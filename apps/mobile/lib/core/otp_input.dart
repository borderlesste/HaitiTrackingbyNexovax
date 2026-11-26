import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Seis casillas para el código SMS. Un campo invisible recibe el teclado y el autocompletado.
class OtpInput extends StatefulWidget {
  const OtpInput({super.key, required this.controller, this.onCompleted});
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 6; i++)
              Container(
                width: 46,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: i == code.length && _focus.hasFocus ? HtColors.blue : HtColors.border,
                    width: i == code.length && _focus.hasFocus ? 2 : 1.4,
                  ),
                ),
                child: Text(i < code.length ? code[i] : '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                if (v.length == 6) widget.onCompleted?.call(v);
              },
            ),
          ),
        ),
      ]),
    );
  }
}
