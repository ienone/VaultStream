import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/distribution_rule_editor.dart';

/// Each route instance owns its form; browser exits use the same confirmation.
final ruleEditorKeyProvider = Provider.autoDispose
    .family<GlobalKey<DistributionRuleEditorState>, ValueKey<String>>(
      (ref, routeKey) => GlobalKey<DistributionRuleEditorState>(),
    );
