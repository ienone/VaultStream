import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'share_receiver_service.g.dart';

/// 分享内容数据模型
class SharedContent {
  final String? text;
  final List<SharedMediaFile> mediaFiles;
  final DateTime receivedAt;

  SharedContent({
    this.text,
    this.mediaFiles = const [],
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  /// 提取 URL (从分享文本中)
  String? get extractedUrl {
    if (text == null) return null;
    final urlRegex = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
    );
    final match = urlRegex.firstMatch(text!);
    return match?.group(0);
  }

  bool get hasUrl => extractedUrl != null;
  bool get hasMedia => mediaFiles.isNotEmpty;
  bool get isEmpty => text == null && mediaFiles.isEmpty;
}

/// 分享接收状态
@riverpod
class ShareReceiverState extends _$ShareReceiverState {
  @override
  SharedContent? build() => null;

  void setSharedContent(SharedContent? content) {
    state = content;
  }

  void clear() {
    state = null;
  }
}

/// 分享接收服务 - 管理分享 intent 的监听
class ShareReceiverService {
  StreamSubscription? _intentSubscription;
  final Ref _ref;
  bool _initialized = false;

  ShareReceiverService(this._ref);

  void initialize() {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    _intentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        _handleSharedMedia(files);
      },
      onError: (_) {},
    );

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        _handleSharedMedia(files);
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  void _handleSharedMedia(List<SharedMediaFile> files) {
    if (files.isEmpty) {
      return;
    }

    // 分离文本和媒体文件
    String? sharedText;
    final mediaFiles = <SharedMediaFile>[];

    for (final file in files) {
      if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        sharedText = file.path;
      } else {
        mediaFiles.add(file);
      }
    }

    final content = SharedContent(
      text: sharedText,
      mediaFiles: mediaFiles,
    );

    if (!content.isEmpty) {
      _ref.read(shareReceiverStateProvider.notifier).setSharedContent(content);
    }
  }

  void clearSharedContent() {
    _ref.read(shareReceiverStateProvider.notifier).clear();
    if (!kIsWeb) {
      ReceiveSharingIntent.instance.reset();
    }
  }

  /// 释放资源
  void dispose() {
    _intentSubscription?.cancel();
  }
}

/// 分享接收服务 Provider
@riverpod
ShareReceiverService shareReceiverService(Ref ref) {
  final service = ShareReceiverService(ref);
  ref.onDispose(() => service.dispose());
  return service;
}
