// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Collection)
final collectionProvider = CollectionFamily._();

final class CollectionProvider
    extends $AsyncNotifierProvider<Collection, ShareCardListResponse> {
  CollectionProvider._({
    required CollectionFamily super.from,
    required ({
      int page,
      int size,
      String? tag,
      String? platform,
      String? status,
      String? author,
      DateTime? startDate,
      DateTime? endDate,
      String? query,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'collectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$collectionHash();

  @override
  String toString() {
    return r'collectionProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  Collection create() => Collection();

  @override
  bool operator ==(Object other) {
    return other is CollectionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$collectionHash() => r'494762ccf655a0b22832a26774c12ad12c1e6f70';

final class CollectionFamily extends $Family
    with
        $ClassFamilyOverride<
          Collection,
          AsyncValue<ShareCardListResponse>,
          ShareCardListResponse,
          FutureOr<ShareCardListResponse>,
          ({
            int page,
            int size,
            String? tag,
            String? platform,
            String? status,
            String? author,
            DateTime? startDate,
            DateTime? endDate,
            String? query,
          })
        > {
  CollectionFamily._()
    : super(
        retry: null,
        name: r'collectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CollectionProvider call({
    int page = 1,
    int size = 20,
    String? tag,
    String? platform,
    String? status,
    String? author,
    DateTime? startDate,
    DateTime? endDate,
    String? query,
  }) => CollectionProvider._(
    argument: (
      page: page,
      size: size,
      tag: tag,
      platform: platform,
      status: status,
      author: author,
      startDate: startDate,
      endDate: endDate,
      query: query,
    ),
    from: this,
  );

  @override
  String toString() => r'collectionProvider';
}

abstract class _$Collection extends $AsyncNotifier<ShareCardListResponse> {
  late final _$args =
      ref.$arg
          as ({
            int page,
            int size,
            String? tag,
            String? platform,
            String? status,
            String? author,
            DateTime? startDate,
            DateTime? endDate,
            String? query,
          });
  int get page => _$args.page;
  int get size => _$args.size;
  String? get tag => _$args.tag;
  String? get platform => _$args.platform;
  String? get status => _$args.status;
  String? get author => _$args.author;
  DateTime? get startDate => _$args.startDate;
  DateTime? get endDate => _$args.endDate;
  String? get query => _$args.query;

  FutureOr<ShareCardListResponse> build({
    int page = 1,
    int size = 20,
    String? tag,
    String? platform,
    String? status,
    String? author,
    DateTime? startDate,
    DateTime? endDate,
    String? query,
  });
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
    element.handleCreate(
      ref,
      () => build(
        page: _$args.page,
        size: _$args.size,
        tag: _$args.tag,
        platform: _$args.platform,
        status: _$args.status,
        author: _$args.author,
        startDate: _$args.startDate,
        endDate: _$args.endDate,
        query: _$args.query,
      ),
    );
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
