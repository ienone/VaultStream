// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dashboardStats)
final dashboardStatsProvider = DashboardStatsProvider._();

final class DashboardStatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<DashboardStats>,
          DashboardStats,
          FutureOr<DashboardStats>
        >
    with $FutureModifier<DashboardStats>, $FutureProvider<DashboardStats> {
  DashboardStatsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dashboardStatsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dashboardStatsHash();

  @$internal
  @override
  $FutureProviderElement<DashboardStats> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DashboardStats> create(Ref ref) {
    return dashboardStats(ref);
  }
}

String _$dashboardStatsHash() => r'2c860d4cee6e04edcedb3c97711f0587f89825a3';

@ProviderFor(queueStats)
final queueStatsProvider = QueueStatsProvider._();

final class QueueStatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<QueueStats>,
          QueueStats,
          FutureOr<QueueStats>
        >
    with $FutureModifier<QueueStats>, $FutureProvider<QueueStats> {
  QueueStatsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'queueStatsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$queueStatsHash();

  @$internal
  @override
  $FutureProviderElement<QueueStats> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<QueueStats> create(Ref ref) {
    return queueStats(ref);
  }
}

String _$queueStatsHash() => r'0f47d42e4dfa35a9fd4843717107d7e21534e760';
