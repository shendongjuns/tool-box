//! 本地数据源：在 127.0.0.1 的随机端口上提供一个极小的 HTTP API。
//!
//! 前端在「本地数据」模式下请求本地服务，页面代码与云端模式完全一致。
//! 数据落在 %APPDATA%\com.shendongjuns.toolbox\local.db，与云端库**完全独立**。

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tiny_http::{Header, Method, Response, Server, StatusCode};

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
/// 本地库只对当前电脑的用户开放，用轻量哈希即可避免明文落盘。
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

fn json_header() -> Header {
    Header::from_bytes(&b"Content-Type"[..], &b"application/json; charset=utf-8"[..]).unwrap()
}

fn respond_json<T: Serialize>(request: tiny_http::Request, status: u16, body: &T) {
    let payload = serde_json::to_string(body).unwrap_or_else(|_| "{}".to_string());
    let response = Response::from_string(payload)
        .with_status_code(StatusCode(status))
        .with_header(json_header());
    let _ = request.respond(response);
}

fn respond_empty(request: tiny_http::Request, status: u16) {
    let _ = request.respond(Response::empty(StatusCode(status)));
}


fn error_body(code: &str, message: &str) -> serde_json::Value {
    serde_json::json!({ "code": code, "message": message })
}

fn read_body(request: &mut tiny_http::Request) -> serde_json::Value {
    let mut buffer = String::new();
    let _ = request.as_reader().read_to_string(&mut buffer);
    serde_json::from_str(&buffer).unwrap_or(serde_json::Value::Null)
}

