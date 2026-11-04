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
    /// 数据库文件路径，备份与恢复需要
    db_path: PathBuf,
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

/*
 * 密码哈希：Argon2id，参数与云端保持一致（OWASP 推荐档）。
 *
 * 之前的实现是 sha256(salt + password) —— 单轮 SHA-256 只有微秒级，
 * 攻击者拿到 local.db 后可以用 GPU 每秒尝试上亿次，弱密码几分钟就破。
 * Argon2id 是内存硬算法，19456 KiB / t=2 让每次尝试都要占约 19MB 内存，
 * GPU 无法并行堆叠，暴力破解成本提高几个数量级。
 *
 * 哈希串是 PHC 格式（$argon2id$v=19$m=19456,t=2,p=1$...），
 * 参数随串保存，未来调参不会让旧密码失效。
 */
fn argon2_instance() -> argon2::Argon2<'static> {
    // 19456 KiB = 19 MiB，时间成本 2 轮，单通道
    let params = argon2::Params::new(19456, 2, 1, None)
        .expect("Argon2 参数非法：19456/2/1 是合法组合");
    argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params)
}

fn hash_password(password: &str) -> String {
    use argon2::password_hash::PasswordHasher;
    // argon2 0.6 会自动生成随机 salt 并编码进 PHC 串
    argon2_instance()
        .hash_password(password.as_bytes())
        .map(|hash| hash.to_string())
        .unwrap_or_default()
}

/// 校验密码。
///
/// 兼容旧格式 `salt:sha256hex`：老库里已有账号不会被锁在门外，
/// 登录成功后由调用方触发一次 rehash 升级到 Argon2id。
fn verify_password(stored: &str, password: &str) -> bool {
    use argon2::password_hash::{PasswordVerifier, phc::PasswordHash};

    if stored.starts_with("$argon2") {
        let Ok(parsed) = PasswordHash::new(stored) else {
            return false;
        };
        // 注意：参数取自哈希串本身，不是 argon2_instance() 的配置，
        // 这样调整默认参数后老密码依然能验证。
        return argon2::Argon2::default()
            .verify_password(password.as_bytes(), &parsed)
            .is_ok();
    }

    // 旧格式：salt:sha256(salt+password)
    let mut parts = stored.splitn(2, ':');
    let (Some(salt), Some(expected)) = (parts.next(), parts.next()) else {
        return false;
    };
    sha256_hex(&format!("{salt}{password}")) == expected
}

/// 判断哈希是否需要用新算法重算。
fn needs_rehash(stored: &str) -> bool {
    !stored.starts_with("$argon2")
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

/*
 * 本地凭据加解密（AES-256-GCM）。
 *
 * 之前只是 base64 —— 等于明文。任何人拿到 local.db 都能还原
 * 所有 SSH 密码与私钥。
 *
 * 现在用 AES-256-GCM：密钥由机器名 + 用户名经 Argon2id 派生，不落盘；
 * 每次随机 IV，密文带认证标签，篡改会被发现。
 */
const CRED_VERSION: &str = "v1";

fn credential_key() -> [u8; 32] {
    let mut material = String::from("toolbox-credential-v1");
    if let Ok(name) = std::env::var("COMPUTERNAME") {
        material.push_str(&name);
    }
    if let Ok(user) = std::env::var("USERNAME") {
        material.push_str(&user);
    }
    let params = argon2::Params::new(8192, 2, 1, Some(32)).expect("derive params");
    let argon = argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params);
    let mut out = [0u8; 32];
    let _ = argon.hash_password_into(material.as_bytes(), b"toolbox-cred-salt", &mut out);
    out
}

/// 加密凭据，返回 v1:iv:tag:data。
pub fn encrypt_credential(plain: &str) -> String {
    use aes_gcm::aead::{Aead, KeyInit};
    use aes_gcm::{Aes256Gcm, Nonce};
    let Ok(cipher) = Aes256Gcm::new_from_slice(&credential_key()) else {
        return String::new();
    };
    let iv: [u8; 12] = rand::random();
    match cipher.encrypt(Nonce::from_slice(&iv), plain.as_bytes()) {
        Ok(sealed) if sealed.len() > 16 => {
            let (data, tag) = sealed.split_at(sealed.len() - 16);
            format!("{CRED_VERSION}:{}:{}:{}", hex_encode(&iv), hex_encode(tag), hex_encode(data))
        }
        _ => String::new(),
    }
}

