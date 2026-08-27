import 'package:flutter/material.dart';

/// 全局图标映射：所有页面/组件统一从这里取图标，
/// 避免散落的 `Icons.xxx` 与重复的 switch 映射。
abstract final class AppIcons {
  // —— 导航 ——
  static const home = Icons.home_rounded;
  static const work = Icons.work_outline_rounded;
  static const data = Icons.data_object_rounded;
  static const database = Icons.storage_rounded;
  static const text = Icons.text_fields_rounded;
  static const encode = Icons.code_rounded;
  static const system = Icons.tune_rounded;
  static const other = Icons.widgets_outlined;
  static const chevronDown = Icons.keyboard_arrow_down_rounded;

  // —— 工具 ——
  static const repository = Icons.account_tree_rounded;
  static const remote = Icons.dns_rounded;
  static const fallback = Icons.extension_rounded;

  // —— 通用操作 ——
  static const add = Icons.add_rounded;
  static const close = Icons.close_rounded;
  static const search = Icons.search_rounded;
  static const edit = Icons.edit_outlined;
  static const delete = Icons.delete_outline_rounded;
  static const copy = Icons.copy_outlined;
  static const save = Icons.save_outlined;
  static const refresh = Icons.refresh_rounded;
  static const more = Icons.more_horiz_rounded;
  static const chevronRight = Icons.chevron_right_rounded;
  static const settings = Icons.settings_outlined;

  // —— 仓库 ——
  static const download = Icons.download_rounded;
  static const cloudDownload = Icons.cloud_download_outlined;
  static const playlistAdd = Icons.playlist_add_rounded;
  static const importExport = Icons.import_export_rounded;
  static const folder = Icons.folder_rounded;
  static const folderOpen = Icons.folder_open_rounded;
  static const computer = Icons.computer_rounded;
  static const link = Icons.link_rounded;
  static const check = Icons.check_rounded;
  static const lock = Icons.lock_outline_rounded;

  // —— 远程/终端/文件 ——
  static const terminal = Icons.terminal_rounded;
  static const sftpUpload = Icons.upload_rounded;
  static const sftpDownload = Icons.download_rounded;
  static const newFolder = Icons.create_new_folder_outlined;
  static const transferHistory = Icons.history_rounded;
  static const goUp = Icons.arrow_upward_rounded;
  static const goForward = Icons.arrow_forward_rounded;
  static const sort = Icons.sort_rounded;
  static const sortAsc = Icons.arrow_upward_rounded;
  static const sortDesc = Icons.arrow_downward_rounded;
  static const openInNew = Icons.open_in_new_rounded;
  static const fileText = Icons.insert_drive_file_outlined;
  static const transferBox = Icons.inventory_2_outlined;
  static const noSearchResult = Icons.search_off_rounded;
  static const paste = Icons.content_paste_rounded;
  static const hide = Icons.visibility_off_rounded;
  static const info = Icons.info_outline_rounded;
  static const shield = Icons.shield_outlined;
  static const server = Icons.dns_outlined;

  // —— 监控 ——
  static const monitor = Icons.monitor_heart_outlined;
  static const arrowUp = Icons.keyboard_arrow_up_rounded;
  static const arrowDown = Icons.keyboard_arrow_down_rounded;

  // —— 品牌/情感 ——
  static const pets = Icons.pets_rounded;
  static const sparkles = Icons.auto_awesome_rounded;
  static const menuOpen = Icons.menu_open_rounded;

  /// 主题切换图标（跟随系统 → 浅色 → 深色）。
  static IconData themeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };
}
