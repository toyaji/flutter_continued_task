import 'package:flutter/foundation.dart';

/// 네이티브로부터 동기화된 태스크 상태 정보
@immutable
class ContinuedTaskNativeState {
  const ContinuedTaskNativeState({
    required this.assertionHeld,
    required this.stopRequested,
  });

  /// 네이티브 컴포넌트(FGS/BGContinuedProcessingTask)가 현재 수명을 확보하고 있는지 여부
  final bool assertionHeld;

  /// 액티비티가 없던 동안 사용자가 알림의 중단 버튼을 눌렀는지 여부
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
