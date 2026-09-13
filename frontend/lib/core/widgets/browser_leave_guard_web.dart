import 'dart:js_interop';

import 'package:web/web.dart' as web;

void Function() listenBeforeUnload() {
  final listener = ((web.Event event) => event.preventDefault()).toJS;
  web.window.addEventListener('beforeunload', listener);
  return () => web.window.removeEventListener('beforeunload', listener);
}
