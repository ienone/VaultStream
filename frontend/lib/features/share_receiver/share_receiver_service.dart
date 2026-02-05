import 'dart:async';
import 'package:flutter/material.dart';
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

  /// 初始化分享监听
  void initialize() {
    if (_initialized) return;
    _initialized = true;
    
    debugPrint('📥 ShareReceiverService: 初始化分享监听...');

    // 监听应用运行时收到的分享
    _intentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        debugPrint('📥 ShareReceiver: 收到流分享, ${files.length} 个文件');
        _handleSharedMedia(files);
      },
      onError: (err) {
        debugPrint('📥 ShareReceiver stream error: $err');
      },
    );

    // 检查应用启动时是否有分享内容（冷启动）
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      debugPrint('📥 ShareReceiver: 初始分享检查, ${files.length} 个文件');
      if (files.isNotEmpty) {
        _handleSharedMedia(files);
        // 处理完后重置，避免重复处理
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  void _handleSharedMedia(List<SharedMediaFile> files) {
    if (files.isEmpty) {
      debugPrint('📥 ShareReceiver: 空文件列表，跳过');
      return;
    }

    // 打印详细信息用于调试
    for (final file in files) {
      debugPrint('📥 ShareReceiver 文件: type=${file.type}, path=${file.path}');
    }

    // 分离文本和媒体文件
    String? sharedText;
    final mediaFiles = <SharedMediaFile>[];

    for (final file in files) {
      if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        sharedText = file.path;
        debugPrint('📥 ShareReceiver: 检测到文本/URL: $sharedText');
      } else {
        mediaFiles.add(file);
      }
    }

    final content = SharedContent(
      text: sharedText,
      mediaFiles: mediaFiles,
    );

    debugPrint('📥 ShareReceiver: 创建 SharedContent, text=$sharedText, isEmpty=${content.isEmpty}');

    if (!content.isEmpty) {
      debugPrint('📥 ShareReceiver: 设置分享内容到状态');
      _ref.read(shareReceiverStateProvider.notifier).setSharedContent(content);
    }
  }

  /// 清除分享内容并重置 intent
  void clearSharedContent() {
    _ref.read(shareReceiverStateProvider.notifier).clear();
    ReceiveSharingIntent.instance.reset();
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
