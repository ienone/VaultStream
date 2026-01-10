// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_filter_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CollectionFilter)
final collectionFilterProvider = CollectionFilterProvider._();

final class CollectionFilterProvider
    extends $NotifierProvider<CollectionFilter, CollectionFilterState> {
  CollectionFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'collectionFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$collectionFilterHash();

  @$internal
  @override
  CollectionFilter create() => CollectionFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CollectionFilterState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CollectionFilterState>(value),
    );
  }
}

String _$collectionFilterHash() => r'5d23b7b971989f159ab0cf9d128305ee3da3dbcb';

abstract class _$CollectionFilter extends $Notifier<CollectionFilterState> {
  CollectionFilterState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CollectionFilterState, CollectionFilterState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CollectionFilterState, CollectionFilterState>,
              CollectionFilterState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
