//! 本地数据源：在 127.0.0.1 的随机端口上提供一个极小的 HTTP API。
//!
//! 前端在「本地数据」模式下请求本地服务，页面代码与云端模式完全一致。
//! 数据落在 <exe 目录>/data/local.db，与云端库**完全独立**。
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
///
/// 本地库只对当前 Windows 用户开放（服务绑定 127.0.0.1），
/// 因此不需要 Argon2 那种级别的成本，但仍然避免明文落盘。
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

/// 读取 app.tokens（桌面端按数据源保存的令牌表）。
fn read_token_map(conn: &Connection) -> serde_json::Map<String, serde_json::Value> {
    let raw = conn
        .query_row(
            "SELECT value FROM settings WHERE key = ?1",
            params!["app.tokens"],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .ok()
        .flatten();

    let Some(raw) = raw else {
        return serde_json::Map::new();
    };

    // settings 表的值是 JSON 编码的字符串（write_setting 多包了一层），
    // 先解出内层字符串，再解析成 map。
    let inner = serde_json::from_str::<String>(&raw).unwrap_or(raw);
    serde_json::from_str::<serde_json::Map<String, serde_json::Value>>(&inner)
        .unwrap_or_default()
}

/// 写 settings 表（值以 JSON 字符串形式存储，与 settings 路由保持一致）。
fn write_setting(conn: &Connection, key: &str, value: &str, now: i64) {
    let encoded = serde_json::to_string(value).unwrap_or_default();
    let _ = conn.execute(
        "INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
        params![key, encoded, now],
    );
}

/// 当前请求的 (用户 id, 会话 id)。
fn current_session(state: &AppState, request: &Request) -> Option<(String, String)> {
    let token = bearer_token(request)?;
    let hash = sha256_hex(&token);
    let conn = state.conn.lock().ok()?;

    conn.query_row(
        "SELECT user_id, id FROM sessions
         WHERE token_hash = ?1 AND revoked_at IS NULL AND expires_at > ?2",
        params![hash, now_ms()],
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
    )
    .optional()
    .ok()
    .flatten()
}

/// 会话列表（不含 token 摘要）。
fn list_sessions_json(
    conn: &Connection,
    user_id: &str,
    current_id: &str,
) -> rusqlite::Result<Vec<serde_json::Value>> {
    let mut statement = conn.prepare(
        "SELECT id, kind, device_name, user_agent, ip, created_at, last_used_at, expires_at
         FROM sessions
         WHERE user_id = ?1 AND revoked_at IS NULL
         ORDER BY last_used_at DESC",
    )?;
    let rows = statement.query_map(params![user_id], |row| {
        let id: String = row.get(0)?;
        Ok(serde_json::json!({
            "id": id,
            "kind": row.get::<_, String>(1)?,
            "deviceName": row.get::<_, Option<String>>(2)?,
            "userAgent": row.get::<_, Option<String>>(3)?,
            "ip": row.get::<_, Option<String>>(4)?,
            "createdAt": row.get::<_, i64>(5)?,
            "lastUsedAt": row.get::<_, i64>(6)?,
            "expiresAt": row.get::<_, i64>(7)?,
            "current": id == current_id
        }))
    })?;
    Ok(rows.flatten().collect())
}

/// 本地凭据混淆。
///
/// 本地库只对本机当前用户开放（服务绑定 127.0.0.1），
/// 这里做一层可逆混淆，避免明文直接躺在 SQLite 里被随手看见。
/// 真正的安全边界是文件系统权限，不是这层编码。
pub fn obfuscate(plain: &str) -> String {
    use base64::Engine as _;
    base64::engine::general_purpose::STANDARD.encode(plain.as_bytes())
}

fn deobfuscate(encoded: &str) -> Option<String> {
    use base64::Engine as _;
    base64::engine::general_purpose::STANDARD
        .decode(encoded.as_bytes())
        .ok()
        .and_then(|bytes| String::from_utf8(bytes).ok())
}

/// 服务器列表（不含凭据）。
fn list_servers_json(conn: &Connection) -> rusqlite::Result<Vec<serde_json::Value>> {
    let mut statement = conn.prepare(
        "SELECT id, name, host, port, username, auth_type,
                password_cipher, private_key_cipher, created_at, updated_at, last_connected_at
         FROM servers ORDER BY name",
    )?;
    let rows = statement.query_map([], |row| {
        Ok(server_row_json(
            row.get(0)?,
            row.get(1)?,
            row.get(2)?,
            row.get(3)?,
            row.get(4)?,
            row.get(5)?,
            row.get::<_, Option<String>>(6)?.is_some(),
            row.get::<_, Option<String>>(7)?.is_some(),
            row.get(8)?,
            row.get(9)?,
            row.get(10)?,
        ))
    })?;
    Ok(rows.flatten().collect())
}

fn get_server_json(conn: &Connection, id: &str) -> Option<serde_json::Value> {
    conn.query_row(
        "SELECT id, name, host, port, username, auth_type,
                password_cipher, private_key_cipher, created_at, updated_at, last_connected_at
         FROM servers WHERE id = ?1",
        params![id],
        |row| {
            Ok(server_row_json(
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
                row.get::<_, Option<String>>(6)?.is_some(),
                row.get::<_, Option<String>>(7)?.is_some(),
                row.get(8)?,
                row.get(9)?,
                row.get(10)?,
            ))
        },
    )
    .optional()
    .ok()
    .flatten()
}

#[allow(clippy::too_many_arguments)]
fn server_row_json(
    id: String,
    name: String,
    host: String,
    port: i64,
    username: String,
    auth_type: String,
    has_password: bool,
    has_key: bool,
    created_at: i64,
    updated_at: i64,
    last_connected_at: Option<i64>,
) -> serde_json::Value {
    let has_credential = if auth_type == "password" { has_password } else { has_key };
    serde_json::json!({
        "id": id,
        "name": name,
        "host": host,
        "port": port,
        "username": username,
        "authType": auth_type,
        "hasCredential": has_credential,
        "createdAt": created_at,
        "updatedAt": updated_at,
        "lastConnectedAt": last_connected_at
    })
}

/// 一次性凭据（明文，仅供建立连接）。
fn server_credential_json(conn: &Connection, id: &str) -> Option<serde_json::Value> {
    conn.query_row(
        "SELECT id, host, port, username, auth_type, password_cipher, private_key_cipher
         FROM servers WHERE id = ?1",
        params![id],
        |row| {
            Ok(serde_json::json!({
                "id": row.get::<_, String>(0)?,
                "host": row.get::<_, String>(1)?,
                "port": row.get::<_, i64>(2)?,
                "username": row.get::<_, String>(3)?,
                "authType": row.get::<_, String>(4)?,
                "password": row.get::<_, Option<String>>(5)?.and_then(|v| deobfuscate(&v)),
                "privateKey": row.get::<_, Option<String>>(6)?.and_then(|v| deobfuscate(&v)),
                "passphrase": serde_json::Value::Null
            }))
        },
    )
    .optional()
    .ok()
    .flatten()
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

    /*
     * 已有数据库的增量升级。
     *
     * 0000_init.sql 里的建表都带 IF NOT EXISTS，但老版本创建的库不会自动
     * 补上后来新增的表。这里用一条幂等语句兜底，保证升级后能直接用。
     */
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS servers (
           id text PRIMARY KEY NOT NULL,
           name text NOT NULL,
           host text NOT NULL,
           port integer DEFAULT 22 NOT NULL,
           username text NOT NULL,
           auth_type text NOT NULL,
           password_cipher text,
           private_key_cipher text,
           passphrase_cipher text,
           created_at integer NOT NULL,
           updated_at integer NOT NULL,
           last_connected_at integer
         );",
    )?;

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

        // 初始化状态：本地与云端行为一致 —— 没有账号时要求注册。
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
                    serde_json::json!({
                        "initialized": count > 0,
                        "username": username,
                        "authMode": "password"
                    })
                }
                Err(_) => {
                    respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                    return;
                }
            };
            respond_json(request, 200, &payload);
        }

        // 首次注册：仅当本地库里没有用户时成功（单用户系统）。
        (Method::Post, "/api/auth/bootstrap") => {
            let body = read_body(&mut request);
            let username = body["username"].as_str().unwrap_or_default().trim().to_string();
            let password = body["password"].as_str().unwrap_or_default().to_string();
            let now = now_ms();

            if username.trim().is_empty() {
                respond_json(request, 400, &error_body("VALIDATION_FAILED", "用户名不能为空"));
                return;
            }
            if username.chars().count() > 32 {
                respond_json(request, 400, &error_body("VALIDATION_FAILED", "用户名最多 32 个字符"));
                return;
            }
            if password.is_empty() {
                respond_json(request, 400, &error_body("VALIDATION_FAILED", "密码不能为空"));
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
                    &error_body("ALREADY_INITIALIZED", "账号已创建，请直接登录"),
                );
                return;
            }

            let id = format!("user-{now}");
            let inserted = conn.execute(
                "INSERT INTO users (id, username, password_hash, display_name, created_at, updated_at, password_changed_at, last_login_at)
                 VALUES (?1, ?2, ?3, ?2, ?4, ?4, ?4, ?4)",
                params![id, username, hash_password(&password), now],
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
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
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
            if !verify_password(&hash, &password) {
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

        // 桌面端令牌存取：按数据源分别保存，存在本地库 settings 表（app.tokens）里。
        // 结构：{ "local": "<token>", "cloud:http://1.2.3.4:3000": "<token>" }
        // 切换数据源只影响当前源的令牌，其它源保留，切回来无需重新登录。
        // 数据随 exe 目录走，不写 AppData，也不需要 store 插件。
        (Method::Get, "/api/app/tokens") => {
            let payload = match state.conn.lock() {
                Ok(conn) => serde_json::json!({ "tokens": read_token_map(&conn) }),
                Err(_) => {
                    respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                    return;
                }
            };
            respond_json(request, 200, &payload);
        }

        (Method::Put, "/api/app/tokens") => {
            let body = read_body(&mut request);
            let now = now_ms();
            let conn = match state.conn.lock() {
                Ok(conn) => conn,
                Err(_) => {
                    respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                    return;
                }
            };

            // 载入现有 map，按 key 增删改
            let mut map = read_token_map(&conn);
            if let Some(obj) = body["tokens"].as_object() {
                for (key, value) in obj {
                    match value.as_str() {
                        Some(token) if !token.is_empty() => {
                            map.insert(key.clone(), serde_json::Value::String(token.to_string()));
                        }
                        // null 或空串 = 删除该数据源的令牌
                        _ => {
                            map.remove(key);
                        }
                    }
                }
            }

            if map.is_empty() {
                let _ = conn.execute("DELETE FROM settings WHERE key = ?1", params!["app.tokens"]);
            } else {
                write_setting(
                    &conn,
                    "app.tokens",
                    &serde_json::to_string(&map).unwrap_or_default(),
                    now,
                );
            }
            drop(conn);
            respond_empty(request, 204);
        }

        // ---- 登录会话（设置页「登录设备」） ----
        (Method::Get, "/api/auth/sessions") => {
            let Some((user_id, current_id)) = current_session(state, &request) else {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            };

            let items = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                        return;
                    }
                };
                list_sessions_json(&conn, &user_id, &current_id).unwrap_or_default()
            };
            respond_json(request, 200, &serde_json::json!({ "items": items }));
        }

        (Method::Delete, path) if path.starts_with("/api/auth/sessions/") => {
            let Some((user_id, current_id)) = current_session(state, &request) else {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            };
            let id = path.trim_start_matches("/api/auth/sessions/").to_string();
            if id == "revoke-all" {
                respond_json(request, 404, &error_body("NOT_FOUND", "资源不存在"));
                return;
            }

            let ok = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                        return;
                    }
                };
                // 只允许撤销自己的会话
                conn.execute(
                    "UPDATE sessions SET revoked_at = ?1 WHERE id = ?2 AND user_id = ?3",
                    params![now_ms(), id, user_id],
                )
                .unwrap_or(0)
                    > 0
            };

            if ok {
                respond_empty(request, 204);
            } else {
                respond_json(request, 404, &error_body("NOT_FOUND", "会话不存在"));
            }
        }

        (Method::Post, "/api/auth/sessions/revoke-all") => {
            let Some((user_id, current_id)) = current_session(state, &request) else {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            };
            {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                        return;
                    }
                };
                let _ = conn.execute(
                    "UPDATE sessions SET revoked_at = ?1
                     WHERE user_id = ?2 AND id != ?3 AND revoked_at IS NULL",
                    params![now_ms(), user_id, current_id],
                );
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

        // ---- 服务器（远程管理） ----
        (Method::Get, "/api/servers") if path == "/api/servers" => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let items = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                        return;
                    }
                };
                list_servers_json(&conn).unwrap_or_default()
            };
            respond_json(request, 200, &serde_json::json!({ "items": items }));
        }

        (Method::Post, path) if path.starts_with("/api/servers/") && path.ends_with("/credential") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let id = path
                .trim_start_matches("/api/servers/")
                .trim_end_matches("/credential")
                .to_string();

            let payload = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                        return;
                    }
                };
                let _ = conn.execute(
                    "UPDATE servers SET last_connected_at = ?1 WHERE id = ?2",
                    params![now_ms(), id],
                );
                server_credential_json(&conn, &id)
            };

            match payload {
                Some(value) => respond_json(request, 200, &value),
                None => respond_json(request, 404, &error_body("NOT_FOUND", "服务器不存在")),
            }
        }

        (Method::Post, "/api/servers") if path == "/api/servers" => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let body = read_body(&mut request);
            let now = now_ms();
            let id = format!("srv-{now}-{}", rand::random::<u16>());

            let name = body["name"].as_str().unwrap_or_default().trim().to_string();
            let host = body["host"].as_str().unwrap_or_default().trim().to_string();
            let username = body["username"].as_str().unwrap_or_default().trim().to_string();
            let port = body["port"].as_i64().unwrap_or(22);
            let auth_type = body["authType"].as_str().unwrap_or("password").to_string();

            if name.is_empty() || host.is_empty() || username.is_empty() {
                respond_json(request, 400, &error_body("VALIDATION_FAILED", "名称、主机与用户名不能为空"));
                return;
            }

            let result = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                        return;
                    }
                };
                conn.execute(
                    "INSERT INTO servers (id, name, host, port, username, auth_type,
                     password_cipher, private_key_cipher, passphrase_cipher,
                     created_at, updated_at, last_connected_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, NULL, ?9, ?9, NULL)",
                    params![
                        id,
                        name,
                        host,
                        port,
                        username,
                        auth_type,
                        body["password"].as_str().map(crate::local_api::obfuscate),
                        body["privateKey"].as_str().map(crate::local_api::obfuscate),
                        now
                    ],
                )
            };

            match result {
                Ok(_) => {
                    let payload = {
                        let conn = match state.conn.lock() {
                            Ok(conn) => conn,
                            Err(_) => {
                                respond_json(request, 500, &error_body("INTERNAL_ERROR", "读取失败"));
                                return;
                            }
                        };
                        get_server_json(&conn, &id).unwrap_or(serde_json::json!({}))
                    };
                    respond_json(request, 201, &payload);
                }
                Err(error) => {
                    respond_json(
                        request,
                        500,
                        &error_body("INTERNAL_ERROR", &format!("创建失败：{error}")),
                    );
                }
            }
        }


        (Method::Put, path) if path.starts_with("/api/servers/") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let id = path.trim_start_matches("/api/servers/").to_string();
            let body = read_body(&mut request);
            let now = now_ms();

            let ok = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                        return;
                    }
                };
                let affected = conn.execute(
                    "UPDATE servers SET
                       name = COALESCE(?1, name),
                       host = COALESCE(?2, host),
                       port = COALESCE(?3, port),
                       username = COALESCE(?4, username),
                       auth_type = COALESCE(?5, auth_type),
                       password_cipher = CASE WHEN ?6 THEN ?7 ELSE password_cipher END,
                       private_key_cipher = CASE WHEN ?8 THEN ?9 ELSE private_key_cipher END,
                       updated_at = ?10
                     WHERE id = ?11",
                    params![
                        body["name"].as_str(),
                        body["host"].as_str(),
                        body["port"].as_i64(),
                        body["username"].as_str(),
                        body["authType"].as_str(),
                        body.get("password").is_some(),
                        body["password"].as_str().map(obfuscate),
                        body.get("privateKey").is_some(),
                        body["privateKey"].as_str().map(obfuscate),
                        now,
                        id
                    ],
                );
                affected.unwrap_or(0) > 0
            };

            if !ok {
                respond_json(request, 404, &error_body("NOT_FOUND", "服务器不存在"));
                return;
            }

            let payload = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "读取失败"));
                        return;
                    }
                };
                get_server_json(&conn, &id).unwrap_or(serde_json::json!({}))
            };
            respond_json(request, 200, &payload);
        }

        (Method::Delete, path) if path.starts_with("/api/servers/") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let id = path.trim_start_matches("/api/servers/").to_string();
            let ok = {
                let conn = match state.conn.lock() {
                    Ok(conn) => conn,
                    Err(_) => {
                        respond_json(request, 500, &error_body("INTERNAL_ERROR", "本地数据库不可用"));
                        return;
                    }
                };
                conn.execute("DELETE FROM servers WHERE id = ?1", params![id])
                    .unwrap_or(0)
                    > 0
            };
            if ok {
                respond_empty(request, 204);
            } else {
                respond_json(request, 404, &error_body("NOT_FOUND", "服务器不存在"));
            }
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