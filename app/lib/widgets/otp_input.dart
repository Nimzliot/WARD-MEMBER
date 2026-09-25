import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Six OTP boxes backed by one invisible TextField, so typing, backspace,
/// paste and SMS autofill all just work.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.enabled = true,
    this.hasError = false,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool hasError;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, _focus]),
      builder: (context, _) {
        final text = widget.controller.text;
        return SizedBox(
          height: 60,
          child: Stack(
            children: [
              Row(
                children: List.generate(widget.length, (i) {
                  final isCurrent = _focus.hasFocus &&
                      (i == text.length || (i == widget.length - 1 && text.length == widget.length));
                  final filled = i < text.length;
                  final borderColor = widget.hasError
                      ? scheme.error
                      : isCurrent
                          ? AppColors.forest
                          : filled
                              ? AppColors.leaf
                              : AppColors.mintLine;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: filled ? AppColors.mint : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor, width: isCurrent ? 2 : 1.5),
                        boxShadow: isCurrent
                            ? [BoxShadow(color: AppColors.forest.withValues(alpha: 0.15), blurRadius: 10)]
                            : null,
                      ),
                      child: Text(
                        filled ? text[i] : '',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forestDark),
                      ),
                    ),
                  );
                }),
              ),
              // Invisible input on top receives taps and keystrokes.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: true,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(widget.length),
                    ],
                    decoration: const InputDecoration(border: InputBorder.none, filled: false),
                    onChanged: (v) {
                      if (v.length == widget.length) widget.onCompleted?.call(v);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Resend code in 0:42" → "Resend code" button.
/// [onResend] returns the seconds to wait before the next resend, or null if
/// sending failed (the button stays available).
class ResendTimer extends StatefulWidget {
  const ResendTimer({super.key, required this.onResend, this.initialSeconds = 60});

  final Future<int?> Function() onResend;
  final int initialSeconds;

  @override
  State<ResendTimer> createState() => _ResendTimerState();
}

class _ResendTimerState extends State<ResendTimer> {
  Timer? _timer;
  int _left = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start(widget.initialSeconds);
  }

  void _start(int seconds) {
    _timer?.cancel();
    _left = seconds;
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    final wait = await widget.onResend();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (wait != null) _start(wait);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_left > 0) {
      final m = _left ~/ 60, s = (_left % 60).toString().padLeft(2, '0');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Resend code in $m:$s',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return TextButton.icon(
      onPressed: _busy ? null : _resend,
      icon: const Icon(Icons.refresh),
      label: Text(_busy ? 'Sending…' : 'Resend code'),
    );
  }
}
