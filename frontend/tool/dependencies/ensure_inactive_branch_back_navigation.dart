import 'dart:convert';
import 'dart:io';

/// Apply after pub get, before running or building the app. This changes the
/// resolved dependency in place; it does not vendor a second router.
/// Remove once go_router makes its shell PopScope ignore inactive branches.
void main() {
  final config = File.fromUri(
    Platform.script.resolve('../../.dart_tool/package_config.json'),
  );
  final packages =
      (jsonDecode(config.readAsStringSync())
              as Map<String, dynamic>)['packages']
          as List<dynamic>;
  final router = packages.cast<Map<String, dynamic>>().singleWhere(
    (package) => package['name'] == 'go_router',
  );
  final source = File.fromUri(
    Directory.fromUri(
      config.uri.resolve(router['rootUri'] as String),
    ).uri.resolve('lib/src/builder.dart'),
  );
  final text = source.readAsStringSync();
  const original = 'canPop: match.matches.length == 1,';
  const fixed =
      'canPop: !TickerMode.valuesOf(context).enabled || match.matches.length == 1,';
  const start = 'return PopScope(\n              // Prevent ShellRoute';
  const wrapped =
      'return Builder(builder: (context) => PopScope(\n              // Prevent ShellRoute';
  const end = '''                requestFocus: widget.requestFocus,
              ),
            );''';
  const closed = '''                requestFocus: widget.requestFocus,
              ),
            ));''';
  if (text.contains(fixed) && text.contains(wrapped) && text.contains(closed)) {
    stdout.writeln('go_router: inactive shell back guard already patched.');
    return;
  }
  if ([original, start, end].any((part) => part.allMatches(text).length != 1)) {
    throw StateError(
      'go_router shell guard changed. Review the upstream implementation and '
      'update or remove tool/dependencies/ensure_inactive_branch_back_navigation.dart before building.',
    );
  }
  source.writeAsStringSync(
    text
        .replaceFirst(original, fixed)
        .replaceFirst(start, wrapped)
        .replaceFirst(end, closed),
  );
  stdout.writeln('go_router: inactive shell back guard patched in place.');
}
