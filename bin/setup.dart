// ignore_for_file: avoid_print
import 'dart:io';

void main(List<String> args) {
  print('🚀 [flutter_continued_task] Running iOS setup...');

  final projectDir = Directory.current;
  final infoPlistFile = File('${projectDir.path}/ios/Runner/Info.plist');

  if (!infoPlistFile.existsSync()) {
    print(
        '⚠️  Could not find ios/Runner/Info.plist in the current directory (${projectDir.path}).');
    print('   Please run this command from the root of your Flutter project.');
    exit(1);
  }

  final String taskIdentifier;
  if (args.isNotEmpty) {
    taskIdentifier = args.first;
  } else {
    final bundleId = _resolveBundleIdentifier(projectDir, infoPlistFile);
    if (bundleId == null) {
      print('❌ Could not resolve this app\'s bundle identifier automatically.');
      print(
          '   iOS requires the BGTaskScheduler identifier to be prefixed with your bundle ID,');
      print(
          '   so a placeholder would silently break background continuation at runtime.');
      print(
          '   Pass it explicitly: dart run flutter_continued_task:setup <your.bundle.id>.continued_task');
      exit(1);
    }
    taskIdentifier = '$bundleId.continued_task';
    print('ℹ️  Resolved bundle identifier "$bundleId".');
    print('   Using task identifier "$taskIdentifier".');
  }

  try {
    var content = infoPlistFile.readAsStringSync();
    var modified = false;

    // 1. Add 'processing' to UIBackgroundModes
    if (!content.contains('<key>UIBackgroundModes</key>')) {
      final insertIndex = content.lastIndexOf('</dict>');
      if (insertIndex != -1) {
        const backgroundModesXml = '''
\t<key>UIBackgroundModes</key>
\t<array>
\t\t<string>processing</string>
\t</array>
''';
        content = content.substring(0, insertIndex) +
            backgroundModesXml +
            content.substring(insertIndex);
        modified = true;
        print('✅ Added UIBackgroundModes with "processing" to Info.plist.');
      }
    } else if (!content.contains('<string>processing</string>')) {
      final modeRegex = RegExp(r'<key>UIBackgroundModes</key>\s*<array>');
      final match = modeRegex.firstMatch(content);
      if (match != null) {
        final insertIndex = match.end;
        content =
            '${content.substring(0, insertIndex)}\n\t\t<string>processing</string>${content.substring(insertIndex)}';
        modified = true;
        print(
            '✅ Appended "processing" to existing UIBackgroundModes in Info.plist.');
      }
    }

    // 2. Add task identifier to BGTaskSchedulerPermittedIdentifiers
    if (!content.contains('<key>BGTaskSchedulerPermittedIdentifiers</key>')) {
      final insertIndex = content.lastIndexOf('</dict>');
      if (insertIndex != -1) {
        final permittedIdsXml = '''
\t<key>BGTaskSchedulerPermittedIdentifiers</key>
\t<array>
\t\t<string>$taskIdentifier</string>
\t</array>
''';
        content = content.substring(0, insertIndex) +
            permittedIdsXml +
            content.substring(insertIndex);
        modified = true;
        print(
            '✅ Added BGTaskSchedulerPermittedIdentifiers with "$taskIdentifier" to Info.plist.');
      }
    } else if (!content.contains('<string>$taskIdentifier</string>')) {
      final idRegex =
          RegExp(r'<key>BGTaskSchedulerPermittedIdentifiers</key>\s*<array>');
      final match = idRegex.firstMatch(content);
      if (match != null) {
        final insertIndex = match.end;
        content =
            '${content.substring(0, insertIndex)}\n\t\t<string>$taskIdentifier</string>${content.substring(insertIndex)}';
        modified = true;
        print(
            '✅ Appended "$taskIdentifier" to existing BGTaskSchedulerPermittedIdentifiers in Info.plist.');
      }
    }

    if (modified) {
      infoPlistFile.writeAsStringSync(content);
      print('🎉 Successfully updated ios/Runner/Info.plist!');
    } else {
      print(
          '✨ Info.plist is already configured with all required background keys.');
    }
  } catch (e) {
    print('❌ Error modifying Info.plist: $e');
    exit(1);
  }
}

/// Resolves the app's concrete bundle identifier.
///
/// `CFBundleIdentifier` in a Flutter project's Info.plist is normally the build
/// setting placeholder `$(PRODUCT_BUNDLE_IDENTIFIER)`, so the Xcode project is
/// consulted whenever the plist does not hold a literal value. Returns null when
/// no literal identifier can be determined.
String? _resolveBundleIdentifier(Directory projectDir, File infoPlistFile) {
  final plistMatch = RegExp(
    r'<key>CFBundleIdentifier</key>\s*<string>([^<]*)</string>',
  ).firstMatch(infoPlistFile.readAsStringSync());
  final fromPlist = plistMatch?.group(1)?.trim();
  if (fromPlist != null && fromPlist.isNotEmpty && !fromPlist.contains(r'$(')) {
    return fromPlist;
  }

  final pbxproj =
      File('${projectDir.path}/ios/Runner.xcodeproj/project.pbxproj');
  if (!pbxproj.existsSync()) return null;

  for (final match in RegExp(
    r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
  ).allMatches(pbxproj.readAsStringSync())) {
    final value = match.group(1)!.trim().replaceAll('"', '');
    // Test and extension targets append a suffix to the app's identifier.
    if (value.isEmpty ||
        value.contains(r'$(') ||
        value.endsWith('.RunnerTests')) {
      continue;
    }
    return value;
  }
  return null;
}
