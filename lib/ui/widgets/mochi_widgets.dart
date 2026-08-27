import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:toolbox/ui/theme/app_icons.dart';
import 'package:toolbox/ui/theme/mochi_cat_tokens.dart';

/// 在弹窗关闭后安全释放 TextEditingController。
///
/// `Navigator.pop` 触发 `showDialog` 的 future 立即 resolve，但弹窗的
/// 退出动画仍在进行，TextField 仍挂在树上；此时 dispose controller 会在
/// 动画帧的 didUpdateWidget 中触发 "used after being disposed" 崩溃。
/// 等待退出动画结束后再释放。
Future<void> disposeAfterDialog(List<TextEditingController> controllers) async {
  // DialogRoute 默认退出动画 150ms，加安全余量。
  await Future<void>.delayed(const Duration(milliseconds: 400));
  for (final controller in controllers) {
    controller.dispose();
  }
}

/// 品牌猫标：紫色圆角方块 + 两只猫耳 + 猫脸，用于顶栏品牌区与页面标题。
class CatMark extends StatelessWidget {
  const CatMark({super.key, this.size = 29, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final primary = MochiCatPalette.of(context).primary;
    final corner = radius ?? size * 0.34;
    final ear = size * 0.28;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 左猫耳
          Positioned(
            left: size * 0.13,
            top: -ear * 0.32,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: ear,
                height: ear,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // 右猫耳
          Positioned(
            right: size * 0.13,
            top: -ear * 0.32,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: ear,
                height: ear,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // 主体
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(corner),
              ),
              alignment: Alignment.center,
              child: Text(
                '•ᴗ•',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.42,
                  height: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按钮视觉类型（对应设计规范按钮层级）。
enum MochiButtonType {
  /// 主操作：紫色底白字。
  primary,

  /// 普通操作：白底描边。
  secondary,

  /// 成功/连接/远程拉取：薄荷底。
  success,

  /// 危险操作：柔红底。
  danger,

  /// 弱操作：透明底灰字。
  ghost,
}

/// 类型化按钮：统一 36px 高、9px 圆角、图标+文字。
class MochiButton extends StatelessWidget {
  const MochiButton({
    super.key,
    required this.label,
    this.icon,
    this.type = MochiButtonType.secondary,
    this.onPressed,
    this.loading = false,
    this.expanded = false,
  });

  final String label;
  final IconData? icon;
  final MochiButtonType type;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    final (bg, fg, border) = switch (type) {
      // 主操作：深灰底白字（协调不刺眼，替代原紫色）。
      MochiButtonType.primary => (p.textPrimary, Colors.white, p.textPrimary),
      MochiButtonType.secondary => (p.surface, p.textPrimary, p.border),
      MochiButtonType.success => (p.mintSoft, p.mint, p.mint.withValues(alpha: .45)),
      MochiButtonType.danger => (p.dangerSoft, p.danger, p.danger.withValues(alpha: .4)),
      // 弱操作（弹窗取消/关闭）：白底描边 + 次要文字色，与 secondary 同体系。
      MochiButtonType.ghost => (p.surface, p.textSecondary, p.border),
    };
    final disabled = onPressed == null;
    final effectiveBg = disabled ? const Color(0xFFF3F1F6) : bg;
    final effectiveFg = disabled ? const Color(0xFFB9B4C2) : fg;

    final button = Material(
      color: effectiveBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MochiCatRadius.sm),
        side: BorderSide(color: disabled ? const Color(0xFFEEEAF2) : border),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(MochiCatRadius.sm),
        child: Container(
          height: MochiCatSize.buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.lg),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: effectiveFg,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 16, color: effectiveFg),
              if (loading || icon != null) const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: effectiveFg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// 状态圆点 + 文本（不依赖颜色单独表意）。
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.label,
    this.color,
    this.size = 7,
  });

  final String label;

  /// 为空时使用次文本色。
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? MochiCatPalette.of(context).textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

/// 简洁优雅的下拉选择框：浅色底、细边框、圆角 9px、右侧下拉箭头。
///
/// 替代原生 [DropdownButton] 在弹窗/表单中的样式，视觉与输入框统一。
class MochiSelectField<T> extends StatelessWidget {
  const MochiSelectField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.icon,
  });

  final T? value;

  /// 选项：`(值, 显示文本)` 列表。
  final List<(T, String)> items;

  final ValueChanged<T?> onChanged;

  /// 上方小标签（可选）。
  final String? label;

  /// 左侧图标（可选）。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    // 与输入框一致的字体与字号（微软雅黑），选中项与下拉项统一。
    const itemStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      fontFamily: 'Microsoft YaHei UI',
    );
    final field = Container(
      height: MochiCatSize.inputHeight,
      padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.md),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(MochiCatRadius.sm),
        border: Border.all(color: p.border),
      ),
      alignment: Alignment.centerLeft,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: Icon(
            AppIcons.chevronDown,
            size: 18,
            color: p.textSecondary,
          ),
          style: itemStyle.copyWith(color: p.textPrimary),
          dropdownColor: p.surface,
          borderRadius: BorderRadius.circular(MochiCatRadius.md),
          menuMaxHeight: 300,
          items: [
            for (final (v, label) in items)
              DropdownMenuItem(
                value: v,
                child: Text(
                  label,
                  style: itemStyle.copyWith(color: p.textPrimary),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
    if (label == null && icon == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: 11,
              color: p.textSecondary,
              fontFamily: 'Microsoft YaHei UI',
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (icon != null)
          Row(
            children: [
              Icon(icon, size: 15, color: p.textSecondary),
              const SizedBox(width: MochiCatSpacing.sm),
              Expanded(child: field),
            ],
          )
        else
          field,
      ],
    );
  }
}

