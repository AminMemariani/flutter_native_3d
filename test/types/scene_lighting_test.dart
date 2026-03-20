import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_3d/flutter_native_3d.dart';

void main() {
  group('SceneLighting', () {
    test('presets are distinct', () {
      final presets = <SceneLighting>[
        SceneLighting.studio,
        SceneLighting.natural,
        SceneLighting.dramatic,
        SceneLighting.neutral,
        SceneLighting.unlit,
      ];
      final unique = presets.toSet();
      expect(unique.length, 5);
    });

    test('same preset is equal', () {
      expect(SceneLighting.studio, equals(SceneLighting.studio));
      expect(SceneLighting.studio.hashCode, equals(SceneLighting.studio.hashCode));
    });

    test('different presets are not equal', () {
      expect(SceneLighting.studio, isNot(equals(SceneLighting.dramatic)));
    });

    test('toString produces readable names', () {
      expect(SceneLighting.studio.toString(), 'SceneLighting.studio');
      expect(SceneLighting.dramatic.toString(), 'SceneLighting.dramatic');
      expect(SceneLighting.unlit.toString(), 'SceneLighting.unlit');
    });
  });
}
