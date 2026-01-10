// ignore_for_file: deprecated_member_use
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/theme_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(
          context,
        ).colorScheme.surface.withValues(alpha: 0.8),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '外观',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          RadioListTile<ThemeMode>(
            title: const Text('跟随系统'),
            value: ThemeMode.system,
            groupValue: themeMode,
            onChanged: (val) {
              if (val != null) {
                ref.read(themeModeProvider.notifier).set(val);
              }
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('浅色模式'),
            value: ThemeMode.light,
            groupValue: themeMode,
            onChanged: (val) {
              if (val != null) {
                ref.read(themeModeProvider.notifier).set(val);
              }
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('深色模式'),
            value: ThemeMode.dark,
            groupValue: themeMode,
            onChanged: (val) {
              if (val != null) {
                ref.read(themeModeProvider.notifier).set(val);
              }
            },
          ),
          const Divider(),
          Center(
             child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Text(
                 'VaultStream v0.1.0',
                 style: Theme.of(context).textTheme.bodySmall?.copyWith(
                   color: Theme.of(context).colorScheme.outline,
                 ),
               ),
             ),
          ),
        ],
      ),
    );
  }
}
