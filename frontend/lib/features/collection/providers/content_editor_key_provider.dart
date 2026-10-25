import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/content_editor.dart';

final contentEditorKeyProvider = Provider.autoDispose
    .family<GlobalKey<ContentEditorState>, (ValueKey<String>, int)>(
      (ref, routeKey) => GlobalKey<ContentEditorState>(),
    );
