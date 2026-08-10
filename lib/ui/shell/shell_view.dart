import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'navigation_controller.dart';
import 'top_nav_bar.dart';

/// AppFlowy 风格布局：顶部横向导航栏 + 内容区。
class ShellView extends ConsumerWidget {
  const ShellView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedToolProvider);

    // MaterialApp 的 home 无 Scaffold/Material 祖先（main.dart 直接挂
    // ShellView），壳层自带透明 Material，保证导航 ink 平台可用。
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          const TopNavBar(),
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: selected?.buildContent(context) ?? const HomePage(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页占位：内容待定（暂空）。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '内容待定',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
