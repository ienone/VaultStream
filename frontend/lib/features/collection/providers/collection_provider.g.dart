// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Collection)
final collectionProvider = CollectionProvider._();

final class CollectionProvider
    extends $AsyncNotifierProvider<Collection, ShareCardListResponse> {
  CollectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'collectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$collectionHash();

  @$internal
  @override
  Collection create() => Collection();
}

String _$collectionHash() => r'f1ca654b2b3f86609d7f6246ad9fd34d9c9bbe72';

abstract class _$Collection extends $AsyncNotifier<ShareCardListResponse> {
  FutureOr<ShareCardListResponse> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ShareCardListResponse>, ShareCardListResponse>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ShareCardListResponse>,
                ShareCardListResponse
              >,
              AsyncValue<ShareCardListResponse>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(contentDetail)
final contentDetailProvider = ContentDetailFamily._();

final class ContentDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<ContentDetail>,
          ContentDetail,
          FutureOr<ContentDetail>
        >
    with $FutureModifier<ContentDetail>, $FutureProvider<ContentDetail> {
  ContentDetailProvider._({
    required ContentDetailFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'contentDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$contentDetailHash();

  @override
  String toString() {
    return r'contentDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ContentDetail> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ContentDetail> create(Ref ref) {
    final argument = this.argument as int;
    return contentDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ContentDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$contentDetailHash() => r'a0a17ef65be94c6f9d58cf34e28300441959888e';

final class ContentDetailFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ContentDetail>, int> {
  ContentDetailFamily._()
    : super(
        retry: null,
        name: r'contentDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ContentDetailProvider call(int id) =>
      ContentDetailProvider._(argument: id, from: this);

  @override
  String toString() => r'contentDetailProvider';
}
