// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SystemSettings)
final systemSettingsProvider = SystemSettingsProvider._();

final class SystemSettingsProvider
    extends $AsyncNotifierProvider<SystemSettings, List<SystemSetting>> {
  SystemSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'systemSettingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$systemSettingsHash();

  @$internal
  @override
  SystemSettings create() => SystemSettings();
}

String _$systemSettingsHash() => r'9467a1e7d0f51037c7c41424bfc40898d96eb2b5';

abstract class _$SystemSettings extends $AsyncNotifier<List<SystemSetting>> {
  FutureOr<List<SystemSetting>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<SystemSetting>>, List<SystemSetting>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<SystemSetting>>, List<SystemSetting>>,
              AsyncValue<List<SystemSetting>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
