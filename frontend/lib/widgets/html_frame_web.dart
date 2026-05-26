import 'dart:html' as html;

html.IFrameElement? _iframe;
html.DivElement? _overlay;

void showFrame(String content, void Function()? onClose) {
  hideFrame(); // remove any existing

  _overlay = html.DivElement()
    ..style.position = 'absolute'
    ..style.top = '0'
    ..style.left = '0'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.zIndex = '9999'
    ..style.backgroundColor = '#ffffff';

  // Close button — triggers mode switch back to Markdown
  final closeBtn = html.ButtonElement()
    ..text = '✕'
    ..style.position = 'absolute'
    ..style.top = '12px'
    ..style.right = '12px'
    ..style.zIndex = '10000'
    ..style.width = '36px'
    ..style.height = '36px'
    ..style.border = 'none'
    ..style.borderRadius = '50%'
    ..style.backgroundColor = 'rgba(0,0,0,0.6)'
    ..style.color = '#fff'
    ..style.fontSize = '18px'
    ..style.cursor = 'pointer'
    ..style.display = 'flex'
    ..style.alignItems = 'center'
    ..style.justifyContent = 'center'
    ..onClick.listen((_) {
      if (onClose != null) {
        onClose();
      } else {
        hideFrame();
      }
    });

  _iframe = html.IFrameElement()
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..srcdoc = content;

  _overlay!.append(closeBtn);
  _overlay!.append(_iframe!);

  final fv = html.document.querySelector('flutter-view');
  if (fv != null) {
    fv.append(_overlay!);
  } else {
    html.document.body?.append(_overlay!);
  }
}

void hideFrame() {
  _overlay?.remove();
  _overlay = null;
  _iframe = null;
}

void disposeFrame() => hideFrame();
