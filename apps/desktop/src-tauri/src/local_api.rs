//! 本地数据源：在 127.0.0.1 的随机端口上提供一个极小的 HTTP API。
//!
//! 前端在「本地数据」模式下请求本地服务，页面代码与云端模式完全一致。
//! 数据落在 %APPDATA%\com.shendongjuns.toolbox\local.db，与云端库**完全独立**。
//!
//! 注意：WebView 的 origin 是 tauri://localhost（或 http://tauri.localhost），
//! 请求 127.0.0.1 属于跨源，因此每个响应都必须带 CORS 头，并处理 OPTIONS 预检。

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tiny_http::{Header, Method, Request, Response, Server, StatusCode};

const SESSION_TTL_MS: i64 = 30 * 24 * 3600 * 1000;

#[derive(Clone)]
struct AppState {
    conn: Arc<Mutex<Connection>>,
}

struct LocalUser {
    id: String,
    username: String,
    display_name: Option<String>,
    created_at: i64,
    last_login_at: Option<i64>,
}

fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn sha256_hex(value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_bytes());
    hex_encode(&hasher.finalize())
}

/// 本地密码哈希：sha256(salt + password)，salt 存在哈希串里。
fn hash_password(password: &str) -> String {
    let salt: [u8; 16] = rand::random();
    let salt_hex = hex_encode(&salt);
    let digest = sha256_hex(&format!("{salt_hex}{password}"));
    format!("{salt_hex}:{digest}")
}

fn verify_password(stored: &str, password: &str) -> bool {
    let mut parts = stored.splitn(2, ':');
    let (Some(salt), Some(expected)) = (parts.next(), parts.next()) else {
        return false;
    };
    sha256_hex(&format!("{salt}{password}")) == expected
}

/// 本地数据源的访问模式。
///
/// 只存在于桌面端本地库：`None` = 无密码（打开即用），`Password` = 需要密码。
/// 云端服务端没有这个概念，永远要求密码。
#[derive(Clone, Copy, PartialEq, Eq)]
enum AuthMode {
    None,
    Password,
}

const AUTH_MODE_KEY: &str = "auth.mode";
const LOCAL_USERNAME_KEY: &str = "auth.username";

fn read_setting(conn: &Connection, key: &str) -> Option<String> {
    conn.query_row(
        "SELECT value FROM settings WHERE key = ?1",
        params![key],
        |row| row.get::<_, String>(0),
    )
    .optional()
    .ok()
    .flatten()
    .and_then(|raw| serde_json::from_str::<String>(&raw).ok())
}

fn write_setting(conn: &Connection, key: &str, value: &str, now: i64) {
    let encoded = serde_json::to_string(value).unwrap_or_default();
    let _ = conn.execute(
        "INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
        params![key, encoded, now],
    );
}

/// 桌面端默认无密码；只有显式设置成 password 才要求密码。
fn auth_mode_of(conn: &Connection) -> AuthMode {
    match read_setting(conn, AUTH_MODE_KEY).as_deref() {
        Some("password") => AuthMode::Password,
        _ => AuthMode::None,
    }
}

fn header(name: &str, value: &str) -> Header {
    Header::from_bytes(name.as_bytes(), value.as_bytes()).expect("valid header")
}

/// 所有响应共用的头：CORS + 禁止缓存 + JSON。
fn base_headers() -> Vec<Header> {
    vec![
        header("Content-Type", "application/json; charset=utf-8"),
        // WebView 的 origin 是 tauri://localhost，必须允许跨源
        header("Access-Control-Allow-Origin", "*"),
        header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS"),
        header(
            "Access-Control-Allow-Headers",
            "Content-Type, Authorization, X-Toolbox-Client",
        ),
        header("Access-Control-Max-Age", "600"),
        header("Cache-Control", "no-store"),
    ]
}

