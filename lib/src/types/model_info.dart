/// Metadata about a successfully loaded 3D model.
class ModelInfo {
  /// Names of all animations in the model. Empty if the model has no animations.
  final List<String> animationNames;

  const ModelInfo({required this.animationNames});

  /// Whether this model contains any animations.
  bool get hasAnimations => animationNames.isNotEmpty;

  /// Number of animations in the model.
  int get animationCount => animationNames.length;
}
