/// How the 3D model is scaled to fit within the viewer.
enum ModelFit {
  /// Scale uniformly so the entire model is visible (default).
  /// Analogous to [BoxFit.contain].
  contain,

  /// Scale uniformly so the model fills the viewport.
  /// Parts of the model may be clipped.
  /// Analogous to [BoxFit.cover].
  cover,

  /// Use the model's original scale. No automatic fitting.
  none,
}
