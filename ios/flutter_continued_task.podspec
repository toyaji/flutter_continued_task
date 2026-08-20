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
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
