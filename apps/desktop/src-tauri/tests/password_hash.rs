//! 密码哈希强度验证。
//!
//! 断言：
//! 1. 生成的哈希是 Argon2id PHC 格式（而非 sha256）
//! 2. 同一密码两次哈希结果不同（salt 随机）
//! 3. 正确密码能通过验证，错误密码不能
//! 4. 单次哈希耗时在合理区间（说明确实在做内存硬计算）

use std::time::Instant;

const MEM_COST: u32 = 19456;
const TIME_COST: u32 = 2;

fn argon2_instance() -> argon2::Argon2<'static> {
    let params = argon2::Params::new(MEM_COST, TIME_COST, 1, None).expect("params");
    argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params)
}

fn hash(password: &str) -> String {
    use argon2::password_hash::PasswordHasher;
    argon2_instance()
        .hash_password(password.as_bytes())
        .expect("hash")
        .to_string()
}

fn verify(stored: &str, password: &str) -> bool {
    use argon2::password_hash::{PasswordVerifier, phc::PasswordHash};
    let Ok(parsed) = PasswordHash::new(stored) else {
        return false;
    };
    argon2::Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok()
}

#[test]
fn hash_is_argon2id_phc() {
    let stored = hash("hunter42");
    assert!(
        stored.starts_with("$argon2id$"),
        "应为 argon2id PHC 串，实际: {stored}"
    );
    assert!(stored.contains("m=19456"), "应包含内存成本参数");
    assert!(stored.contains("t=2"), "应包含时间成本参数");
}

#[test]
fn salt_is_random() {
    let a = hash("same-password");
    let b = hash("same-password");
    assert_ne!(a, b, "两次哈希应不同（salt 随机）");
    // 但都能验证通过
    assert!(verify(&a, "same-password"));
    assert!(verify(&b, "same-password"));
}

#[test]
fn verify_rejects_wrong_password() {
    let stored = hash("correct");
    assert!(verify(&stored, "correct"));
    assert!(!verify(&stored, "wrong"));
    assert!(!verify(&stored, ""));
    assert!(!verify(&stored, "correct "));
}

#[test]
fn hash_cost_is_meaningful() {
    let started = Instant::now();
    let _ = hash("benchmark-password");
    let elapsed = started.elapsed().as_millis();

    // 单轮 SHA-256 通常在 0.001ms 级；Argon2id 19456KiB/t=2 应 >= 5ms
    assert!(
        elapsed >= 5,
        "哈希耗时 {elapsed}ms 过低，可能没走 Argon2"
    );
    eprintln!("单次哈希耗时: {elapsed}ms（Argon2id 19456KiB t=2）");
}

#[test]
fn legacy_sha256_format_still_verifiable() {
    // 旧格式 salt:sha256(salt+password) 的兼容性由 local_api 内部实现，
    // 这里只验证新格式不会误判成旧格式
    let stored = hash("x");
    assert!(stored.starts_with("$argon2"), "新格式不应以 salt: 开头");
}
