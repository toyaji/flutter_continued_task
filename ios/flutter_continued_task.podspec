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
  s.homepage         = 'https://github.com/zellypaw/zelly-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Zelly' => 'contact@zellypaw.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  # **설치 하한과 동작 하한이 다르다.**
  # 여기(설치 하한)는 낮게 둔다 — 올리면 deployment target이 더 낮은 앱은
  # CocoaPods가 의존성 해석 단계에서 거부해 **빌드 자체가 불가능**해진다.
  # 실제 동작 하한은 iOS 26(BGContinuedProcessingTask 도입)이며, 그 아래에서는
  # `#available` 가드로 조용히 no-op이 된다(`start`가 false를 돌려준다).
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
