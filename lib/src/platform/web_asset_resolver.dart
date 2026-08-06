/// Resolves a Flutter Web asset URL to an absolute URL.
///
/// [assetUrl] is the value `ui_web.assetManager.getAssetUrl` returns for a
/// packaged asset: either already absolute (when a CDN `assetBase` is
/// configured through `initializeEngine`) or relative to `<base href>` (the
/// default). [documentBaseUri] must be `web.document.baseURI` - the page's
/// `<base href>` - and not `Uri.base`, which carries the active single-page
/// route under path URL strategy and would nest the asset under that route
/// (see issue #14).
///
/// Resolution follows the same rules the browser applies to every other asset
/// reference, so an absolute [assetUrl] is returned unchanged and a relative
/// one is anchored at the app root.
///
/// **Cross-origin `assetBase` is not supported.** The page's own CSP is no
/// longer the obstacle - it names the origin of each resolved asset root
/// explicitly (see `_cspAssetOrigins` in `html_builder.dart`) - but the asset
/// host must then serve the Monaco bundle and bridge with CORS headers
/// permitting the app's origin, including for the module workers, and that is
/// not something this package can arrange. Serve the Monaco assets from the
/// app's origin; a CDN `assetBase` for the REST of the app is fine as long as
/// the flutter_monaco assets stay same-origin.
String resolveWebAssetUrl(String documentBaseUri, String assetUrl) =>
    Uri.parse(documentBaseUri).resolve(assetUrl).toString();
