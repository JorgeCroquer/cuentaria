import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Architecture Rules', () {
    test('Packages should not import the domain/ of other bounded contexts', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();

      final violations = <String>[];
      final importRegex = RegExp(r'''import\s+['"]package:([^/]+)/domain/.*''');
      // The current package's name. We can read it from pubspec or just allow contabilidad
      const currentPackage = 'contabilidad';

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final match = importRegex.firstMatch(line);
          if (match != null) {
            final importedPackage = match.group(1);
            if (importedPackage != currentPackage && importedPackage != 'shared_kernel') {
              violations.add('${file.path}:${i + 1} -> $line');
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        fail('Found invalid domain imports from other bounded contexts:\n' +
            violations.join('\n'));
      }
    });

    test('Packages should have domain/, application/, and infrastructure/ directories with dart placeholders', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) fail('lib/ directory does not exist');

      final expectedDirs = ['domain', 'application', 'infrastructure'];
      for (final dir in expectedDirs) {
        final dirDir = Directory('${libDir.path}/$dir');
        if (!dirDir.existsSync()) {
          fail('Directory ${dirDir.path} does not exist');
        }

        final hasDartFile = dirDir.listSync().any((e) => e is File && e.path.endsWith('.dart'));
        if (!hasDartFile) {
          fail('Directory ${dirDir.path} must contain at least one .dart file');
        }
      }
    });
  });
}
