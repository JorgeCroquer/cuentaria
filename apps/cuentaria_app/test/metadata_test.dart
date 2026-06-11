import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('.metadata contains required platforms', () {
    final file = File('.metadata');
    expect(file.existsSync(), isTrue, reason: '.metadata file should exist');

    final content = file.readAsStringSync();
    
    // The platforms that must be configured in this project
    expect(content, contains('- platform: android'));
    expect(content, contains('- platform: web'));
    expect(content, contains('- platform: ios'));
  });
}
