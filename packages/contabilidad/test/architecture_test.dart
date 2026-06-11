import 'dart:io';
import 'package:test/test.dart';

/// Returns the cross-context `domain/` imports found in [lines].
///
/// A bounded context may import its own `domain/` and the [allowed] shared
/// packages (the shared kernel). Importing another context's `domain/` violates
/// ADR-0005 (Context Boundaries) and is reported as `"<lineNumber>: <line>"`.
List<String> findCrossContextDomainImports(
  Iterable<String> lines, {
  required String currentPackage,
  Set<String> allowed = const {'shared_kernel'},
}) {
  final importRegex = RegExp(r'''import\s+['"]package:([^/]+)/domain/''');
  final violations = <String>[];
  var lineNumber = 0;
  for (final line in lines) {
    lineNumber++;
    final match = importRegex.firstMatch(line);
    if (match == null) continue;
    final importedPackage = match.group(1);
    if (importedPackage != currentPackage &&
        !allowed.contains(importedPackage)) {
      violations.add('$lineNumber: $line');
    }
  }
  return violations;
}

void main() {
  group('findCrossContextDomainImports', () {
    test('flags an import of another context domain/', () {
      final violations = findCrossContextDomainImports([
        "import 'package:presupuesto/domain/budget.dart';",
      ], currentPackage: 'contabilidad');
      expect(violations, hasLength(1));
    });

    test('allows importing the shared kernel domain', () {
      final violations = findCrossContextDomainImports([
        "import 'package:shared_kernel/domain/money.dart';",
      ], currentPackage: 'contabilidad');
      expect(violations, isEmpty);
    });

    test('allows importing the own context domain/', () {
      final violations = findCrossContextDomainImports([
        "import 'package:contabilidad/domain/ledger.dart';",
      ], currentPackage: 'contabilidad');
      expect(violations, isEmpty);
    });

    test('ignores imports that are not domain/ paths', () {
      final violations = findCrossContextDomainImports([
        "import 'package:presupuesto/application/api.dart';",
      ], currentPackage: 'contabilidad');
      expect(violations, isEmpty);
    });
  });

  group('Architecture Rules', () {
    // NOTE: this test runs with the package directory as CWD, so it only proves
    // *this* context does not reach into another context's domain/. Global
    // enforcement of ADR-0005 requires the same test in every context package.
    test('contabilidad does not import the domain/ of other contexts', () {
      final libDir = Directory('lib');
      if (!libDir.existsSync()) return;

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      final violations = <String>[];
      for (final file in dartFiles) {
        final fileViolations = findCrossContextDomainImports(
          file.readAsLinesSync(),
          currentPackage: 'contabilidad',
        );
        violations.addAll(fileViolations.map((v) => '${file.path}:$v'));
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Found invalid domain imports from other bounded contexts:\n${violations.join('\n')}',
      );
    });

    test(
      'lib/ has domain/, application/, and infrastructure/ with placeholders',
      () {
        final libDir = Directory('lib');
        expect(
          libDir.existsSync(),
          isTrue,
          reason: 'lib/ directory does not exist',
        );

        for (final dir in const ['domain', 'application', 'infrastructure']) {
          final subDir = Directory('${libDir.path}/$dir');
          expect(
            subDir.existsSync(),
            isTrue,
            reason: 'Directory ${subDir.path} does not exist',
          );

          final hasDartFile = subDir.listSync().any(
            (e) => e is File && e.path.endsWith('.dart'),
          );
          expect(
            hasDartFile,
            isTrue,
            reason:
                'Directory ${subDir.path} must contain at least one .dart file',
          );
        }
      },
    );
  });
}
