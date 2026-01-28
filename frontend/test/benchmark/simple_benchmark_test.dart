import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/review/models/queue_item.dart';
import 'package:frontend/features/review/widgets/queue_content_list.dart';

void main() {
  testWidgets('QueueContentList rendering benchmark', (WidgetTester tester) async {
    // Create a large list of items to simulate load
    final items = List.generate(100, (index) => QueueItem(
      id: index,
      contentId: index + 1000,
      title: 'Benchmark Item $index ' * 5, // Long title
      platform: index % 2 == 0 ? 'twitter' : 'bilibili',
      tags: ['tag1', 'tag2', 'tag3'],
      status: 'will_push',
      scheduledTime: DateTime.now().add(Duration(minutes: index)),
    ));

    final stopwatch = Stopwatch()..start();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: QueueContentList(
              items: items,
              currentStatus: QueueStatus.willPush,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );

    // Measure first frame render time
    await tester.pump();
    stopwatch.stop();

    final elapsed = stopwatch.elapsedMilliseconds;
    print('QueueContentList with 100 items rendered in ${elapsed}ms');

    // Basic assertion to ensure it's "fast enough"
    expect(elapsed, lessThan(1000), reason: 'Rendering took too long');
    
    // Verify scrolling performance (basic check)
    // Need to find the Scrollable
    final listFinder = find.byType(Scrollable);
    expect(listFinder, findsOneWidget);

    stopwatch.reset();
    stopwatch.start();
    
    await tester.fling(listFinder, const Offset(0, -500), 1000);
    await tester.pumpAndSettle();
    
    stopwatch.stop();
    print('Scrolling list took ${stopwatch.elapsedMilliseconds}ms');
  });
}