fn respond_json<T: Serialize>(request: Request, status: u16, body: &T) {
    let payload = serde_json::to_string(body).unwrap_or_else(|_| "{}".to_string());
    let mut response = Response::from_string(payload).with_status_code(StatusCode(status));
    for item in base_headers() {
        response.add_header(item);
    }
    let _ = request.respond(response);
}

fn respond_empty(request: Request, status: u16) {
    let mut response = Response::empty(StatusCode(status));
    for item in base_headers() {
        response.add_header(item);
    }
    let _ = request.respond(response);
}

fn error_body(code: &str, message: &str) -> serde_json::Value {
    serde_json::json!({ "code": code, "message": message })
}

fn read_body(request: &mut Request) -> serde_json::Value {
    let mut buffer = String::new();
    let _ = request.as_reader().read_to_string(&mut buffer);
    serde_json::from_str(&buffer).unwrap_or(serde_json::Value::Null)
}

fn bearer_token(request: &Request) -> Option<String> {
    request
        .headers()
        .iter()
        .find(|item| item.field.equiv("Authorization"))
        .and_then(|item| item.value.as_str().strip_prefix("Bearer ").map(str::to_string))
}

fn find_user(conn: &Connection, user_id: &str) -> Option<LocalUser> {
    conn.query_row(
        "SELECT id, username, display_name, created_at, last_login_at FROM users WHERE id = ?1",
        params![user_id],
        |row| {
            Ok(LocalUser {
                id: row.get(0)?,
                username: row.get(1)?,
                display_name: row.get(2)?,
                created_at: row.get(3)?,
                last_login_at: row.get(4)?,
            })
        },
    )
    .optional()
    .ok()?
}

fn current_user(state: &AppState, request: &Request) -> Option<LocalUser> {
    let token = bearer_token(request)?;
    let token_hash = sha256_hex(&token);
    let now = now_ms();
    let conn = state.conn.lock().ok()?;

    let user_id: Option<String> = conn
        .query_row(
            "SELECT user_id FROM sessions WHERE token_hash = ?1 AND revoked_at IS NULL AND expires_at > ?2",
            params![token_hash, now],
            |row| row.get(0),
        )
        .optional()
        .ok()?;
    let user_id = user_id?;

    // 滑动续期
    let _ = conn.execute(
        "UPDATE sessions SET last_used_at = ?1, expires_at = ?2 WHERE token_hash = ?3",
        params![now, now + SESSION_TTL_MS, token_hash],
    );

    find_user(&conn, &user_id)
}

fn issue_session(state: &AppState, user_id: &str) -> Option<(String, i64)> {
    let bytes: [u8; 32] = rand::random();
    let token = hex_encode(&bytes);
    let now = now_ms();
    let expires_at = now + SESSION_TTL_MS;
    let conn = state.conn.lock().ok()?;
    conn.execute(
        "INSERT INTO sessions (id, user_id, token_hash, kind, device_name, user_agent, ip, created_at, last_used_at, expires_at, revoked_at)
         VALUES (?1, ?2, ?3, 'local', '本机', NULL, '127.0.0.1', ?4, ?4, ?5, NULL)",
        params![format!("local-{now}"), user_id, sha256_hex(&token), now, expires_at],
    )
    .ok()?;
    Some((token, expires_at))
}

fn init_db(path: &PathBuf) -> rusqlite::Result<Connection> {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let conn = Connection::open(path)?;
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "busy_timeout", 5000)?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.execute_batch(include_str!("../migrations/0000_init.sql"))?;
    Ok(conn)
}

/// 启动本地服务，返回实际端口。
pub fn start(db_path: PathBuf) -> Result<u16, String> {
    let conn = init_db(&db_path).map_err(|error| format!("初始化本地数据库失败: {error}"))?;
    let state = AppState {
        conn: Arc::new(Mutex::new(conn)),
    };

    let server =
        Server::http("127.0.0.1:0").map_err(|error| format!("本地服务启动失败: {error}"))?;
    let port = server
        .server_addr()
        .to_ip()
        .map(|addr| addr.port())
        .ok_or_else(|| "无法获取本地服务端口".to_string())?;

    std::thread::spawn(move || {
        for request in server.incoming_requests() {
            let state = state.clone();
            std::thread::spawn(move || handle(&state, request));
        }
    });

    Ok(port)
}

