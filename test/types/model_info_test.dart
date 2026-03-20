import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_3d/flutter_native_3d.dart';

void main() {
  group('ModelInfo', () {
    test('hasAnimations is true when animations exist', () {
      const info = ModelInfo(animationNames: ['Walk', 'Run']);
      expect(info.hasAnimations, isTrue);
    });

    test('hasAnimations is false for empty list', () {
      const info = ModelInfo(animationNames: []);
      expect(info.hasAnimations, isFalse);
    });

    test('animationCount returns correct count', () {
      const info = ModelInfo(animationNames: ['Walk', 'Run', 'Jump']);
      expect(info.animationCount, 3);
    });

    test('animationCount is 0 for empty list', () {
      const info = ModelInfo(animationNames: []);
      expect(info.animationCount, 0);
    });
  });
}