/// 常规面板容器：白底（或主题 surface）+ 描边 + 15px 圆角。
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MochiCatSpacing.lg),
    this.radius = MochiCatRadius.xl,
    this.color,
    this.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? p.border),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

/// 标准弹窗：常规宽度 460、18px 圆角、可选 34px 猫咪标题图形。
///
/// [title] 为弹窗主标题；[emoji] 会渲染在标题左侧奶杏圆角方块中。
/// 按钮通过 [actions] 传入，右对齐由 AlertDialog 处理。
Future<T?> showMochiDialog<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  String? emoji,
  required Widget content,
  required List<Widget> actions,
  double width = MochiCatSize.dialogWidth,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(
        MochiCatSpacing.xl,
        MochiCatSpacing.xl,
        MochiCatSpacing.lg,
        0,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        MochiCatSpacing.xl,
        MochiCatSpacing.lg,
        MochiCatSpacing.xl,
        0,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        MochiCatSpacing.xl,
        MochiCatSpacing.xs,
        MochiCatSpacing.xl,
        MochiCatSpacing.lg,
      ),
      title: Row(
        children: [
          if (emoji != null) ...[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MochiCatPalette.of(context).creamSoft,
                borderRadius: BorderRadius.circular(MochiCatRadius.md),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 17)),
            ),
            const SizedBox(width: MochiCatSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: MochiCatPalette.of(context).textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 右上角关闭叉号：点击关闭弹窗（返回 null，等同取消）。
          IconButton(
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            icon: Icon(AppIcons.close, size: 18, color: MochiCatPalette.of(context).textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(width: width, child: content),
      // 按钮右对齐、强制同一行（按钮数量少，不会溢出）。
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: MochiCatSpacing.sm),
              actions[i],
            ],
          ],
        ),
      ],
    ),
  );
}

/// 通用删除确认弹窗：猫咪警示图形 + 明确操作对象 + 不可撤销说明。
Future<bool> showDeleteConfirm(
  BuildContext context, {
  required String title,
  required String description,
}) async {
  final p = MochiCatPalette.of(context);
  final ok = await showMochiDialog<bool>(
    context: context,
    title: title,
    emoji: '🙀',
    width: 400,
    content: Padding(
      padding: const EdgeInsets.only(top: MochiCatSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: MochiCatSpacing.xs),
          Text(
            '此操作无法撤销。',
            style: TextStyle(
              fontSize: 12,
              color: p.danger,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
    actions: [
      MochiButton(
        label: '取消',
        type: MochiButtonType.ghost,
        onPressed: () => Navigator.pop(context, false),
      ),
      MochiButton(
        label: '删除',
        icon: AppIcons.delete,
        type: MochiButtonType.danger,
        onPressed: () => Navigator.pop(context, true),
      ),
    ],
  );
  return ok == true;
}
