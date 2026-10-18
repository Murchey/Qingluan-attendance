import 'package:flutter/services.dart';

const _channel = MethodChannel('qingluan/keyboard');

/// Ask Android to show the IME for the focused field.
///
/// Android suppresses the soft keyboard when it reports a hardware keyboard
/// and the “show virtual keyboard” setting is off. That state is common on
/// phones that expose built-in keypads as keyboards, and it left bottom input
/// panels focused but untypeable. The platform handler uses SHOW_FORCED, which
/// ignores the hardware-keyboard state. Other platforms and widget tests have
/// no handler, so a missing plugin is expected and harmless.
Future<void> showSoftKeyboard() async {
  try {
    await _channel.invokeMethod<void>('show');
  } on MissingPluginException {
    // Desktop, iOS and widget tests.
  } on PlatformException {
    // The IME is unavailable; the field can still receive hardware input.
  }
}
