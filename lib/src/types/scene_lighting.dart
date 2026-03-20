/// Predefined lighting setups for the 3D scene.
///
/// Each preset maps to a specific light configuration on the native side.
/// Custom lighting with explicit parameters will be added in a future version.
sealed class SceneLighting {
  const SceneLighting();

  /// Balanced three-point lighting. Good for product shots.
  static const studio = PresetLighting._('studio');

  /// Soft, even lighting simulating outdoor shade.
  static const natural = PresetLighting._('natural');

  /// High-contrast lighting with strong directional light.
  static const dramatic = PresetLighting._('dramatic');

  /// Flat, even lighting with minimal shadows.
  static const neutral = PresetLighting._('neutral');

  /// No lighting applied. Displays raw material/texture colors.
  static const unlit = PresetLighting._('unlit');
}

final class PresetLighting extends SceneLighting {
  final String name;
  const PresetLighting._(this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresetLighting && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'SceneLighting.$name';
}