/// 解密凭据。
fn decrypt_credential(stored: &str) -> Option<String> {
    use aes_gcm::aead::{Aead, KeyInit};
    use aes_gcm::{Aes256Gcm, Nonce};
    // 兼容历史 base64 数据
    if !stored.starts_with(&format!("{CRED_VERSION}:")) {
        use base64::Engine as _;
        return base64::engine::general_purpose::STANDARD
            .decode(stored.as_bytes())
            .ok()
            .and_then(|bytes| String::from_utf8(bytes).ok());
    }
    let parts: Vec<&str> = stored.split(':').collect();
    if parts.len() != 4 {
        return None;
    }
    let iv = hex_decode(parts.get(1)?)?;
    let tag = hex_decode(parts.get(2)?)?;
    let data = hex_decode(parts.get(3)?)?;
    if iv.len() != 12 || tag.len() != 16 {
        return None;
    }
    let cipher = Aes256Gcm::new_from_slice(&credential_key()).ok()?;
    let mut sealed = data;
    sealed.extend_from_slice(&tag);
    cipher.decrypt(Nonce::from_slice(&iv), sealed.as_slice()).ok()
        .and_then(|bytes| String::from_utf8(bytes).ok())
}

fn hex_decode(value: &str) -> Option<Vec<u8>> {
    if value.len() % 2 != 0 {
        return None;
    }
    (0..value.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&value[i..i + 2], 16).ok())
        .collect()
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
                "password": row.get::<_, Option<String>>(5)?.and_then(|v| decrypt_credential(&v)),
                "privateKey": row.get::<_, Option<String>>(6)?.and_then(|v| decrypt_credential(&v)),
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
/// 是否允许该 Origin 访问本地 API。
///
/// 只允许 Tauri WebView 自身。之前用 `*`，意味着浏览器里打开的任意网页
/// 都能直接请求 127.0.0.1:随机端口 —— 配合无认证的 /api/app/tokens
/// 就能读走全部会话令牌。
fn is_allowed_origin(origin: Option<&str>) -> bool {
    match origin {
        // 非浏览器发起的请求（curl、同源请求）没有 Origin 头
        None => true,
        Some(value) => {
            // 生产模式：页面由 Tauri 从内嵌资源加载
            if value.starts_with("tauri://")
                || value.starts_with("http://tauri.localhost")
                || value.starts_with("https://tauri.localhost")
            {
                return true;
            }

            /*
             * 开发模式：页面由 Vite dev server 提供，Origin 是
             * http://localhost:5173 或 http://127.0.0.1:5173。
             *
             * 不放行这一条的话，pnpm desktop:dev 时页面能打开，
             * 但所有本地 API 请求都会被拒 —— 表现为
             * 「连不上这个数据源」，而打包后的 exe 却正常。
             */
            is_dev_origin(value)
        }
    }
}

/// 是否是 Vite 开发服务器的来源。
///
/// 只在 debug 构建里接受：release 包里页面从 tauri:// 加载，
/// 不该出现 localhost:5173。多放行一条入口就多一分被利用的可能，
/// 所以用 cfg!(debug_assertions) 把它限制在开发构建中。
///
/// 同时严格限定回环地址 + 特定端口，避免被局域网内的网页利用。
fn is_dev_origin(origin: &str) -> bool {
    if !cfg!(debug_assertions) {
        return false;
    }

    let Some(rest) = origin
        .strip_prefix("http://")
        .or_else(|| origin.strip_prefix("https://"))
    else {
        return false;
    };

    // 期望形如 localhost:5173 / 127.0.0.1:5173 / [::1]:5173
    let Some((host, port)) = rest.rsplit_once(':') else {
        return false;
    };

    let is_loopback = host == "localhost" || host == "127.0.0.1" || host == "[::1]";
    is_loopback && port == "5173"
}

