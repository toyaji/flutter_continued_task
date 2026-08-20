#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_continued_task.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_continued_task'
  s.version          = '0.1.0'
  s.summary          = 'A Flutter plugin for continued background execution and progress reporting.'
  s.description      = <<-DESC
A Flutter plugin to ensure process lifecycle continuation and progress synchronization during long-running tasks in background across Android and iOS.
                       DESC
  s.homepage         = 'https://github.com/toyaji/flutter_continued_task'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'toyaji' => 'happytoday83@naver.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_continued_task/Sources/flutter_continued_task/**/*'
  s.dependency 'Flutter'
  # Note: The deployment target here is kept low (13.0) to ensure CocoaPods dependency resolution passes.
  # The actual runtime requirement is iOS 26 (when BGContinuedProcessingTask is available);
  # on earlier versions, it safely falls back to a no-op returning false.
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
