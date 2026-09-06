import 'package:file_selector/file_selector.dart';

enum CaptureKind { link, text, file }

/// Unified input state for app capture and operating-system share intents.
class CaptureDraft {
  const CaptureDraft({
    this.url,
    this.text,
    this.files = const [],
    this.title,
    this.note,
    this.source = 'manual_paste',
    this.receivedAt,
    this.initialKind,
  });

  final String? url;
  final String? text;
  final List<XFile> files;
  final String? title;
  final String? note;
  final String source;
  final DateTime? receivedAt;
  final CaptureKind? initialKind;

  CaptureKind get effectiveInitialKind {
    if (initialKind != null) return initialKind!;
    if (files.isNotEmpty) return CaptureKind.file;
    if ((url ?? '').trim().isNotEmpty) return CaptureKind.link;
    if ((text ?? '').trim().isNotEmpty) return CaptureKind.text;
    return CaptureKind.link;
  }

  Map<String, dynamic>? get clientContext => receivedAt == null
      ? null
      : {'received_at': receivedAt!.toUtc().toIso8601String()};
}
