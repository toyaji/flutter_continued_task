// ignore_for_file: avoid_print
import 'dart:io';

void main(List<String> args) {
  print('🚀 [flutter_continued_task] Running iOS setup...');

  final projectDir = Directory.current;
  final infoPlistFile = File('${projectDir.path}/ios/Runner/Info.plist');

  if (!infoPlistFile.existsSync()) {
    print('⚠️  Could not find ios/Runner/Info.plist in the current directory (${projectDir.path}).');
    print('   Please run this command from the root of your Flutter project.');
    exit(1);
  }

  String taskIdentifier = 'com.example.app.continued_task';
  if (args.isNotEmpty) {
    taskIdentifier = args.first;
  } else {
    // Read CFBundleIdentifier from Info.plist or use default
    print('ℹ️  No task identifier provided. Using default "$taskIdentifier".');
    print('   Tip: You can pass your custom task identifier: dart run flutter_continued_task:setup your.custom.task.id');
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
        content = content.substring(0, insertIndex) + backgroundModesXml + content.substring(insertIndex);
        modified = true;
        print('✅ Added UIBackgroundModes with "processing" to Info.plist.');
      }
    } else if (!content.contains('<string>processing</string>')) {
      final modeRegex = RegExp(r'<key>UIBackgroundModes</key>\s*<array>');
      final match = modeRegex.firstMatch(content);
      if (match != null) {
        final insertIndex = match.end;
        content = '${content.substring(0, insertIndex)}\n\t\t<string>processing</string>${content.substring(insertIndex)}';
        modified = true;
        print('✅ Appended "processing" to existing UIBackgroundModes in Info.plist.');
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
        content = content.substring(0, insertIndex) + permittedIdsXml + content.substring(insertIndex);
        modified = true;
        print('✅ Added BGTaskSchedulerPermittedIdentifiers with "$taskIdentifier" to Info.plist.');
      }
    } else if (!content.contains('<string>$taskIdentifier</string>')) {
      final idRegex = RegExp(r'<key>BGTaskSchedulerPermittedIdentifiers</key>\s*<array>');
      final match = idRegex.firstMatch(content);
      if (match != null) {
        final insertIndex = match.end;
        content = '${content.substring(0, insertIndex)}\n\t\t<string>$taskIdentifier</string>${content.substring(insertIndex)}';
        modified = true;
        print('✅ Appended "$taskIdentifier" to existing BGTaskSchedulerPermittedIdentifiers in Info.plist.');
      }
    }

    if (modified) {
      infoPlistFile.writeAsStringSync(content);
      print('🎉 Successfully updated ios/Runner/Info.plist!');
    } else {
      print('✨ Info.plist is already configured with all required background keys.');
    }
  } catch (e) {
    print('❌ Error modifying Info.plist: $e');
    exit(1);
  }
}
