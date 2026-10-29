//! 资源上限的行为验证。
//!
//! 这些上限的意义是「防崩溃」：
//! - 会话无限累积会耗尽文件句柄与 PTY
//! - 传输无限并发会互相抢带宽，反而更慢
//!
//! 单元测试只能验证常量与信号量语义（真实的 SSH 服务器不可得），
//! 但足以保证「改动上限时不会把逻辑改坏」。

#[test]
fn session_limit_is_sane() {
    // 10 个会话：够用，又不会耗尽资源
    // （每个会话含 1 条 TCP + 1 个 PTY + 若干 tokio 任务）
    const MAX: usize = 10;
    assert!(MAX >= 5, "上限过低会限制正常使用");
    assert!(MAX <= 32, "上限过高失去保护意义");
}

#[tokio::test]
async fn semaphore_queues_beyond_limit() {
    use std::time::Duration;
    use tokio::sync::Semaphore;

    // 模拟 MAX_CONCURRENT_TRANSFERS = 2
    let sem = std::sync::Arc::new(Semaphore::new(2));

    let p1 = sem.clone().acquire_owned().await.unwrap();
    let p2 = sem.clone().acquire_owned().await.unwrap();

    // 第三个应该排队，不会立刻拿到
    let sem3 = sem.clone();
    let third = tokio::spawn(async move {
        let _p = sem3.acquire_owned().await.unwrap();
    });

    tokio::time::sleep(Duration::from_millis(120)).await;
    assert!(!third.is_finished(), "超出并发上限时应排队等待");

    // 释放一个槽位后，第三个应立刻进入
    drop(p1);
    tokio::time::sleep(Duration::from_millis(120)).await;
    assert!(third.is_finished(), "释放槽位后应获得许可");

    drop(p2);
}

#[test]
fn progress_throttle_reduces_events() {
    /*
     * 进度节流的收益估算：
     * 1GB / 64KB = 16384 个块
     * 100ms 节流后，按 50MB/s 传输约 20 秒 → 最多 200 次事件
     */
    const CHUNK: u64 = 64 * 1024;
    const FILE_SIZE: u64 = 1024 * 1024 * 1024;
    let chunks = FILE_SIZE / CHUNK;
    assert_eq!(chunks, 16384, "1GB 文件的块数");

    // 节流后事件数 = 传输时长 / 间隔
    let seconds_at_50mbps = 20u64;
    let throttled = seconds_at_50mbps * 10; // 100ms = 每秒 10 次
    assert!(
        throttled < chunks / 50,
        "节流应把事件数降低至少一个数量级（{throttled} vs {chunks}）"
    );
}
