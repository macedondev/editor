import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

import '../data/demo_snippets.dart';
import '../data/samples.dart';
import '../data/showcase_metadata.dart';

/// The editor theme choices exposed in the playground theme picker: the four
/// built-in Monaco themes plus one custom theme registered at runtime.
enum PlaygroundTheme {
  dark,
  light,
  hcDark,
  hcLight,
  midnight;

  String get label => switch (this) {
    PlaygroundTheme.dark => 'Dark',
    PlaygroundTheme.light => 'Light',
    PlaygroundTheme.hcDark => 'High Contrast Dark',
    PlaygroundTheme.hcLight => 'High Contrast Light',
    PlaygroundTheme.midnight => 'Midnight (custom)',
  };

  /// The Monaco theme to apply via [MonacoController.setTheme].
  MonacoTheme get monacoTheme => switch (this) {
    PlaygroundTheme.dark => MonacoTheme.vsDark,
    PlaygroundTheme.light => MonacoTheme.vs,
    PlaygroundTheme.hcDark => MonacoTheme.hcBlack,
    PlaygroundTheme.hcLight => MonacoTheme.hcLight,
    PlaygroundTheme.midnight => const MonacoTheme(kMidnightThemeId),
  };

  bool get isDark =>
      this == PlaygroundTheme.dark ||
      this == PlaygroundTheme.hcDark ||
      this == PlaygroundTheme.midnight;
}

/// Holds all page + playground state and brokers every live change to the
/// single shared [MonacoController].
///
/// The owning [MonacoEditor] is created once with [initialEditorOptions] and
/// is never rebuilt with new options/content; instead every change is applied
/// imperatively here, which keeps the editor instance stable.
class ShowcaseController extends ChangeNotifier {
  ShowcaseController({ShowcaseMetadataLoader? metadataLoader})
    : _metadataLoader = metadataLoader ?? ShowcaseMetadataLoader();

  final ShowcaseMetadataLoader _metadataLoader;

  // --- Page state ---
  Brightness _brightness = Brightness.dark;
  Brightness get brightness => _brightness;

  ShowcaseMetadata _metadata = ShowcaseMetadata.fallback;
  ShowcaseMetadata get metadata => _metadata;

  bool _metadataLoading = false;
  bool get metadataLoading => _metadataLoading;

  /// Set by the app so feature cards can scroll the page to the playground.
  VoidCallback? onRequestScrollToPlayground;

  // --- Editor state mirrors ---
  PlaygroundTheme _playgroundTheme = PlaygroundTheme.dark;
  PlaygroundTheme get playgroundTheme => _playgroundTheme;

  MonacoLanguage _language = MonacoLanguage.dart;
  MonacoLanguage get language => _language;

  bool _minimap = false;
  bool get minimap => _minimap;

  bool _wordWrap = true;
  bool get wordWrap => _wordWrap;

  bool _lineNumbers = true;
  bool get lineNumbers => _lineNumbers;

  bool _readOnly = false;
  bool get readOnly => _readOnly;

  double _fontSize = 14;
  double get fontSize => _fontSize;

  String? _hint;
  String? get hint => _hint;

  MonacoController? _editor;
  bool get isEditorReady => _editor != null;

  /// Owner key for the markers demo's diagnostics.
  static const String _demoMarkerOwner = 'showcase-demo';

  /// Decoration set backing the decorations demo; created lazily so demos
  /// can highlight lines without clobbering other decorations.
  MonacoDecorationSet? _demoDecorations;

  /// The underlying Monaco controller, available after [attachEditor].
  /// Used by [MonacoFocusGuard] for web overlay handling.
  MonacoController? get monaco => _editor;

  /// Live editor stats (cursor, line/char counts). Null until the editor is
  /// attached.
  ValueListenable<MonacoLiveStats>? get liveStats => _editor?.stats;

  /// Stable options used to create the editor widget. Computed once.
  late final EditorOptions initialEditorOptions = _buildOptions();

  /// Initial document for the editor widget.
  String get initialValue =>
      sampleFor(MonacoLanguage.dart, metadata: _metadata);

  EditorOptions _buildOptions() => EditorOptions(
    language: _language,
    theme: _playgroundTheme.isDark ? MonacoTheme.vsDark : MonacoTheme.vs,
    fontSize: _fontSize,
    wordWrap: _wordWrap ? MonacoWordWrap.on : MonacoWordWrap.off,
    minimap: MonacoMinimapOptions(enabled: _minimap),
    lineNumbers: _lineNumbers ? MonacoLineNumbers.on : MonacoLineNumbers.off,
    readOnly: _readOnly,
    scrollBeyondLastLine: false,
    padding: const MonacoPadding(top: 16, bottom: 16),
  );

  /// Called from [MonacoEditor.onReady]: registers the custom theme and
  /// completion snippets, then syncs the current theme.
  Future<void> attachEditor(MonacoController controller) async {
    _editor = controller;
    _demoDecorations = null; // Any previous set died with its controller.
    try {
      await controller.defineTheme(kMidnightTheme);
      await controller.registerStaticCompletions(
        id: 'showcase-snippets',
        languages: const ['dart', 'typescript', 'javascript', 'python'],
        triggerCharacters: const ['.'],
        items: kDemoCompletions,
      );
      await controller.setTheme(_playgroundTheme.monacoTheme);
    } catch (e) {
      debugPrint('[ShowcaseController] attachEditor failed: $e');
    }
    notifyListeners();
  }

