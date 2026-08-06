import 'dart:convert';

/// Characters that would let a source expression escape the policy attribute
/// or smuggle in an additional directive.
final RegExp _unsafeCspSourceChars = RegExp(r'''[\s;'"<>]''');

/// Whether [source] may be spliced into the page's CSP.
///
/// The single definition of what is admissible, applied to every source
/// expression that reaches the policy - both caller-supplied
/// ([sanitizeConnectSources]) and derived from asset URLs ([_cspAssetOrigins]).
bool _isSafeCspSource(String source) =>
    source.isNotEmpty && !_unsafeCspSourceChars.hasMatch(source);

/// Validates extra CSP `connect-src` source expressions.
///
/// Returns the non-empty entries, ready to append to the `connect-src`
/// directive. Throws [ArgumentError] for entries that could break out of the
/// policy attribute or smuggle in additional directives (whitespace, quotes,
/// `;`, `<`, `>`).
List<String> sanitizeConnectSources(List<String> sources) {
  final cleaned = <String>[];
  for (final raw in sources) {
    final source = raw.trim();
    if (source.isEmpty) continue;
    if (!_isSafeCspSource(source)) {
      throw ArgumentError.value(
        raw,
        'allowedConnectSources',
        'Each entry must be a single CSP source expression without '
            'whitespace, quotes, or ";" (e.g. "wss://lsp.example.com")',
      );
    }
    cleaned.add(source);
  }
  return cleaned;
}

/// CSP host-sources for every origin the generated page fetches from.
///
/// The policy must never depend on `'self'`. This document is always
/// delivered over a local scheme - a `blob:` URL on web (see
/// `webview_web.dart`) and a `file:` URL on native (see
/// `webview_native.dart`) - and `'self'` is not dependable there: Firefox
/// does not resolve it to the creating document's origin inside a `blob:`
/// document, so every same-origin fetch the page makes (`loader.js`, the
/// bridge scripts, `editor.main.css`, the workers) is blocked while Chrome
/// allows it. Native has always handled this by naming `file:` in every
/// directive; web names the origins it actually references.
///
/// Only absolute http(s) URLs carry an origin, so native's relative and
/// `file:` asset paths contribute nothing and leave the policy unchanged.
/// [Uri.origin] rather than `authority` is deliberate: it is
/// `scheme://host[:port]` with no userinfo, which is the only form valid as a
/// CSP host-source - `authority` would emit `https://user:pass@host`, an
/// expression browsers discard, silently restoring the failure.
List<String> _cspAssetOrigins(List<String> assetUrls) {
  final origins = <String>{};
  for (final url in assetUrls) {
    final uri = Uri.tryParse(url);
    if (uri == null) continue;
    if (uri.scheme != 'http' && uri.scheme != 'https') continue;
    if (uri.host.isEmpty) continue;
    final origin = uri.origin;
    if (_isSafeCspSource(origin)) origins.add(origin);
  }
  return origins.toList()..sort();
}

/// Neutralizes `</` sequences so injected CSS can never terminate its
/// `<style>` element early (an embedded `</style>` would promote the rest
/// of the block to markup, i.e. script injection). `\/` is a valid CSS
/// escape for `/`, so legitimate CSS - including content strings such as
/// `"</b>"` - keeps its meaning.
String _escapeStyleText(String css) => css.replaceAll('</', r'<\/');

/// The bridge JavaScript files referenced by the generated page, in load
/// order. `boot.js` must stay last: it runs the installers the other files
/// define. `viewport-fit.js` is only emitted on web.
const List<String> monacoBridgeScripts = [
  'core.js',
  'focus.js',
  'editor-api.js',
  'diff-api.js',
  'scroll-handoff.js',
  'lsp.js',
  // 'viewport-fit.js' (web only, inserted by the builder)
  'boot.js',
];