/// 构造响应头。origin 用于回显允许的来源。
fn base_headers(origin: Option<&str>) -> Vec<Header> {
    let allow_origin = if is_allowed_origin(origin) {
        origin.unwrap_or("*")
    } else {
        "null"
    };

    vec![
        header("Content-Type", "application/json; charset=utf-8"),
        header("Access-Control-Allow-Origin", allow_origin),
        header("Vary", "Origin"),
        header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS"),
        header(
            "Access-Control-Allow-Headers",
            "Content-Type, Authorization, X-Toolbox-Client",
        ),
        header("Access-Control-Max-Age", "600"),
        header("Cache-Control", "no-store"),
    ]
}

/// 从请求里取 Origin 头。
fn origin_of(request: &Request) -> Option<String> {
    request
        .headers()
        .iter()
        .find(|h| h.field.equiv("Origin"))
        .map(|h| h.value.as_str().to_string())
}

fn respond_json<T: Serialize>(request: Request, status: u16, body: &T) {
    let payload = serde_json::to_string(body).unwrap_or_else(|_| "{}".to_string());
    let mut response = Response::from_string(payload).with_status_code(StatusCode(status));
    let origin = origin_of(&request);
    for item in base_headers(origin.as_deref()) {
        response.add_header(item);
    }
    let _ = request.respond(response);
}

/// 返回二进制内容（备份下载用）。需要自定义 Content-Type 与文件名。
fn respond_bytes(request: Request, bytes: Vec<u8>, filename: &str) {
    let mut response = Response::from_data(bytes).with_status_code(StatusCode(200));
    let origin = origin_of(&request);
    for item in base_headers(origin.as_deref()) {
        response.add_header(item);
    }
    let _ = response.add_header(Header::from_bytes(
        &b"Content-Type"[..],
        &b"application/octet-stream"[..],
    ).unwrap());
    let disposition = format!("attachment; filename=\"{filename}\"");
    if let Ok(header) = Header::from_bytes(&b"Content-Disposition"[..], disposition.as_bytes()) {
        let _ = response.add_header(header);
    }
    let _ = request.respond(response);
}