  Future<void> loadMetadata() async {
    if (_metadataLoading) return;
    _metadataLoading = true;
    notifyListeners();
    try {
      _metadata = await _metadataLoader.load();
      final editor = _editor;
      if (editor != null && _language == MonacoLanguage.json) {
        await editor.document.setText(
          sampleFor(_language, metadata: _metadata),
        );
      }
    } catch (e) {
      debugPrint('[ShowcaseController] metadata load failed: $e');
    } finally {
      _metadataLoading = false;
      notifyListeners();
    }
  }

  // --- Page theme ---

  /// Flips the page brightness and keeps the editor theme in sync (the nav
  /// toggle controls both, per the design).
  void toggleBrightness() {
    _brightness = _brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    _playgroundTheme = _brightness == Brightness.dark
        ? PlaygroundTheme.dark
        : PlaygroundTheme.light;
    _applyTheme();
    notifyListeners();
  }

  // --- Editor theme (playground picker can override the page) ---

  void setPlaygroundTheme(PlaygroundTheme theme) {
    if (theme == _playgroundTheme) return;
    _playgroundTheme = theme;
    _applyTheme();
    notifyListeners();
  }

  void _applyTheme() {
    _editor?.setTheme(_playgroundTheme.monacoTheme);
  }

  // --- Language ---

  Future<void> setLanguage(MonacoLanguage language) async {
    if (language == _language) return;
    _language = language;
    _hint = null;
    notifyListeners();
    final editor = _editor;
    if (editor == null) return;
    await _clearDemoArtifacts(editor);
    await editor.document.setLanguage(language);
    await editor.document.setText(sampleFor(language, metadata: _metadata));
  }

  /// Removes the markers and decorations left behind by the feature demos.
  Future<void> _clearDemoArtifacts(MonacoController editor) async {
    await editor.document.clearMarkers(owner: _demoMarkerOwner);
    await _demoDecorations?.clear();
  }

  // --- Options ---

  void setMinimap(bool value) {
    _minimap = value;
    _applyOptions();
    notifyListeners();
  }

  void setWordWrap(bool value) {
    _wordWrap = value;
    _applyOptions();
    notifyListeners();
  }

  void setLineNumbers(bool value) {
    _lineNumbers = value;
    _applyOptions();
    notifyListeners();
  }

  void setReadOnly(bool value) {
    _readOnly = value;
    _applyOptions();
    notifyListeners();
  }

  void changeFontSize(double delta) {
    final next = (_fontSize + delta).clamp(10.0, 28.0);
    if (next == _fontSize) return;
    _fontSize = next;
    _applyOptions();
    notifyListeners();
  }

  void _applyOptions() {
    _editor?.updateOptions(_buildOptions());
  }

  // --- Quick actions ---

  void format() => _editor?.executeAction(MonacoAction.formatDocument);
  void find() => _editor?.executeAction(MonacoAction.find);
  void foldAll() => _editor?.executeAction(MonacoAction.foldAll);

  Future<String> currentValue() async =>
      await _editor?.document.getText() ?? '';

  Future<void> reset() async {
    final editor = _editor;
    _hint = null;
    notifyListeners();
    if (editor == null) return;
    await _clearDemoArtifacts(editor);
    await editor.document.setLanguage(_language);
    await editor.document.setText(sampleFor(_language, metadata: _metadata));
  }

  /// Scrolls the page to the playground (used by feature-card "Try it" links).
  void scrollToPlayground() => onRequestScrollToPlayground?.call();

  // --- Advanced feature demos (all drive the one editor) ---

  Future<void> runIntelliSenseDemo() async {
    await setLanguage(MonacoLanguage.dart);
    _setHint(
      'Type "pr" then press Ctrl/Cmd + Space to see custom completions.',
    );
  }

  Future<void> runJsonValidationDemo() async {
    final editor = _editor;
    _language = MonacoLanguage.json;
    notifyListeners();
    if (editor == null) return;
    await _demoDecorations?.clear();
    await editor.document.setLanguage(MonacoLanguage.json);
    await editor.document.setText(kInvalidJsonSample);
    await editor.setJsonDiagnostics(kJsonDiagnostics);
    _setHint(
      'Invalid fields are underlined - hover a squiggle for the schema '
      'error.',
    );
  }

  Future<void> runMarkersDemo() async {
    final editor = _editor;
    _language = MonacoLanguage.javascript;
    notifyListeners();
    if (editor == null) return;
    await _demoDecorations?.clear();
    await editor.document.setLanguage(MonacoLanguage.javascript);
    await editor.document.setText(kMarkersDemoCode);
    await editor.document.setMarkers([
      ...kDemoErrorMarkers,
      ...kDemoWarningMarkers,
    ], owner: _demoMarkerOwner);
    _setHint(
      'Error + warning squiggles with overview-ruler ticks - hover to '
      'read each message.',
    );
  }

  Future<void> runDecorationsDemo() async {
    final editor = _editor;
    if (editor == null) return;
    final lineCount = editor.stats.value.lineCount;
    if (lineCount <= 0) return;
    final targets = <int>[
      1,
      if (lineCount >= 3) 3,
      if (lineCount >= 5) 5,
    ].where((line) => line <= lineCount).toList();
    final decorations = _demoDecorations ??= await editor.createDecorationSet();
    await decorations.set([
      for (final line in targets)
        DecorationOptions.line(
          range: Range.lines(line, line),
          className: 'demo-line-highlight',
        ),
    ]);
    _setHint('Lines highlighted with a MonacoDecorationSet + injected CSS.');
  }

  void _setHint(String message) {
    _hint = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _metadataLoader.dispose();
    super.dispose();
  }
}