fn bearer_token(request: &tiny_http::Request) -> Option<String> {
    request
        .headers()
        .iter()
        .find(|header| header.field.equiv("Authorization"))
        .and_then(|header| header.value.as_str().strip_prefix("Bearer ").map(str::to_string))
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

fn current_user(state: &AppState, request: &tiny_http::Request) -> Option<LocalUser> {
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

    // 滑动续期：命中即延后 30 天，本地写入极快，无需节流
    let _ = conn.execute(
        "UPDATE sessions SET last_used_at = ?1, expires_at = ?2 WHERE token_hash = ?3",
        params![now, now + 30 * 24 * 3600 * 1000, token_hash],
    );

    find_user(&conn, &user_id)
}

fn issue_session(state: &AppState, user_id: &str) -> Option<(String, i64)> {
    let bytes: [u8; 32] = rand::random();
    let token = hex_encode(&bytes);
    let now = now_ms();
    let expires_at = now + 30 * 24 * 3600 * 1000;
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
    conn.execute_batch(include_str!("../migrations/0000_init.sql"))?;
    Ok(conn)
}

/// 启动本地服务，返回实际端口。
pub fn start(db_path: PathBuf) -> Result<u16, String> {
    let conn = init_db(&db_path).map_err(|error| format!("初始化本地数据库失败: {error}"))?;
    let state = AppState {
        conn: Arc::new(Mutex::new(conn)),
    };

    let server = Server::http("127.0.0.1:0").map_err(|error| format!("本地服务启动失败: {error}"))?;
    let port = server
        .server_addr()
        .to_ip()
        .map(|addr| addr.port())
        .ok_or_else(|| "无法获取本地服务端口".to_string())?;

    let shared = state;
    std::thread::spawn(move || {
        for request in server.incoming_requests() {
            let state = shared.clone();
            std::thread::spawn(move || handle(&state, request));
        }
    });

    Ok(port)
}

fn handle(state: &AppState, mut request: tiny_http::Request) {
    let method = request.method().clone();
    let url = request.url().to_string();
    let path = url.split('?').next().unwrap_or("/").to_string();

    match (&method, path.as_str()) {
        (Method::Get, "/api/health") => {
            respond_json(request, 200, &serde_json::json!({ "status": "ok", "db": "ok", "source": "local" }));
        }

        (Method::Get, "/api/auth/bootstrap") => {
            let count: i64 = {
                let conn = state.conn.lock().unwrap();
                conn.query_row("SELECT COUNT(*) FROM users", [], |row| row.get(0)).unwrap_or(0)
            };
            respond_json(request, 200, &serde_json::json!({ "initialized": count > 0, "requireSetupToken": false }));
        }

        (Method::Post, "/api/auth/bootstrap") => {
            let body = read_body(&mut request);
            let username = body["username"].as_str().unwrap_or_default().to_string();
            let password = body["password"].as_str().unwrap_or_default().to_string();
            let now = now_ms();

            let conn = state.conn.lock().unwrap();
            let count: i64 = conn.query_row("SELECT COUNT(*) FROM users", [], |row| row.get(0)).unwrap_or(0);
            if count > 0 {
                drop(conn);
                respond_json(request, 409, &error_body("ALREADY_INITIALIZED", "系统已完成初始化，请直接登录"));
                return;
            }
            if password.len() < 10 {
                drop(conn);
                respond_json(request, 400, &error_body("VALIDATION_FAILED", "密码至少 10 个字符"));
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
                    "session": { "createdAt": now, "lastUsedAt": now, "expiresAt": expires_at, "kind": "local" },
                    "user": { "id": id, "username": username, "displayName": username, "createdAt": now, "lastLoginAt": now }
                }),
            );
        }

        (Method::Post, "/api/auth/login") | (Method::Post, "/api/auth/desktop-login") => {
            let body = read_body(&mut request);
            let username = body["username"].as_str().unwrap_or_default().to_string();
            let password = body["password"].as_str().unwrap_or_default().to_string();
            let now = now_ms();

            let found: Option<(String, String, Option<String>, i64, Option<i64>)> = {
                let conn = state.conn.lock().unwrap();
                conn.query_row(
                    "SELECT id, password_hash, display_name, created_at, last_login_at FROM users WHERE username = ?1",
                    params![username],
                    |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
                )
                .optional()
                .unwrap_or(None)
            };

            let Some((id, hash, display_name, created_at, _)) = found else {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "用户名或密码不正确"));
                return;
            };
            if !verify_password(&hash, &password) {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "用户名或密码不正确"));
                return;
            }
            {
                let conn = state.conn.lock().unwrap();
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
                respond_json(request, 200, &serde_json::json!({ "token": token, "expiresAt": expires_at, "user": user }));
            } else {
                respond_json(
                    request,
                    200,
                    &serde_json::json!({
                        "token": token,
                        "session": { "createdAt": now, "lastUsedAt": now, "expiresAt": expires_at, "kind": "local" },
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
                        "session": { "createdAt": user.created_at, "lastUsedAt": now, "expiresAt": now + 30 * 24 * 3600 * 1000, "kind": "local" }
                    }),
                );
            }
            None => respond_json(request, 401, &error_body("UNAUTHENTICATED", "登录已过期，请重新登录")),
        },

        (Method::Post, "/api/auth/logout") => {
            if let Some(token) = bearer_token(&request) {
                let conn = state.conn.lock().unwrap();
                let _ = conn.execute(
                    "UPDATE sessions SET revoked_at = ?1 WHERE token_hash = ?2",
                    params![now_ms(), sha256_hex(&token)],
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
                let conn = state.conn.lock().unwrap();
                let rows = conn
                    .prepare("SELECT key, value FROM settings")
                    .and_then(|mut statement| {
                        statement
                            .query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)))
                            .map(|iter| iter.flatten().collect::<Vec<_>>())
                    })
                    .unwrap_or_default();
                let mut map = serde_json::Map::new();
                for (key, value) in rows {
                    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&value) {
                        map.insert(key, parsed);
                    }
                }
                map
            };
            respond_json(request, 200, &serde_json::json!({ "values": values, "updatedAt": null }));
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
            {
                let conn = state.conn.lock().unwrap();
                for (key, value) in map {
                    let encoded = serde_json::to_string(value).unwrap_or_default();
                    let _ = conn.execute(
                        "INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
                         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
                        params![key, encoded, now_ms()],
                    );
                }
            }
            respond_json(request, 200, &serde_json::json!({ "values": map, "updatedAt": now_ms() }));
        }

        (Method::Get, "/api/tools") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let items = {
                let conn = state.conn.lock().unwrap();
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
            respond_json(
                request,
                200,
                &serde_json::json!({
                    "stats": { "totalTools": 6, "pinnedTools": 0, "activeSessions": 1, "settingsCount": 0 },
                    "recentTools": [],
                    "lastActiveAt": now_ms(),
                    "server": { "version": "2.0.0", "uptime": 0, "dataSource": "cloud" }
                }),
            );
        }

        _ => respond_json(request, 404, &error_body("NOT_FOUND", "资源不存在")),
    }
}