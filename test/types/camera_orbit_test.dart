import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_3d/flutter_native_3d.dart';

void main() {
  group('CameraOrbit', () {
    test('default values', () {
      const orbit = CameraOrbit();
      expect(orbit.theta, 0);
      expect(orbit.phi, 20);
      expect(orbit.radius, 3);
    });

    test('defaultOrbit matches default constructor', () {
      expect(CameraOrbit.defaultOrbit, const CameraOrbit());
    });

    test('equality', () {
      const a = CameraOrbit(theta: 45, phi: 30, radius: 5);
      const b = CameraOrbit(theta: 45, phi: 30, radius: 5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality on different theta', () {
      const a = CameraOrbit(theta: 10);
      const b = CameraOrbit(theta: 20);
      expect(a, isNot(equals(b)));
    });

    test('inequality on different phi', () {
      const a = CameraOrbit(phi: 10);
      const b = CameraOrbit(phi: 20);
      expect(a, isNot(equals(b)));
    });

    test('inequality on different radius', () {
      const a = CameraOrbit(radius: 3);
      const b = CameraOrbit(radius: 5);
      expect(a, isNot(equals(b)));
    });

    test('rejects non-positive radius in debug', () {
      expect(() => CameraOrbit(radius: 0), throwsA(isA<AssertionError>()));
      expect(() => CameraOrbit(radius: -1), throwsA(isA<AssertionError>()));
    });

    test('toString', () {
      const orbit = CameraOrbit(theta: 45, phi: 30, radius: 5);
      expect(orbit.toString(), 'CameraOrbit(theta: 45.0, phi: 30.0, radius: 5.0)');
    });
  });
}