fn session_json(now: i64, expires_at: i64) -> serde_json::Value {
    serde_json::json!({
        "createdAt": now,
        "lastUsedAt": now,
        "expiresAt": expires_at,
        "kind": "local"
    })
}

fn handle(state: &AppState, mut request: Request) {
    let method = request.method().clone();
    let url = request.url().to_string();
    let path = url.split('?').next().unwrap_or("/").to_string();

    // CORS 预检：必须单独处理，否则浏览器/WebView 会在真正请求前就失败
    if method == Method::Options {
        respond_empty(request, 204);
        return;
    }

    match (&method, path.as_str()) {
        (Method::Get, "/api/health") => {
            respond_json(
                request,
                200,
                &serde_json::json!({ "status": "ok", "db": "ok", "source": "local" }),
            );
        }

        (Method::Get, "/api/auth/bootstrap") => {
            let payload = match state.conn.lock() {
                Ok(conn) => {
                    let count: i64 = conn
                        .query_row("SELECT COUNT(*) FROM users", [], |row| row.get(0))
                        .unwrap_or(0);
                    let username: Option<String> = conn
                        .query_row("SELECT username FROM users LIMIT 1", [], |row| {
                            row.get::<_, String>(0)
                        })
                        .optional()
                        .unwrap_or(None);
                    let mode = auth_mode_of(&conn);
                    serde_json::json!({
                        "initialized": count > 0,
                        "username": username,
                        "passwordless": mode == AuthMode::None
                    })
                }
                Err(_) => {
                    respond_json(
                        request,
                        500,
                        &error_body("INTERNAL_ERROR", "本地数据库不可用"),
                    );
                    return;
                }
            };
            respond_json(request, 200, &payload);
        }

        // 无密码模式下的一键进入。
        //
        // 本地库只有一个用户，且服务只监听 127.0.0.1，因此这里不需要凭据：
        // 直接为库里已有的账号签发会话。开启密码模式后此接口返回 403。
        (Method::Post, "/api/auth/local-session") => {
            let conn = match state.conn.lock() {
                Ok(conn) => conn,
                Err(_) => {
                    respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                    return;
                }
            };
            if auth_mode_of(&conn) == AuthMode::Password {
                drop(conn);
                respond_json(
                    request,
                    403,
                    &error_body("PASSWORD_REQUIRED", "本地数据源已开启密码，请使用密码登录"),
                );
                return;
            }
            let user: Option<(String, String, Option<String>, i64, Option<i64>)> = conn
                .query_row(
                    "SELECT id, username, display_name, created_at, last_login_at FROM users LIMIT 1",
                    [],
                    |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
                )
                .optional()
                .unwrap_or(None);
            drop(conn);

            let Some((id, username, display_name, created_at, _)) = user else {
                respond_json(
                    request,
                    404,
                    &error_body("NOT_INITIALIZED", "本地还没有账号"),
                );
                return;
            };

            let now = now_ms();
            if let Ok(conn) = state.conn.lock() {
                let _ = conn.execute(
                    "UPDATE users SET last_login_at = ?1, updated_at = ?1 WHERE id = ?2",
                    params![now, id],
                );
            }
            let Some((token, expires_at)) = issue_session(state, &id) else {
                respond_json(request, 500, &error_body("INTERNAL_ERROR", "创建会话失败"));
                return;
            };
            respond_json(
                request,
                200,
                &serde_json::json!({
                    "token": token,
                    "session": session_json(now, expires_at),
                    "user": {
                        "id": id, "username": username, "displayName": display_name,
                        "createdAt": created_at, "lastLoginAt": now
                    }
                }),
            );
        }

        // 切换本地访问模式：无密码 / 需要密码。
        (Method::Put, "/api/auth/local-mode") => {
            let body = read_body(&mut request);
            let mode = body["mode"].as_str().unwrap_or_default();
            let username = body["username"].as_str().unwrap_or_default().trim().to_string();
            let password = body["password"].as_str().unwrap_or_default().to_string();
            let now = now_ms();

            if mode != "none" && mode != "password" {
                respond_json(
                    request,
                    400,
                    &error_body("VALIDATION_FAILED", "mode 只能是 none 或 password"),
                );
                return;
            }

            if mode == "password" {
                if username.len() < 3 {
                    respond_json(
                        request,
                        400,
                        &error_body("VALIDATION_FAILED", "用户名至少 3 个字符"),
                    );
                    return;
                }
                if password.len() < 10 {
                    respond_json(
                        request,
                        400,
                        &error_body("VALIDATION_FAILED", "密码至少 10 个字符"),
                    );
                    return;
                }
            }

            let conn = match state.conn.lock() {
                Ok(conn) => conn,
                Err(_) => {
                    respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                    return;
                }
            };

            let existing: Option<(String, i64)> = conn
                .query_row(
                    "SELECT id, created_at FROM users LIMIT 1",
                    [],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .optional()
                .unwrap_or(None);

            match mode {
                "password" => {
                    match existing {
                        // 已有账号：更新用户名与密码
                        Some((id, _)) => {
                            let _ = conn.execute(
                                "UPDATE users SET username = ?1, password_hash = ?2, display_name = ?1,
                                 updated_at = ?3, password_changed_at = ?3 WHERE id = ?4",
                                params![username, hash_password(&password), now, id],
                            );
                        }
                        // 还没有账号：创建
                        None => {
                            let id = format!("user-{now}");
                            let _ = conn.execute(
                                "INSERT INTO users (id, username, password_hash, display_name, created_at, updated_at, password_changed_at, last_login_at)
                                 VALUES (?1, ?2, ?3, ?2, ?4, ?4, ?4, ?4)",
                                params![id, username, hash_password(&password), now],
                            );
                        }
                    }
                    write_setting(&conn, AUTH_MODE_KEY, "password", now);
                    write_setting(&conn, LOCAL_USERNAME_KEY, &username, now);
                    // 开启密码后，撤销所有现存会话，强制重新登录
                    let _ = conn.execute(
                        "UPDATE sessions SET revoked_at = ?1 WHERE revoked_at IS NULL",
                        params![now],
                    );
                }
                _ => {
                    write_setting(&conn, AUTH_MODE_KEY, "none", now);
                }
            }
            drop(conn);

            respond_json(
                request,
                200,
                &serde_json::json!({ "mode": mode, "passwordless": mode == "none" }),
            );
        }

        (Method::Post, "/api/auth/bootstrap") => {
            let body = read_body(&mut request);
            let username = body["username"].as_str().unwrap_or_default().trim().to_string();
            let password = body["password"].as_str().unwrap_or_default().to_string();
            let now = now_ms();

            if username.len() < 3 {
                respond_json(
                    request,
                    400,
                    &error_body("VALIDATION_FAILED", "用户名至少 3 个字符"),
                );
                return;
            }
            let conn = match state.conn.lock() {
                Ok(conn) => conn,
                Err(_) => {
                    respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                    return;
                }
            };
            let count: i64 = conn
                .query_row("SELECT COUNT(*) FROM users", [], |row| row.get(0))
                .unwrap_or(0);
            if count > 0 {
                drop(conn);
                respond_json(
                    request,
                    409,
                    &error_body("ALREADY_INITIALIZED", "管理员已创建，请直接登录"),
                );
                return;
            }
            // 无密码模式允许空密码；密码模式必须满足长度要求
            let mode = auth_mode_of(&conn);
            if mode == AuthMode::Password && password.len() < 10 {
                drop(conn);
                respond_json(request, 400, &error_body("VALIDATION_FAILED", "密码至少 10 个字符"));
                return;
            }

            let id = format!("user-{now}");
            // 无密码模式下写入一个不可用于登录的占位哈希
            let stored_hash = if mode == AuthMode::Password {
                hash_password(&password)
            } else {
                "!passwordless".to_string()
            };
            let inserted = conn.execute(
                "INSERT INTO users (id, username, password_hash, display_name, created_at, updated_at, password_changed_at, last_login_at)
                 VALUES (?1, ?2, ?3, ?2, ?4, ?4, ?4, ?4)",
                params![id, username, stored_hash, now],
            );
            drop(conn);

            if inserted.is_err() {
                respond_json(request, 500, &error_body("INTERNAL_ERROR", "创建本地账号失败"));
                return;
            }
            let Some((token, expires_at)) = issue_session(state, &id) else {
                respond_json(request, 500, &error_body("INTERNAL_ERROR", "创建会话失败"));
                return;
            };

            respond_json(
                request,
                201,
                &serde_json::json!({
                    "token": token,
                    "session": session_json(now, expires_at),
                    "user": {
                        "id": id, "username": username, "displayName": username,
                        "createdAt": now, "lastLoginAt": now
                    }
                }),
            );
        }

        (Method::Post, "/api/auth/login") | (Method::Post, "/api/auth/desktop-login") => {
            let body = read_body(&mut request);
            let username = body["username"].as_str().unwrap_or_default().trim().to_string();
            let password = body["password"].as_str().unwrap_or_default().to_string();
            let now = now_ms();

            let found: Option<(String, String, Option<String>, i64)> = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(
                            request,
                            500,
                            &error_body("INTERNAL_ERROR", "本地数据库不可用"),
                        );
                        return;
                    }
                };
                conn.query_row(
                    "SELECT id, password_hash, display_name, created_at FROM users WHERE username = ?1",
                    params![username],
                    |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
                )
                .optional()
                .unwrap_or(None)
            };

            let Some((id, hash, display_name, created_at)) = found else {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "用户名或密码不正确"));
                return;
            };
            // 占位哈希（无密码模式下创建）永远不能用于密码登录
            if hash == "!passwordless" || !verify_password(&hash, &password) {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "用户名或密码不正确"));
                return;
            }

            if let Ok(conn) = state.conn.lock() {
                let _ = conn.execute(
                    "UPDATE users SET last_login_at = ?1, updated_at = ?1 WHERE id = ?2",
                    params![now, id],
                );
            }

            let Some((token, expires_at)) = issue_session(state, &id) else {
                respond_json(request, 500, &error_body("INTERNAL_ERROR", "创建会话失败"));
                return;
            };

            let user = serde_json::json!({
                "id": id, "username": username, "displayName": display_name,
                "createdAt": created_at, "lastLoginAt": now
            });

            if path == "/api/auth/desktop-login" {
                respond_json(
                    request,
                    200,
                    &serde_json::json!({ "token": token, "expiresAt": expires_at, "user": user }),
                );
            } else {
                respond_json(
                    request,
                    200,
                    &serde_json::json!({
                        "token": token,
                        "session": session_json(now, expires_at),
                        "user": user
                    }),
                );
            }
        }

        (Method::Get, "/api/auth/me") => match current_user(state, &request) {
            Some(user) => {
                let now = now_ms();
                respond_json(
                    request,
                    200,
                    &serde_json::json!({
                        "user": {
                            "id": user.id, "username": user.username, "displayName": user.display_name,
                            "createdAt": user.created_at, "lastLoginAt": user.last_login_at
                        },
                        "session": session_json(now, now + SESSION_TTL_MS)
                    }),
                );
            }
            None => respond_json(
                request,
                401,
                &error_body("UNAUTHENTICATED", "登录已过期，请重新登录"),
            ),
        },

        (Method::Post, "/api/auth/logout") => {
            if let Some(token) = bearer_token(&request) {
                if let Ok(conn) = state.conn.lock() {
                    let _ = conn.execute(
                        "UPDATE sessions SET revoked_at = ?1 WHERE token_hash = ?2",
                        params![now_ms(), sha256_hex(&token)],
                    );
                }
            }
            respond_empty(request, 204);
        }

        (Method::Get, "/api/settings") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let values = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(
                            request,
                            500,
                            &error_body("INTERNAL_ERROR", "本地数据库不可用"),
                        );
                        return;
                    }
                };
                conn.prepare("SELECT key, value FROM settings")
                    .and_then(|mut statement| {
                        statement
                            .query_map([], |row| {
                                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                            })
                            .map(|iter| iter.flatten().collect::<Vec<_>>())
                    })
                    .unwrap_or_default()
            };

            let mut map = serde_json::Map::new();
            for (key, value) in values {
                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&value) {
                    map.insert(key, parsed);
                }
            }
            respond_json(
                request,
                200,
                &serde_json::json!({ "values": map, "updatedAt": now_ms() }),
            );
        }

        (Method::Put, "/api/settings") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let body = read_body(&mut request);
            let Some(map) = body["values"].as_object() else {
                respond_json(request, 400, &error_body("VALIDATION_FAILED", "缺少 values"));
                return;
            };
            let now = now_ms();
            {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(
                            request,
                            500,
                            &error_body("INTERNAL_ERROR", "本地数据库不可用"),
                        );
                        return;
                    }
                };
                for (key, value) in map {
                    let encoded = serde_json::to_string(value).unwrap_or_default();
                    let _ = conn.execute(
                        "INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
                         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
                        params![key, encoded, now],
                    );
                }
            }
            respond_json(
                request,
                200,
                &serde_json::json!({ "values": map, "updatedAt": now }),
            );
        }

        (Method::Get, "/api/tools") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let items = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(
                            request,
                            500,
                            &error_body("INTERNAL_ERROR", "本地数据库不可用"),
                        );
                        return;
                    }
                };
                conn.prepare("SELECT tool_id, pinned, sort_order, last_opened_at FROM tool_prefs")
                    .and_then(|mut statement| {
                        statement
                            .query_map([], |row| {
                                Ok(serde_json::json!({
                                    "id": row.get::<_, String>(0)?,
                                    "pinned": row.get::<_, i64>(1)? != 0,
                                    "sortOrder": row.get::<_, i64>(2)?,
                                    "lastOpenedAt": row.get::<_, Option<i64>>(3)?
                                }))
                            })
                            .map(|iter| iter.flatten().collect::<Vec<_>>())
                    })
                    .unwrap_or_default()
            };
            respond_json(request, 200, &serde_json::json!({ "items": items }));
        }

        (Method::Get, "/api/dashboard") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let (tool_count, settings_count, session_count) = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(
                            request,
                            500,
                            &error_body("INTERNAL_ERROR", "本地数据库不可用"),
                        );
                        return;
                    }
                };
                let tool_count: i64 = conn
                    .query_row("SELECT COUNT(*) FROM tool_prefs", [], |row| row.get(0))
                    .unwrap_or(0);
                let settings_count: i64 = conn
                    .query_row("SELECT COUNT(*) FROM settings", [], |row| row.get(0))
                    .unwrap_or(0);
                let session_count: i64 = conn
                    .query_row(
                        "SELECT COUNT(*) FROM sessions WHERE revoked_at IS NULL AND expires_at > ?1",
                        params![now_ms()],
                        |row| row.get(0),
                    )
                    .unwrap_or(0);
                (tool_count, settings_count, session_count)
            };

            respond_json(
                request,
                200,
                &serde_json::json!({
                    "stats": {
                        "totalTools": tool_count,
                        "pinnedTools": 0,
                        "activeSessions": session_count,
                        "settingsCount": settings_count
                    },
                    "recentTools": [],
                    "lastActiveAt": now_ms(),
                    "server": { "version": "2.0.0", "uptime": 0, "dataSource": "cloud" }
                }),
            );
        }

        _ => respond_json(request, 404, &error_body("NOT_FOUND", "资源不存在")),
    }
}