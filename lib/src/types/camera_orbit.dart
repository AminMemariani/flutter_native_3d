/// Defines the camera position as a spherical orbit around the model center.
class CameraOrbit {
  /// Horizontal rotation in degrees. 0 = front, 90 = right side.
  final double theta;

  /// Vertical rotation in degrees. 0 = eye level, 90 = top-down.
  /// Clamped to -89..89 by the native side.
  final double phi;

  /// Distance from the camera to the model center. Must be positive.
  final double radius;

  const CameraOrbit({
    this.theta = 0,
    this.phi = 20,
    this.radius = 3,
  }) : assert(radius > 0, 'Camera radius must be positive');

  static const defaultOrbit = CameraOrbit();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraOrbit &&
          other.theta == theta &&
          other.phi == phi &&
          other.radius == radius;

  @override
  int get hashCode => Object.hash(theta, phi, radius);

  @override
  String toString() =>
      'CameraOrbit(theta: $theta, phi: $phi, radius: $radius)';
}
