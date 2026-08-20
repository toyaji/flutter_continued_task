import 'package:flutter/foundation.dart';

/// 계속 실행 태스크의 초기 설정 모델
@immutable
class ContinuedTaskConfig {
  const ContinuedTaskConfig({
    required this.title,
    this.taskId = 'default_task',
    this.subtitle,
    this.initialProgress = 0,
    this.maxProgress = 100,
    this.indeterminate = false,
    this.allowCancel = true,
    this.cancelActionLabel = '중단',
    this.androidNotificationIcon,
    this.androidChannelId = 'continued_task_channel',
    this.androidChannelName = 'Background Task',
    this.androidChannelDescription = 'Shows ongoing progress for continued tasks',
    this.iosTaskIdentifier,
  });

  /// 태스크 고유 식별자 (기본값: 'default_task')
  final String taskId;

  /// 시스템 알림 및 잠금화면에 노출될 메인 제목
  final String title;

  /// 시스템 알림 및 잠금화면에 노출될 보조 설명/부제목
  final String? subtitle;

  /// 초기 진행률 값
  final int initialProgress;

  /// 최대 진행률 값
  final int maxProgress;

  /// 진행률 불특정(스피너) 여부
  final bool indeterminate;

  /// 알림 UI에 사용자 '중단' 액션 버튼을 노출할지 여부
  final bool allowCancel;

  /// 사용자 중단 액션 버튼의 라벨 (예: "중단", "취소", "Cancel")
  final String cancelActionLabel;

  /// Android 알림 아이콘 drawable 리소스명 또는 프리셋 키워드('upload', 'download', 'sync', 'processing').
  /// null일 경우 기본 동기화 벡터 아이콘('ic_continued_task_sync')이 자동 적용됩니다.
  final String? androidNotificationIcon;

  /// Android 알림 채널 ID
  final String androidChannelId;

  /// Android 알림 채널 이름
  final String androidChannelName;

  /// Android 알림 채널 설명
  final String androidChannelDescription;

  /// iOS `BGContinuedProcessingTask` 식별자 (Info.plist의 `BGTaskSchedulerPermittedIdentifiers`와 일치해야 함)
  final String? iosTaskIdentifier;

  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'title': title,
      'subtitle': subtitle,
      'initialProgress': initialProgress,
      'maxProgress': maxProgress,
      'indeterminate': indeterminate,
      'allowCancel': allowCancel,
      'cancelActionLabel': cancelActionLabel,
      'androidNotificationIcon': androidNotificationIcon,
      'androidChannelId': androidChannelId,
      'androidChannelName': androidChannelName,
      'androidChannelDescription': androidChannelDescription,
      'iosTaskIdentifier': iosTaskIdentifier,
    };
  }
}
