/*
 * Copyright (C) 2022 Yubico.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/logging.dart';
import '../../app/message.dart';
import '../../app/models.dart';
import '../../desktop/models.dart';
import '../../widgets/responsive_dialog.dart';
import '../models.dart';
import '../state.dart';

final _log = Logger('fido.views.pin_dialog');

class FidoPinDialog extends ConsumerStatefulWidget {
  final DevicePath devicePath;
  final FidoState state;
  const FidoPinDialog(this.devicePath, this.state, {super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _FidoPinDialogState();
}

class _FidoPinDialogState extends ConsumerState<FidoPinDialog> {
  String _currentPin = '';
  String _newPin = '';
  String _confirmPin = '';
  String? _currentPinError;
  String? _newPinError;
  bool _currentIsWrong = false;
  bool _newIsWrong = false;

  @override
  Widget build(BuildContext context) {
    final hasPin = widget.state.hasPin;
    final isValid = _newPin.isNotEmpty &&
        _newPin == _confirmPin &&
        (!hasPin || _currentPin.isNotEmpty);
    final minPinLength = widget.state.minPinLength;

    return ResponsiveDialog(
      title: Text(hasPin
          ? AppLocalizations.of(context)!.fido_change_pin
          : AppLocalizations.of(context)!.fido_set_pin),
      actions: [
        TextButton(
          onPressed: isValid ? _submit : null,
          child: Text(AppLocalizations.of(context)!.fido_save),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPin) ...[
              Text(AppLocalizations.of(context)!.fido_enter_current_pin),
              TextFormField(
                initialValue: _currentPin,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: AppLocalizations.of(context)!.fido_current_pin,
                  errorText: _currentIsWrong ? _currentPinError : null,
                  errorMaxLines: 3,
                  prefixIcon: const Icon(Icons.pin_outlined),
                ),
                onChanged: (value) {
                  setState(() {
                    _currentIsWrong = false;
                    _currentPin = value;
                  });
                },
              ),
            ],
            Text(
                AppLocalizations.of(context)!.fido_enter_new_pin(minPinLength)),
            // TODO: Set max characters based on UTF-8 bytes
            TextFormField(
              initialValue: _newPin,
              autofocus: !hasPin,
              obscureText: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: AppLocalizations.of(context)!.fido_new_pin,
                enabled: !hasPin || _currentPin.isNotEmpty,
                errorText: _newIsWrong ? _newPinError : null,
                errorMaxLines: 3,
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
              onChanged: (value) {
                setState(() {
                  _newIsWrong = false;
                  _newPin = value;
                });
              },
            ),
            TextFormField(
              initialValue: _confirmPin,
              obscureText: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: AppLocalizations.of(context)!.fido_confirm_pin,
                prefixIcon: const Icon(Icons.pin_outlined),
                enabled:
                    (!hasPin || _currentPin.isNotEmpty) && _newPin.isNotEmpty,
              ),
              onChanged: (value) {
                setState(() {
                  _confirmPin = value;
                });
              },
              onFieldSubmitted: (_) {
                if (isValid) {
                  _submit();
                }
              },
            ),
          ]
              .map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: e,
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _submit() async {
    final minPinLength = widget.state.minPinLength;
    final oldPin = _currentPin.isNotEmpty ? _currentPin : null;
    if (_newPin.length < minPinLength) {
      setState(() {
        _newPinError =
            AppLocalizations.of(context)!.fido_new_pin_chars(minPinLength);
        _newIsWrong = true;
      });
      return;
    }
    try {
      final result = await ref
          .read(fidoStateProvider(widget.devicePath).notifier)
          .setPin(_newPin, oldPin: oldPin);
      result.when(success: () {
        Navigator.of(context).pop(true);
        showMessage(context, AppLocalizations.of(context)!.fido_pin_set);
      }, failed: (retries, authBlocked) {
        setState(() {
          if (authBlocked) {
            _currentPinError = AppLocalizations.of(context)!.fido_pin_blocked;
            _currentIsWrong = true;
          } else {
            _currentPinError = AppLocalizations.of(context)!
                .fido_wrong_pin_retries_remaining(retries);
            _currentIsWrong = true;
          }
        });
      });
    } catch (e) {
      _log.error('Failed to set PIN', e);
      final String errorMessage;
      // TODO: Make this cleaner than importing desktop specific RpcError.
      if (e is RpcError) {
        errorMessage = e.message;
      } else {
        errorMessage = e.toString();
      }
      showMessage(
        context,
        '${AppLocalizations.of(context)!.fido_fail_set_pin}: $errorMessage',
        duration: const Duration(seconds: 4),
      );
    }
  }
}
