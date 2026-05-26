/// Web-only: injects an IFrame into the DOM to render HTML content.
/// Used as a fallback when native WebView is unavailable.
library html_frame;

// Conditional import: dart:html on web, stub on native
import 'html_frame_stub.dart'
    if (dart.library.html) 'html_frame_web.dart'
    as impl;

/// Manages an IFrame overlay for HTML rendering on web.
/// On native platforms, this is a no-op.
class HtmlFrame {
  void Function()? onClose;

  void show(String html) => impl.showFrame(html, onClose);
  void hide() => impl.hideFrame();
  void dispose() => impl.disposeFrame();
}
