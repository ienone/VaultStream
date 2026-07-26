import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/collection/collection_page.dart';
import 'package:frontend/features/collection/models/content.dart';
import 'package:frontend/features/collection/providers/collection_filter_provider.dart';
import 'package:frontend/features/collection/providers/collection_provider.dart';
import 'package:frontend/features/collection/widgets/list/content_card.dart';
import 'package:mockito/mockito.dart';

class _StubDio extends Mock implements Dio {
  @override
  BaseOptions get options =>
      BaseOptions(baseUrl: 'http://localhost', headers: {});
}

ShareCard _card(
  int id, {
  String? title,
  String? status,
  String platform = 'zhihu',
}) {
  return ShareCard(
    id: id,
    platform: platform,
    url: 'https://example.test/$id',
    status: status,
    title: title ?? '内容 $id',
    authorName: '作者 $id',
    layoutType: 'article',
    createdAt: DateTime(2026, 5, 20),
  );
}

ShareCardListResponse _response(List<ShareCard> items) => ShareCardListResponse(
  items: items,
  total: items.length,
  page: 1,
  size: 20,
  hasMore: false,
);

Widget _host({
  required ShareCardListResponse response,
  CollectionFilterState? filter,
  Size size = const Size(400, 800),
}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(_StubDio()),
      collectionProvider.overrideWith(() => _StubCollection(response)),
      collectionFilterProvider.overrideWith(
        () => _StubFilter(filter ?? const CollectionFilterState()),
      ),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const CollectionPage(),
      ),
    ),
  );
}

class _StubCollection extends Collection {
  _StubCollection(this._response);
  final ShareCardListResponse _response;

  @override
  Future<ShareCardListResponse> build() async => _response;
}

class _StubFilter extends CollectionFilter {
  _StubFilter(this._initial);
  final CollectionFilterState _initial;

  @override
  CollectionFilterState build() => _initial;
}

void main() {
  testWidgets('内容以等节奏网格呈现，不使用瀑布流', (tester) async {
    await tester.pumpWidget(
      _host(response: _response([_card(1), _card(2), _card(3)])),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ContentCard), findsNWidgets(3));
    // 混合内容默认不得使用 masonry 布局
    expect(find.byType(SliverMasonryGrid), findsNothing);
    expect(find.byType(SliverGrid), findsOneWidget);
  });

  testWidgets('窄屏在内容区顶部使用胶囊搜索条，并保留刷新和筛选动作', (tester) async {
    await tester.pumpWidget(_host(response: _response([_card(1)])));
    await tester.pumpAndSettle();

    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.byType(SearchBar)),
      findsNothing,
    );
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    // 搜索模式切换不再是顶栏的独立按钮
    expect(find.byIcon(Icons.psychology_alt_rounded), findsNothing);
    expect(find.byIcon(Icons.manage_search_rounded), findsNothing);
  });

  testWidgets('宽屏搜索胶囊紧邻标题并在顶栏内保留上下间距', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _host(response: _response([_card(1)]), size: const Size(1100, 800)),
    );
    await tester.pumpAndSettle();

    final appBar = find.byType(AppBar);
    final searchBar = find.byType(SearchBar);
    expect(find.descendant(of: appBar, matching: searchBar), findsOneWidget);

    final appBarRect = tester.getRect(appBar);
    final searchRect = tester.getRect(searchBar);
    expect(searchRect.top, greaterThan(appBarRect.top));
    expect(searchRect.bottom, lessThan(appBarRect.bottom));

    final titleRect = tester.getRect(find.text('收藏库'));
    expect(searchRect.left - titleRect.right, lessThanOrEqualTo(32));
  });

  testWidgets('没有筛选时不显示筛选摘要行', (tester) async {
    await tester.pumpWidget(_host(response: _response([_card(1)])));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);
    expect(find.text('清除'), findsNothing);
  });

  testWidgets('已生效筛选以可移除的摘要 chip 呈现，并显示结果数', (tester) async {
    await tester.pumpWidget(
      _host(
        response: _response([_card(1), _card(2)]),
        filter: const CollectionFilterState(
          platforms: ['zhihu'],
          tags: ['ai'],
          searchQuery: '向量',
          searchMode: 'semantic',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('语义: 向量'), findsOneWidget);
    expect(find.text('zhihu'), findsOneWidget);
    expect(find.text('#ai'), findsOneWidget);
    expect(find.text('2 条'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(3));
    expect(find.text('清除'), findsOneWidget);
  });

  testWidgets('空结果区分"没有内容"与"筛选没有命中"', (tester) async {
    await tester.pumpWidget(_host(response: _response([])));
    await tester.pumpAndSettle();
    expect(find.text('收藏库还是空的'), findsOneWidget);

    // 销毁上一棵 ProviderScope，避免同一容器保留第一次的 filter notifier。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(
        response: _response([]),
        filter: const CollectionFilterState(platforms: ['zhihu']),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的内容'), findsOneWidget);
    expect(find.text('清除全部筛选'), findsOneWidget);
  });

  testWidgets('搜索面板用文字说明两种搜索模式，不让用户猜图标', (tester) async {
    await tester.pumpWidget(_host(response: _response([_card(1)])));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '向量检索');
    await tester.pumpAndSettle();

    expect(find.text('精确与全文搜索 "向量检索"'), findsOneWidget);
    expect(find.text('语义相关搜索 "向量检索"'), findsOneWidget);
  });

  testWidgets('卡片显示解析失败状态', (tester) async {
    await tester.pumpWidget(
      _host(response: _response([_card(1, status: 'parse_failed')])),
    );
    await tester.pumpAndSettle();

    expect(find.text('解析失败'), findsOneWidget);
  });

  testWidgets('缺失标题时显式说明，不留空', (tester) async {
    await tester.pumpWidget(_host(response: _response([_card(1, title: '')])));
    await tester.pumpAndSettle();

    expect(find.text('无标题'), findsOneWidget);
  });

  testWidgets('宽屏使用更多列，窄屏使用紧凑双列', (tester) async {
    final items = List.generate(8, (i) => _card(i + 1));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    tester.view.physicalSize = const Size(400, 900);
    await tester.pumpWidget(
      _host(response: _response(items), size: const Size(400, 900)),
    );
    await tester.pumpAndSettle();
    final narrowGrid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(
      (narrowGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );

    tester.view.physicalSize = const Size(1300, 900);
    await tester.pumpWidget(
      _host(response: _response(items), size: const Size(1300, 900)),
    );
    await tester.pumpAndSettle();
    final wideGrid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(
      (wideGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      4,
    );
  });
}
