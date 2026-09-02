library;

// Core exports
export 'src/common/defaults.dart' show MonacoDefaults, MonacoFontStacks;
export 'src/common/exceptions.dart'
    show
        MonacoDisposedError,
        MonacoException,
        MonacoJavaScriptError,
        MonacoPageReloadedError,
        MonacoProtocolError,
        MonacoTimeoutError;
export 'src/assets/asset_diagnostics.dart' show MonacoAssetDiagnostics;
export 'src/assets/monaco_assets.dart' show MonacoAssets;
export 'src/editor/controller.dart' show MonacoController;
export 'src/common/monaco_page_config.dart'
    show MonacoCapabilities, MonacoPageConfig;
export 'src/diff/diff_controller.dart' show MonacoDiffController;
export 'src/diff/diff_options.dart' show MonacoDiffOptions;
export 'src/editor/completions.dart'
    show CompletionProvider, MonacoCompletionRegistration;
export 'src/editor/inline_completions.dart'
    show InlineCompletionProvider, MonacoInlineCompletionRegistration;
export 'src/editor/custom_actions.dart' show MonacoActionRegistration;
export 'src/editor/decorations.dart' show MonacoDecorationSet;
export 'src/editor/document.dart' show MonacoDocument;
export 'src/editor/events.dart'
    show
        MonacoContentChanged,
        MonacoEvent,
        MonacoFocusChanged,
        MonacoScrollHandoffEvent,
        MonacoSelectionChanged,
        MonacoUnknownEvent;
export 'src/editor/focus_coordinator.dart' show MonacoFocusIntent;
export 'src/editor/view_state.dart' show MonacoViewState;

// LSP exports
export 'src/lsp/lsp_connection.dart' show LanguageServerConnection;
export 'src/lsp/lsp_server_process.dart' show LspServerProcess;
export 'src/lsp/lsp_stdio_framing.dart'
    show LspStdioMessageDecoder, LspStdioMessageEncoder;
export 'src/lsp/lsp_transport.dart'
    show
        LspBridgedTransport,
        LspCustomTransport,
        LspTransport,
        LspTransportKind,
        LspWebSocketTransport;
export 'src/lsp/lsp_types.dart'
    show LspConnectionState, LspConnectionStatus, LspReconnectPolicy;

// Options exports
export 'src/options/action.dart' show MonacoAction;
export 'src/options/editor_options.dart' show EditorOptions;
export 'src/options/language.dart' show MonacoLanguage;
export 'src/options/option_enums.dart'
    show
        AutoClosingBehavior,
        CursorBlinking,
        CursorStyle,
        DiagnosticsSeverity,
        MonacoBaseTheme,
        MonacoFoldingControls,
        MonacoLineHighlight,
        MonacoLineNumbers,
        MonacoMinimapSide,
        MonacoScrollbarVisibility,
        MonacoWordWrap,
        RenderWhitespace;
export 'src/options/sub_options.dart'
    show
        MonacoGuidesOptions,
        MonacoMinimapOptions,
        MonacoPadding,
        MonacoScrollbarOptions,
        MonacoStickyScroll;
export 'src/options/theme.dart' show MonacoTheme;
export 'src/options/theme_definition.dart'
    show MonacoThemeDefinition, MonacoThemeRule;

// Type exports
export 'src/types/completion.dart'
    show
        CompletionItem,
        CompletionItemKind,
        CompletionList,
        CompletionRequest,
        InsertTextRule;
export 'src/types/inline_completion.dart'
    show
        InlineCompletionContext,
        InlineCompletionItem,
        InlineCompletionList,
        InlineCompletionRequest,
        InlineCompletionTriggerKind;
export 'src/types/decorations.dart' show DecorationOptions;
export 'src/types/geometry.dart' show Position, Range;
export 'src/types/json_diagnostics.dart'
    show JsonDiagnosticsOptions, JsonDiagnosticsSchema;
export 'src/types/keybinding.dart'
    show MonacoActionDescriptor, MonacoKey, MonacoKeybinding;
export 'src/types/markers.dart'
    show MarkerData, MarkerSeverity, RelatedInformation;
export 'src/types/scroll_handoff.dart'
    show
        MonacoScrollBoundaryPolicy,
        MonacoScrollHandoff,
        MonacoScrollHandoffDetails,
        MonacoScrollHandoffMode,
        MonacoScrollHandoffPhase,
        MonacoScrollHandoffSource;
export 'src/types/stats.dart' show EditorState, MonacoLiveStats;
export 'src/types/text.dart'
    show EditOperation, FindMatch, FindOptions, MonacoTextChange;

// Widget exports
export 'src/widgets/monaco_diff_editor.dart' show MonacoDiffEditor;
export 'src/widgets/monaco_editor_view.dart' show MonacoEditor;
export 'src/widgets/monaco_focus_guard.dart' show MonacoFocusGuard;
export 'src/widgets/monaco_overlay_boundary.dart' show MonacoOverlayBoundary;
export 'src/widgets/monaco_route_observer.dart' show MonacoRouteObserver;
export 'src/widgets/monaco_scaffold.dart' show MonacoScaffold;
export 'src/widgets/monaco_editor_theme.dart'
    show MonacoEditorTheme, MonacoEditorThemeData;
