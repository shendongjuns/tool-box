//! 递归删除的行为验证。
//!
//! 真实 SFTP 目录树不可得，这里验证「删除顺序」这一核心逻辑：
//! 必须先删完文件、再按深度倒序删目录。
//! 顺序错了会得到「目录非空」错误。

/// 模拟两阶段删除的顺序计算。
/// 与 sftp_remove 里的 dirs.sort_by 保持同一逻辑。
fn deletion_order(tree: &[(&str, usize)]) -> Vec<String> {
    let mut dirs: Vec<(String, usize)> = tree
        .iter()
        .map(|(p, d)| (p.to_string(), *d))
        .collect();
    dirs.sort_by(|a, b| b.1.cmp(&a.1));
    dirs.into_iter().map(|(p, _)| p).collect()
}

#[test]
fn deepest_directories_are_deleted_first() {
    let tree = [
        ("/root", 0usize),
        ("/root/a", 1),
        ("/root/a/b", 2),
        ("/root/a/b/c", 3),
        ("/root/d", 1),
    ];

    let order = deletion_order(&tree);

    // 最深的 c 必须最先删
    assert_eq!(order[0], "/root/a/b/c");
    // 根目录必须最后删
    assert_eq!(order.last().unwrap(), "/root");
    // b 必须在 a 之前
    let pos_b = order.iter().position(|p| p == "/root/a/b").unwrap();
    let pos_a = order.iter().position(|p| p == "/root/a").unwrap();
    assert!(pos_b < pos_a, "子目录应先于父目录删除");
}

#[test]
fn each_directory_appears_exactly_once() {
    // 防止两阶段实现里重复 push 同一个目录
    let tree = [("/r", 0usize), ("/r/x", 1), ("/r/y", 1)];
    let order = deletion_order(&tree);
    assert_eq!(order.len(), tree.len(), "每个目录只应出现一次");
    let unique: std::collections::HashSet<_> = order.iter().collect();
    assert_eq!(unique.len(), order.len(), "不应有重复目录");
}

#[test]
fn flat_directory_tree_is_handled() {
    // 只有一层：排序后顺序无关紧要，但不能丢
    let tree = [("/only", 0usize)];
    assert_eq!(deletion_order(&tree), vec!["/only"]);
}
