import '../../../../core/layout/app_page_body.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/widgets/app_choice_segments.dart';
import '../widgets/setting_components.dart';
import '../licenses_page.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../../../../theme/design_tokens.dart';

class SystemTab extends ConsumerWidget {
  const SystemTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      children: [
        const SectionHeader(title: '主题'),
        AppChoiceSegments<ThemeMode>(
          options: const {
            ThemeMode.system: '跟随系统',
            ThemeMode.light: '浅色',
            ThemeMode.dark: '深色',
          },
          selected: {ref.watch(themeModeProvider)},
          onChanged: (values) =>
              ref.read(themeModeProvider.notifier).set(values.first),
        ),
        const SizedBox(height: 32),
        const _AppAboutSection(),
      ],
    );
    return AppPageBody(child: content);
  }
}

class _AppAboutSection extends StatefulWidget {
  const _AppAboutSection();
  @override
  State<_AppAboutSection> createState() => _AppAboutSectionState();
}

class _AppAboutSectionState extends State<_AppAboutSection> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _packageInfo,
    builder: (context, snapshot) {
      final info = snapshot.data;
      final version = info == null
          ? null
          : '${info.version} (${info.buildNumber})';
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VaultStream', style: theme.textTheme.titleMedium),
                if (version != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '版本 $version',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            shape: const RoundedRectangleBorder(
              borderRadius: AppShape.cardMediaBorder,
            ),
            title: const Text('开源许可'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context, rootNavigator: true).push<void>(
              MaterialPageRoute(
                builder: (context) =>
                    AppLicensesPage(applicationVersion: version),
              ),
            ),
          ),
        ],
      );
    },
  );
}
