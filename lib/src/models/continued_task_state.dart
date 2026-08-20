import 'package:flutter/foundation.dart';

/// Synchronized native state information for continued background tasks.
@immutable
class ContinuedTaskNativeState {
  const ContinuedTaskNativeState({
    required this.assertionHeld,
    required this.stopRequested,
  });

  /// Whether the native component (FGS / BGContinuedProcessingTask) is currently holding process assertion.
  final bool assertionHeld;

  /// Whether the user requested a stop (e.g. notification action button) while the UI was detached.
  final bool stopRequested;

  factory ContinuedTaskNativeState.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const ContinuedTaskNativeState(
        assertionHeld: false,
        stopRequested: false,
      );
    }
    return ContinuedTaskNativeState(
      assertionHeld: map['assertionHeld'] == true,
      stopRequested: map['stopRequested'] == true,
    );
  }
}