/// Builds the HTML document that hosts the Monaco Editor.
///
/// The page contains only platform shims and `<script src>` references; the
/// bridge logic lives in real JavaScript files under `assets/monaco/bridge/`
/// (see upcoming/v3.md Section 6.7). [bridgeBase] is the URL prefix for those
/// files, without a trailing slash: relative (`bridge`) on Android/iOS/macOS,
/// an absolute `file://` directory URL on Windows, and a resolved asset URL
/// on web.
///
/// [monacoVersion] is stamped into `window.__FM_PAGE` for the protocol
/// handshake.
/// [vsPath] is the path to the Monaco `vs/` directory (platform-specific,
/// same semantics as 2.3.0). [messageToken] is the web postMessage
/// authentication token. [customCss] is injected into a `<style>` tag.
/// [allowCdnFonts] relaxes CSP for `https:` styles/fonts.
/// [allowedConnectSources] extends the CSP `connect-src` list and is
/// validated by [sanitizeConnectSources].
String buildMonacoIndexHtml({
  required String vsPath,
  required String bridgeBase,
  required String monacoVersion,
  bool isWindows = false,
  bool isIosOrMacOS = false,
  bool isWeb = false,
  String? messageToken,
  String? customCss,
  bool allowCdnFonts = false,
  List<String> allowedConnectSources = const [],
}) {
  final extraConnectSources = sanitizeConnectSources(allowedConnectSources);

  // The page's whole fetch surface, named explicitly so nothing load-bearing
  // depends on 'self' (see _cspAssetOrigins). Both asset roots contribute:
  // the Monaco bundle and the bridge scripts are resolved by separate
  // functions on web and are same-origin only by convention, so deriving the
  // policy from one of them would leave the other unadmitted.
  final selfSources = <String>[
    "'self'",
    ..._cspAssetOrigins([vsPath, bridgeBase]),
  ];

  // Every directive is emitted through here, so one added later cannot
  // silently omit the asset origins. `default-src` is no safety net for
  // that: it only backstops directives that are NOT declared.
  String directive(String name, List<String> extra) =>
      '$name ${[...selfSources, ...extra].join(' ')}';

  final contentSecurityPolicy =
      '${[
        directive('default-src', ['file:', "'unsafe-inline'", "'unsafe-eval'"]),
        directive('script-src', ['file:', "'unsafe-inline'", "'unsafe-eval'"]),
        directive('style-src', ["'unsafe-inline'", if (allowCdnFonts) 'https:']),
        directive('font-src', ['file:', 'data:', if (allowCdnFonts) 'https:']),
        directive('img-src', ['data:', 'blob:', 'file:']),
        directive('worker-src', ['blob:']),
        directive('connect-src', ['blob:', ...extraConnectSources]),
      ].join('; ')};';

  final platform = isWeb
      ? 'web'
      : isWindows
      ? 'windows'
      : isIosOrMacOS
      ? 'apple'
      : 'other';

  // Page facts the external bridge files read instead of having values
  // interpolated into their source (which must stay static assets).
  final pageConfig =
      '''
<script>
  window.__FM_PAGE = {
    platform: ${jsonEncode(platform)},
    vsPath: ${jsonEncode(vsPath)},
    monacoVersion: ${jsonEncode(monacoVersion)},
    token: ${messageToken == null ? 'null' : jsonEncode(messageToken)}
  };
</script>
''';

  // Platform-specific initialization scripts (channel shims + worker shims).
  // VERBATIM PORT from 2.3.0 generateIndexHtml; these must run before any
  // external script loads, so they stay inline in the head.
  String platformScript;

  if (isWeb) {
    platformScript =
        '''
<script>
  console.log('[Web Init] Setting up for iframe mode');
  self.MonacoEnvironment = {
    baseUrl: '$vsPath/../',
    getWorkerUrl: function(moduleId, label) {
      var workerSrc = "self.MonacoEnvironment = { baseUrl: '$vsPath/../' }; importScripts('$vsPath/base/worker/workerMain.js');";
      return URL.createObjectURL(new Blob([workerSrc], { type: 'application/javascript' }));
    }
  };
  window.flutterChannel = {
    postMessage: function(msg) {
      window.parent.postMessage(msg, '*');
    }
  };
  window.flutterMonacoToken = ${jsonEncode(messageToken ?? '')};
  window.flutterMonacoPostMessage = function(message) {
    var token = window.flutterMonacoToken;
    if (typeof message !== 'string') {
      if (token && message && typeof message === 'object') {
        message._flutterToken = token;
      }
      message = JSON.stringify(message);
    } else {
      try {
        var parsed = JSON.parse(message);
        if (parsed && typeof parsed === 'object') {
          if (token) parsed._flutterToken = token;
          message = JSON.stringify(parsed);
        }
      } catch (_) {}
    }
    if (window.flutterChannel && window.flutterChannel.postMessage) {
      window.flutterChannel.postMessage(message);
    }
  };
  console.log('[Web Init] flutterChannel created successfully');
</script>
''';
  } else if (isWindows) {
    platformScript = '''
<script>
  // Windows: Create flutterChannel immediately when document is created
  console.log('[Windows Init] Creating flutterChannel on document creation');
  window.flutterChannel = {
    postMessage: function(msg) {
      if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(msg);
      } else {
        console.error('[flutterChannel] WebView2 API not available!');
      }
    }
  };
  console.log('[Windows Init] flutterChannel created successfully');
</script>
''';
  } else if (isIosOrMacOS) {
    // iOS and macOS need blob worker shim for WKWebView + file:// protocol
    platformScript =
        '''
<script>
  (function () {
    console.log('[Init] Setting up worker shim for WKWebView');
    const vsRel = '$vsPath'; // e.g., "min/vs"
    let absVs;
    try { absVs = new URL(vsRel, window.location.href).toString(); }
    catch (_) { absVs = vsRel; }

    // Ensure baseUrl points to the ".../min/" folder (not ".../min/vs")
    const idx = absVs.lastIndexOf('/vs');
    const baseUrl = idx >= 0 ? absVs.substring(0, idx + 1) : absVs; // e.g., ".../min/"

    // Set baseUrl so Monaco can resolve URLs before workers start
    self.MonacoEnvironment = {
      baseUrl: baseUrl,
      getWorkerUrl: function (moduleId, label) {
        // Include the label for better worker resolution and debugging.
        // This template is a cooked Dart string: the newline escapes must be
        // written as \\n so JavaScript receives "\\n" and not a raw newline,
        // which is a SyntaxError inside a JS string literal and would kill
        // this whole script block (workers then fall back to the main thread).
        const src =
          "self.MonacoEnvironment = { baseUrl: '" + baseUrl + "' };\\n" +
          "self.monacoLabel = '" + label + "';\\n" +
          "importScripts('" + absVs + "/base/worker/workerMain.js');\\n";
        return URL.createObjectURL(new Blob([src], { type: 'application/javascript' }));
      }
    };
    console.log('[Init] Worker shim configured. baseUrl=' + baseUrl);
  })();
</script>
''';
  } else {
    // Android and other platforms: just set baseUrl
    final baseUrl = vsPath.replaceAll('/vs', '/');
    platformScript =
        '''
<script>
  // Linux/Other: Set base URL for worker resolution
  console.log('[Init] Setting Monaco base URL');
  self.MonacoEnvironment = { baseUrl: '$baseUrl' };
</script>
''';
  }

  final bridgeScriptNames = [
    ...monacoBridgeScripts.sublist(0, monacoBridgeScripts.length - 1),
    if (isWeb) 'viewport-fit.js',
    monacoBridgeScripts.last,
  ];
  final bridgeScriptTags = bridgeScriptNames
      .map((name) => '    <script src="$bridgeBase/$name"></script>')
      .join('\n');

  return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta http-equiv="X-UA-Compatible" content="IE=edge" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
    <meta
      http-equiv="Content-Security-Policy"
      content="$contentSecurityPolicy"
    />
    <!-- NOTE: connect-src intentionally limits in-page requests to this
         page's own asset origins and blob:. Opt into remote endpoints (e.g.
         WebSocket language servers) via the allowedConnectSources parameter
         instead of editing this policy. -->
    <script>
      // A CSP block is this page's most likely load failure: it is served
      // over a local scheme and fetches everything else from the app origin.
      // Unrecorded, it surfaces only as "Failed to load Monaco loader.js",
      // which names neither the directive that refused nor the URL it
      // refused - the difference between a one-line report and a
      // cross-browser hunt. Must precede every governed load.
      window.__FM_CSP_VIOLATIONS = [];
      document.addEventListener('securitypolicyviolation', function (e) {
        if (window.__FM_CSP_VIOLATIONS.length >= 5) return;
        window.__FM_CSP_VIOLATIONS.push(
          (e.effectiveDirective || e.violatedDirective) + ' blocked ' + e.blockedURI
        );
      });
      window.__fmCspDetail = function () {
        var v = window.__FM_CSP_VIOLATIONS;
        return v && v.length ? ' (CSP: ' + v.join('; ') + ')' : '';
      };
    </script>
    <style>
      html, body, #editor-container {
        width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden;
      }
      ${isWeb ? '''
      /* Scroll containment for the iframe embed (issue #11). Monaco only
         preventDefault()s touches that start on its text surface or
         scrollbar sliders; touches that start on the margin, a scrollbar
         track, or before Monaco loads fall through to the browser's native
         pan. Nothing in this document can scroll, so mobile Safari chains
         that pan to the host Flutter page. Declaring the policy here removes
         the native pan for every touch in this document; Monaco's own touch
         scrolling is JS-driven and unaffected by touch-action. */
      html, body, #editor-container {
        touch-action: none;
        overscroll-behavior: none;
      }''' : ''}
    </style>
    ${customCss != null ? '<style id="flutter-monaco-custom">\n${_escapeStyleText(customCss)}\n</style>' : ''}
    $pageConfig
    $platformScript
  </head>
  <body>
    <div id="editor-container"></div>

    <script>
      var require = { paths: { vs: '$vsPath' } };
      console.log('[Monaco HTML] Require config set. VS_PATH is: ' + '$vsPath');
    </script>

    ${isWeb ? '''
    <script>
      // Web: Load loader.js dynamically to ensure proper timing in blob URL context
      var loaderScript = document.createElement('script');
      loaderScript.src = '$vsPath/loader.js';
      loaderScript.onload = function() {
        console.log('[Monaco HTML] loader.js dynamically loaded.');
        window._monacoLoaderReady = true;
        if (window._initMonacoWhenReady) window._initMonacoWhenReady();
      };
      loaderScript.onerror = function() {
        // This error event and securitypolicyviolation are dispatched
        // independently, so yield once: a CSP block is then already recorded
        // when the report is built. The host is waiting on a 20s readiness
        // timeout, so one task is free.
        setTimeout(function () {
          var detail = window.__fmCspDetail ? window.__fmCspDetail() : '';
          console.error('[Monaco HTML] FATAL: loader.js FAILED TO LOAD.' + detail);
          var payload = { event: 'error', message: 'Failed to load Monaco loader.js' + detail };
          if (window.flutterMonacoPostMessage) {
            window.flutterMonacoPostMessage(payload);
          } else if (window.flutterChannel) {
            window.flutterChannel.postMessage(JSON.stringify(payload));
          }
        }, 0);
      };
      document.head.appendChild(loaderScript);
    </script>
    ''' : '''
    <script src="$vsPath/loader.js"
            onload="console.log('[Monaco HTML] loader.js successfully loaded.')"
            onerror="console.error('[Monaco HTML] FATAL: loader.js FAILED TO LOAD.' + (window.__fmCspDetail ? window.__fmCspDetail() : ''))"
    ></script>
    '''}

$bridgeScriptTags
  </body>
</html>
''';
}