fn respond_empty(request: Request, status: u16) {
    let mut response = Response::empty(StatusCode(status));
    let origin = origin_of(&request);
    for item in base_headers(origin.as_deref()) {
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

/// 当前 schema 版本号，与 packages/data/src/migrations.ts 的 SCHEMA_VERSION 保持一致。
pub const SCHEMA_VERSION: i64 = 2;

/// 迁移 SQL。idx 必须与服务端 migrations.ts 一一对应。
const MIGRATIONS: &[(i64, &str, &str)] = &[
    (0, "0000_init", include_str!("../migrations/0000_init.sql")),
    (1, "0001_servers", include_str!("../migrations/0001_servers.sql")),
];

/// 打开数据库并按版本执行迁移。
///
/// 与服务端 createNodeDatabase 同一套规则：
/// - 版本号存在 PRAGMA user_version
/// - 单个迁移一个事务，失败回滚
/// - 升级前自动备份，备份永久保留
/// - 库版本高于程序时拒绝启动
fn init_db(path: &PathBuf) -> Result<Connection, String> {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let conn = Connection::open(path).map_err(|e| format!("打开数据库失败：{e}"))?;
    conn.pragma_update(None, "journal_mode", "WAL")
        .map_err(|e| format!("设置 WAL 失败：{e}"))?;
    conn.pragma_update(None, "busy_timeout", 5000)
        .map_err(|e| format!("设置 busy_timeout 失败：{e}"))?;
    conn.pragma_update(None, "foreign_keys", "ON")
        .map_err(|e| format!("启用外键失败：{e}"))?;

    let applied: i64 = conn
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .map_err(|e| format!("读取数据库版本失败：{e}"))?;

    /*
     * 2.0.0 时期的库 user_version 是 0，但表已建好。
     * 项目不支持从 2.0.0 之前的版本升级，这里只处理
     * 「有表但没版本号」这一种情况。
     */
    let has_existing_schema = applied == 0
        && conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
            .and_then(|mut s| s.exists([]))
            .unwrap_or(false);

    let starting = if has_existing_schema {
        SCHEMA_VERSION.min(2)
    } else {
        applied
    };

    if has_existing_schema {
        conn.pragma_update(None, "user_version", starting)
            .map_err(|e| format!("写入数据库版本失败：{e}"))?;
    }

    // 降级保护：库比程序新
    if starting > SCHEMA_VERSION {
        return Err(format!(
            "数据库版本为 {starting}，高于当前程序支持的 {SCHEMA_VERSION}。             这通常是安装了旧版本导致的，请安装更新的版本；             或从 data 目录下的 .bak 备份文件恢复后重试。"
        ));
    }

    if starting == SCHEMA_VERSION {
        return Ok(conn);
    }

    /*
     * 升级前备份（永久保留，不自动删除）。
     *
     * 全新数据库跳过 —— 文件里还没有任何表，备份出来是 4KB 空壳。
     * 它会在列表里和真实备份混在一起，用户一旦误恢复，
     * 账号和数据全部消失，看起来就像「需要重新注册」。
     * 空备份没有任何价值，不生成。
     */
    let is_fresh_database = starting == 0 && !has_existing_schema;
    if !is_fresh_database {
        crate::backup::create_backup(path, starting)
            .map_err(|e| format!("升级前备份失败，已中止升级：{e}"))?;
    }

    for (idx, tag, sql) in MIGRATIONS.iter().filter(|(idx, _, _)| *idx >= starting) {
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| format!("开启事务失败：{e}"))?;
        tx.execute_batch(sql)
            .map_err(|e| format!("迁移 {tag} 失败：{e}"))?;
        tx.pragma_update(None, "user_version", idx + 1)
            .map_err(|e| format!("写入版本号失败：{e}"))?;
        tx.commit().map_err(|e| format!("提交迁移 {tag} 失败：{e}"))?;
    }

    Ok(conn)
}

/// 启动本地服务，返回实际端口。
pub fn start(db_path: PathBuf) -> Result<u16, String> {
    let conn = init_db(&db_path)?;
    let state = AppState {
        conn: Arc::new(Mutex::new(conn)),
        db_path: db_path.clone(),
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

/// 登录失败计数，用于本地暴力破解防护。
///
/// 本地服务虽只绑 127.0.0.1，但同机其他程序/脚本仍可访问；
/// 没有限流的话 Argon2 再慢也只是把在线爆破变成「慢速在线爆破」。
static LOGIN_FAILURES: std::sync::Mutex<Option<(std::time::Instant, u32)>> =
    std::sync::Mutex::new(None);

/// 1 分钟内失败超过 10 次则拒绝。
fn login_throttled() -> bool {
    match LOGIN_FAILURES.lock() {
        Ok(guard) => match *guard {
            Some((start, count)) => {
                start.elapsed() <= std::time::Duration::from_secs(60) && count >= 10
            }
            None => false,
        },
        Err(_) => false,
    }
}

fn record_login_failure() {
    if let Ok(mut guard) = LOGIN_FAILURES.lock() {
        match *guard {
            Some((start, count)) if start.elapsed() <= std::time::Duration::from_secs(60) => {
                *guard = Some((start, count + 1));
            }
            _ => {
                *guard = Some((std::time::Instant::now(), 1));
            }
        }
    }
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

            if login_throttled() {
                respond_json(
                    request,
                    429,
                    &error_body("TOO_MANY_ATTEMPTS", "尝试过于频繁，请 1 分钟后再试"),
                );
                return;
            }

            let Some((id, hash, display_name, created_at)) = found else {
                record_login_failure();
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "用户名或密码不正确"));
                return;
            };
            if !verify_password(&hash, &password) {
                record_login_failure();
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "用户名或密码不正确"));
                return;
            }

            if let Ok(conn) = state.conn.lock() {
                /*
                 * 老库里的密码可能是 sha256 格式。登录成功后立刻用
                 * Argon2id 重算写回 —— 用户无感知，但下次验证就走强算法了。
                 */
                if needs_rehash(&hash) {
                    let upgraded = hash_password(&password);
                    if !upgraded.is_empty() {
                        let _ = conn.execute(
                            "UPDATE users SET password_hash = ?1 WHERE id = ?2",
                            params![upgraded, id],
                        );
                    }
                }

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
        // 结构：{ "local": "<token>", "cloud:http://1.2.3.4:7788": "<token>" }
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
            let Some((user_id, _)) = current_session(state, &request) else {
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
                        body["password"].as_str().map(encrypt_credential),
                        body["privateKey"].as_str().map(encrypt_credential),
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
                        body["password"].as_str().map(encrypt_credential),
                        body.get("privateKey").is_some(),
                        body["privateKey"].as_str().map(encrypt_credential),
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

        // ---------- 数据库备份 ----------
        (Method::Get, "/api/backup") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let files = crate::backup::list_backups(&state.db_path);
            let total: u64 = files.iter().map(|f| f.size).sum();
            let db_size = std::fs::metadata(&state.db_path).map(|m| m.len()).unwrap_or(0);
            respond_json(
                request,
                200,
                &serde_json::json!({
                    "files": files,
                    "totalSize": total,
                    "databaseSize": db_size,
                    "schemaVersion": SCHEMA_VERSION,
                }),
            );
        }

        (Method::Post, "/api/backup") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            match crate::backup::create_backup(&state.db_path, SCHEMA_VERSION) {
                Ok(file) => {
                    respond_json(request, 201, &serde_json::json!({ "file": file }))
                }
                Err(error) => {
                    respond_json(request, 500, &error_body("BACKUP_FAILED", &error))
                }
            }
        }

        (Method::Get, path) if path.starts_with("/api/backup/") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let name = path.trim_start_matches("/api/backup/").to_string();

            /*
             * 下载备份文件。
             *
             * WebView 里 window.open("/api/backup/xxx") 会解析成
             * tauri:// 下的相对路径，根本到不了这里 —— 所以前端在
             * 桌面端不能走浏览器下载，必须由 Rust 直接返回字节流。
             */
            match crate::backup::read_backup(&state.db_path, &name) {
                Ok(bytes) => respond_bytes(request, bytes, &name),
                Err(error) => {
                    respond_json(request, 404, &error_body("NOT_FOUND", &error))
                }
            }
        }

        (Method::Delete, path) if path.starts_with("/api/backup/") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let name = path.trim_start_matches("/api/backup/").to_string();
            match crate::backup::delete_backup(&state.db_path, &name) {
                Ok(()) => respond_json(request, 200, &serde_json::json!({ "ok": true })),
                Err(error) => {
                    respond_json(request, 404, &error_body("NOT_FOUND", &error))
                }
            }
        }

        (Method::Post, path) if path.starts_with("/api/backup/") && path.ends_with("/restore") => {
            if current_user(state, &request).is_none() {
                respond_json(request, 401, &error_body("UNAUTHENTICATED", "请先登录"));
                return;
            }
            let name = path
                .trim_start_matches("/api/backup/")
                .trim_end_matches("/restore")
                .trim_end_matches('/')
                .to_string();

            /*
             * 恢复会整体替换数据库文件。
             *
             * 必须先把连接释放掉 —— Windows 上文件被占用时无法覆盖。
             * 用一个临时连接占位，避免其他请求访问已关闭的连接。
             */
            let placeholder = match Connection::open(&state.db_path) {
                Ok(conn) => conn,
                Err(error) => {
                    respond_json(
                        request,
                        500,
                        &error_body("INTERNAL_ERROR", &format!("打开数据库失败：{error}")),
                    );
                    return;
                }
            };
            {
                let mut guard = match state.conn.lock() {
                    Ok(guard) => guard,
                    Err(_) => {
                        respond_json(
                            request,
                            500,
                            &error_body("INTERNAL_ERROR", "本地数据库不可用"),
                        );
                        return;
                    }
                };
                *guard = placeholder;
            }

            let safety = {
                let _guard = state.conn.lock().ok();
                crate::backup::restore_backup(&state.db_path, &name, SCHEMA_VERSION)
            };

            // 恢复完成后重新打开数据库
            match init_db(&state.db_path) {
                Ok(conn) => {
                    if let Ok(mut guard) = state.conn.lock() {
                        *guard = conn;
                    }
                }
                Err(error) => {
                    respond_json(
                        request,
                        500,
                        &error_body("RESTORE_FAILED", &format!("恢复后重新打开失败：{error}")),
                    );
                    return;
                }
            }

            match safety {
                Ok(safety_copy) => respond_json(
                    request,
                    200,
                    &serde_json::json!({
                        "ok": true,
                        "safetyCopy": safety_copy,
                        "requiresRelogin": true,
                    }),
                ),
                Err(error) => {
                    respond_json(request, 400, &error_body("RESTORE_FAILED", &error))
                }
            }
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
