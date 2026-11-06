import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';

/// Android's keyboard back button can hide the IME without clearing focus.
/// Release the focused field when that transition finishes, including forms
/// on pushed routes. Merely resizing a window never clears focus.
class KeyboardFocusDismissal extends StatefulWidget {
  const KeyboardFocusDismissal({super.key, required this.child});
  final Widget child;

  @override
  State<KeyboardFocusDismissal> createState() => _KeyboardFocusDismissalState();
}

class _KeyboardFocusDismissalState extends State<KeyboardFocusDismissal>
    with WidgetsBindingObserver {
  FlutterView? _view;
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.of(context);
    _keyboardVisible = _view!.viewInsets.bottom > 0;
  }

  @override
  void didChangeMetrics() {
    final visible = (_view?.viewInsets.bottom ?? 0) > 0;
    if (_keyboardVisible && !visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _view?.viewInsets.bottom == 0) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      });
    }
    _keyboardVisible = visible;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: widget.child,
  );
}
