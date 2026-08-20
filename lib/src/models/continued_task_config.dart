import 'package:flutter/foundation.dart';

/// Configuration model for starting a continued background task.
@immutable
class ContinuedTaskConfig {
  /// Creates a configuration for a continued background task.
  const ContinuedTaskConfig({
    this.title = 'Task in progress',
    this.taskId = 'default_task',
    this.subtitle,
    this.initialProgress = 0,
    this.maxProgress = 100,
    this.indeterminate = false,
    this.allowCancel = true,
    this.cancelActionLabel = 'Cancel',
    this.androidNotificationIcon,
    this.androidChannelId = 'continued_task_channel',
    this.androidChannelName = 'Background Task',
    this.androidChannelDescription =
        'Shows ongoing progress for continued tasks',
    this.iosTaskIdentifier,
  });

  /// Unique task identifier (defaults to 'default_task').
  final String taskId;

  /// Main title displayed on system notifications and lock screen.
  final String title;

  /// Subtitle or secondary description displayed on system notifications and lock screen.
  final String? subtitle;

  /// Initial progress value.
  final int initialProgress;

  /// Maximum progress value.
  final int maxProgress;

  /// Whether the progress is indeterminate (spinner style).
  final bool indeterminate;

  /// Whether to display a user "Cancel" action button on the system notification.
  final bool allowCancel;

  /// Label for the cancel action button (defaults to 'Cancel').
  final String cancelActionLabel;

  /// Android notification icon drawable resource name or preset keyword ('upload', 'download', 'sync', 'processing').
  /// Defaults to 'ic_continued_task_sync' if null.
  final String? androidNotificationIcon;

  /// Android notification channel ID.
  final String androidChannelId;

  /// Android notification channel name.
  final String androidChannelName;

  /// Android notification channel description.
  final String androidChannelDescription;

  /// iOS `BGContinuedProcessingTask` identifier (must match `BGTaskSchedulerPermittedIdentifiers` in `Info.plist`).
  final String? iosTaskIdentifier;

  /// Creates a copy of this config with the given fields replaced.
  ContinuedTaskConfig copyWith({
    String? taskId,
    String? title,
    String? subtitle,
    int? initialProgress,
    int? maxProgress,
    bool? indeterminate,
    bool? allowCancel,
    String? cancelActionLabel,
    String? androidNotificationIcon,
    String? androidChannelId,
    String? androidChannelName,
    String? androidChannelDescription,
    String? iosTaskIdentifier,
  }) {
    return ContinuedTaskConfig(
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      initialProgress: initialProgress ?? this.initialProgress,
      maxProgress: maxProgress ?? this.maxProgress,
      indeterminate: indeterminate ?? this.indeterminate,
      allowCancel: allowCancel ?? this.allowCancel,
      cancelActionLabel: cancelActionLabel ?? this.cancelActionLabel,
      androidNotificationIcon:
          androidNotificationIcon ?? this.androidNotificationIcon,
      androidChannelId: androidChannelId ?? this.androidChannelId,
      androidChannelName: androidChannelName ?? this.androidChannelName,
      androidChannelDescription:
          androidChannelDescription ?? this.androidChannelDescription,
      iosTaskIdentifier: iosTaskIdentifier ?? this.iosTaskIdentifier,
    );
  }

  /// Serializes this config into the payload sent over the method channel.
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
