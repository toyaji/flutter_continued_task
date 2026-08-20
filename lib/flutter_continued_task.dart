/// Keeps long-running work alive when the app leaves the foreground.
///
/// On Android this is a `dataSync` foreground service with a progress
/// notification; on iOS 26+ it is a `BGContinuedProcessingTask` surfaced on the
/// Lock Screen. Start from [ContinuedTask.track] for the high-level API.
library flutter_continued_task;

export 'src/continued_task.dart';
export 'src/continued_task_platform_interface.dart';
export 'src/models/continued_task_config.dart';
export 'src/models/continued_task_state.dart';
export 'src/task_tracker.dart';
