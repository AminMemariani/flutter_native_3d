import 'package:flutter/material.dart';
import 'package:flutter_native_3d/flutter_native_3d.dart';

void main() {
  runApp(const Native3DShowcase());
}

// ---------------------------------------------------------------------------
// Model catalog
// ---------------------------------------------------------------------------

class _DemoModel {
  final String name;
  final String subtitle;
  final ModelSource source;
  final bool hasAnimations;
  final IconData icon;

  const _DemoModel({
    required this.name,
    required this.subtitle,
    required this.source,
    this.hasAnimations = false,
    this.icon = Icons.view_in_ar,
  });
}

// Khronos glTF-Sample-Assets: public domain models hosted on GitHub.
// These are the standard test models used by every glTF viewer.
const _kGitHubBase =
    'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models';

final _models = <_DemoModel>[
  const _DemoModel(
    name: 'Local Asset',
    subtitle: 'Bundled .glb file',
    source: ModelSource.asset('assets/model.glb'),
    icon: Icons.folder,
  ),
  _DemoModel(
    name: 'Damaged Helmet',
    subtitle: 'PBR showcase',
    source: ModelSource.network('$_kGitHubBase/DamagedHelmet/glTF-Binary/DamagedHelmet.glb'),
    icon: Icons.shield,
  ),
  _DemoModel(
    name: 'Animated Fox',
    subtitle: '3 animations',
    source: ModelSource.network('$_kGitHubBase/Fox/glTF-Binary/Fox.glb'),
    hasAnimations: true,
    icon: Icons.pets,
  ),
  _DemoModel(
    name: 'Avocado',
    subtitle: 'Small PBR model',
    source: ModelSource.network('$_kGitHubBase/Avocado/glTF-Binary/Avocado.glb'),
    icon: Icons.eco,
  ),
  const _DemoModel(
    name: 'Bad URL (error)',
    subtitle: 'Tests error display',
    source: ModelSource.network('https://example.com/404.glb'),
    icon: Icons.error_outline,
  ),
];

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class Native3DShowcase extends StatelessWidget {
  const Native3DShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Native 3D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const ShowcasePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

class ShowcasePage extends StatefulWidget {
  const ShowcasePage({super.key});

  @override
  State<ShowcasePage> createState() => _ShowcasePageState();
}

class _ShowcasePageState extends State<ShowcasePage> {
  // Scene
  Native3DController? _controller;
  int _selectedModelIndex = 0;
  ModelInfo? _modelInfo;

  // State
  bool _isLoading = true;
  double _loadProgress = 0;
  String? _error;

  // Animation
  String? _playingAnimation;
  bool _isPaused = false;

  // Settings
  SceneLighting _lighting = SceneLighting.studio;
  bool _gesturesEnabled = true;
  bool _autoRotate = false;

  _DemoModel get _currentModel => _models[_selectedModelIndex];

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  void _onSceneCreated(Native3DController controller) {
    _controller = controller;
    controller.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case SceneReadyEvent():
          break;
        case ModelLoadProgressEvent(:final progress):
          setState(() => _loadProgress = progress);
        case AnimationCompletedEvent(:final animationName):
          setState(() {
            _playingAnimation = null;
            _isPaused = false;
          });
          _showSnackBar('$animationName finished');
        case SceneErrorEvent(:final exception):
          _showSnackBar(exception.message);
      }
    });
  }

  void _onModelLoaded(ModelInfo info) {
    setState(() {
      _modelInfo = info;
      _isLoading = false;
      _loadProgress = 0;
      _error = null;
      _playingAnimation = null;
      _isPaused = false;
    });
  }

  void _onModelLoadProgress(double progress) {
    setState(() => _loadProgress = progress);
  }

  void _onError(Native3DException error) {
    setState(() {
      _isLoading = false;
      _loadProgress = 0;
      _error = error.message;
    });
  }

  void _selectModel(int index) {
    if (index == _selectedModelIndex && !_isLoading && _error == null) return;
    setState(() {
      _selectedModelIndex = index;
      _isLoading = true;
      _loadProgress = 0;
      _error = null;
      _modelInfo = null;
      _playingAnimation = null;
      _isPaused = false;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  // ---------------------------------------------------------------------------
  // Animation controls
  // ---------------------------------------------------------------------------

  void _playAnimation(String name) {
    _controller?.playAnimation(name: name);
    setState(() {
      _playingAnimation = name;
      _isPaused = false;
    });
  }

  void _togglePause() {
    if (_isPaused) {
      if (_playingAnimation != null) {
        _controller?.playAnimation(name: _playingAnimation!);
      }
      setState(() => _isPaused = false);
    } else {
      _controller?.pauseAnimation();
      setState(() => _isPaused = true);
    }
  }

  void _stopAnimation() {
    _controller?.stopAnimation();
    setState(() {
      _playingAnimation = null;
      _isPaused = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ---- 3D Viewer ----
            Expanded(child: _buildViewer(cs)),

            // ---- Controls ----
            _buildControlPanel(cs),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3D Viewer
  // ---------------------------------------------------------------------------

  Widget _buildViewer(ColorScheme cs) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dark background
        Container(color: cs.surfaceContainerHighest),

        // 3D view
        Native3DViewer(
          source: _currentModel.source,
          backgroundColor: cs.surfaceContainerHighest,
          lighting: _lighting,
          fitMode: ModelFit.contain,
          gesturesEnabled: _gesturesEnabled,
          autoRotate: _autoRotate,
          autoPlay: _currentModel.hasAnimations,
          onSceneCreated: _onSceneCreated,
          onModelLoaded: _onModelLoaded,
          onModelLoadProgress: _onModelLoadProgress,
          onError: _onError,
        ),

        // Loading overlay
        if (_isLoading)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loadProgress > 0) ...[
                  SizedBox(
                    width: 200,
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _loadProgress,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Downloading ${(_loadProgress * 100).toInt()}%',
                          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                ] else
                  const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  'Loading ${_currentModel.name}...',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),

        // Error overlay
        if (_error != null)
          Center(
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: cs.error),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load model',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _selectModel(_selectedModelIndex),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Top bar (model name + camera reset)
        Positioned(
          top: 8,
          left: 16,
          right: 16,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _currentModel.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: cs.onSurface,
                      ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => _controller?.resetCamera(),
                icon: const Icon(Icons.center_focus_strong, size: 20),
                tooltip: 'Reset camera',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Control panel
  // ---------------------------------------------------------------------------

  Widget _buildControlPanel(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Model picker
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _models.length,
              itemBuilder: (context, index) {
                final model = _models[index];
                final selected = index == _selectedModelIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    avatar: Icon(model.icon, size: 18),
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(model.subtitle, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) => _selectModel(index),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Settings row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Lighting
                _LightingButton(
                  value: _lighting,
                  onChanged: (v) => setState(() => _lighting = v),
                ),
                const SizedBox(width: 8),

                // Gesture toggle
                FilterChip(
                  label: const Text('Orbit'),
                  selected: _gesturesEnabled,
                  onSelected: (v) => setState(() => _gesturesEnabled = v),
                  avatar: Icon(_gesturesEnabled ? Icons.touch_app : Icons.do_not_touch, size: 16),
                ),
                const SizedBox(width: 8),

                // Auto-rotate
                FilterChip(
                  label: const Text('Spin'),
                  selected: _autoRotate,
                  onSelected: (v) => setState(() => _autoRotate = v),
                  avatar: Icon(_autoRotate ? Icons.sync : Icons.sync_disabled, size: 16),
                ),
              ],
            ),
          ),

          // Animation controls (only shown when model has animations)
          if (_modelInfo != null && _modelInfo!.hasAnimations)
            _buildAnimationBar(cs),

          // Bottom safe area padding
          SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 0 : 4),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Animation bar
  // ---------------------------------------------------------------------------

  Widget _buildAnimationBar(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Play/Pause
          if (_playingAnimation != null)
            IconButton(
              icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 20),
              onPressed: _togglePause,
              tooltip: _isPaused ? 'Resume' : 'Pause',
              visualDensity: VisualDensity.compact,
            ),

          // Stop
          if (_playingAnimation != null)
            IconButton(
              icon: const Icon(Icons.stop, size: 20),
              onPressed: _stopAnimation,
              tooltip: 'Stop',
              visualDensity: VisualDensity.compact,
            ),

          if (_playingAnimation != null)
            const SizedBox(width: 4),

          // Animation chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final name in _modelInfo!.animationNames)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(name, style: const TextStyle(fontSize: 12)),
                        onPressed: () => _playAnimation(name),
                        backgroundColor:
                            _playingAnimation == name && !_isPaused
                                ? cs.primaryContainer
                                : null,
                        side: _playingAnimation == name
                            ? BorderSide(color: cs.primary, width: 1.5)
                            : null,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lighting picker popup
// ---------------------------------------------------------------------------

class _LightingButton extends StatelessWidget {
  final SceneLighting value;
  final ValueChanged<SceneLighting> onChanged;

  const _LightingButton({required this.value, required this.onChanged});

  static const _presets = [
    (SceneLighting.studio, 'Studio', Icons.lightbulb),
    (SceneLighting.natural, 'Natural', Icons.wb_sunny),
    (SceneLighting.dramatic, 'Dramatic', Icons.contrast),
    (SceneLighting.neutral, 'Neutral', Icons.light_mode),
    (SceneLighting.unlit, 'Unlit', Icons.dark_mode),
  ];

  String get _label {
    for (final p in _presets) {
      if (p.$1 == value) return p.$2;
    }
    return 'Studio';
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SceneLighting>(
      onSelected: onChanged,
      initialValue: value,
      itemBuilder: (_) => [
        for (final (lighting, label, icon) in _presets)
          PopupMenuItem(
            value: lighting,
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 12),
                Text(label),
              ],
            ),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.lightbulb_outline, size: 16),
        label: Text(_label),
      ),
    );
  }
}
