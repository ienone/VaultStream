import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';

class AppLicensesPage extends StatefulWidget {
  const AppLicensesPage({super.key, this.applicationVersion});

  final String? applicationVersion;

  @override
  State<AppLicensesPage> createState() => _AppLicensesPageState();
}

class _AppLicensesPageState extends State<AppLicensesPage> {
  late Future<Map<String, List<LicenseEntry>>> _licenses = _readLicenses();

  Future<Map<String, List<LicenseEntry>>> _readLicenses() async {
    final packages = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        (packages[package] ??= []).add(entry);
      }
    }
    return packages;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('开源许可')),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
          child: FutureBuilder<Map<String, List<LicenseEntry>>>(
            future: _licenses,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('暂时无法读取许可信息'),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _licenses = _readLicenses()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重新加载'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final packages = snapshot.data!;
              final names = packages.keys.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                itemCount: names.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                      child: Text(
                        names.isEmpty
                            ? '没有可显示的许可信息'
                            : [
                                'VaultStream',
                                if (widget.applicationVersion != null)
                                  widget.applicationVersion!,
                              ].join(' · '),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  final name = names[index - 1];
                  final entries = packages[name]!;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppShape.cardMediaBorder,
                    ),
                    title: Text(name),
                    subtitle: entries.length > 1
                        ? Text(
                            MaterialLocalizations.of(
                              context,
                            ).licensesPackageDetailText(entries.length),
                          )
                        : null,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) => _LicenseReadingPage(
                          packageName: name,
                          entries: entries,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _LicenseReadingPage extends StatefulWidget {
  const _LicenseReadingPage({required this.packageName, required this.entries});

  final String packageName;
  final List<LicenseEntry> entries;

  @override
  State<_LicenseReadingPage> createState() => _LicenseReadingPageState();
}

class _LicenseReadingPageState extends State<_LicenseReadingPage> {
  late final List<List<LicenseParagraph>> _sections = [
    for (final entry in widget.entries) entry.paragraphs.toList(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('许可正文')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppPane.readableMaxWidth,
            ),
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                children: [
                  Text(widget.packageName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 24),
                  for (var index = 0; index < _sections.length; index++) ...[
                    if (index > 0) const SizedBox(height: 24),
                    if (_sections.length > 1) ...[
                      Text(
                        '许可 ${index + 1}',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final paragraph in _sections[index])
                      LayoutBuilder(
                        builder: (context, constraints) => Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: paragraph.indent > 0
                                ? (paragraph.indent * 16.0).clamp(
                                    0,
                                    constraints.maxWidth / 3,
                                  )
                                : 0,
                            bottom: 12,
                          ),
                          child: Text(
                            paragraph.text,
                            textAlign:
                                paragraph.indent ==
                                    LicenseParagraph.centeredIndent
                                ? TextAlign.center
                                : TextAlign.start,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
