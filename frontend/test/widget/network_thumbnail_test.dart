import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/network_thumbnail.dart';

void main() {
  testWidgets('带鉴权头的缩略图使用 Flutter 网络图片解码路径', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NetworkThumbnail(
          imageUrl: 'http://localhost/media/image.webp',
          httpHeaders: {'X-API-Token': 'test-token'},
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.headers, containsPair('X-API-Token', 'test-token'));
  });
}
