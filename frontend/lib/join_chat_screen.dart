import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JoinChatScreen extends StatefulWidget {
  const JoinChatScreen({super.key});

  static Route<bool> route() {
    return MaterialPageRoute<bool>(builder: (_) => const JoinChatScreen());
  }

  @override
  State<JoinChatScreen> createState() => _JoinChatScreenState();
}

class _JoinChatScreenState extends State<JoinChatScreen> {
  static const String _aliasKey = 'user_alias';
  static const String _primaryServerKey = 'primary_server';

  final _inviteCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isJoining = false;

  @override
  void dispose() {
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _joinChat() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isJoining) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final prefs = await SharedPreferences.getInstance();
    final alias = prefs.getString(_aliasKey);
    final server = prefs.getString(_primaryServerKey);

    if (alias == null || alias.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Alias is not configured.')),
      );
      return;
    }

    if (server == null || server.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Select a server in settings.')),
      );
      return;
    }

    setState(() {
      _isJoining = true;
    });

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(_roomJoinUri(server))
          .timeout(const Duration(seconds: 10));
      final body = jsonEncode({
        'alias': alias,
        'invite': _inviteCodeController.text.trim().toUpperCase(),
      });
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = utf8.encode(body).length;
      request.write(body);

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.notFound) {
        throw const _JoinChatException('Room not found.');
      }
      if (response.statusCode == HttpStatus.conflict) {
        throw _JoinChatException(_errorMessageFrom(responseBody));
      }
      if (response.statusCode == HttpStatus.internalServerError) {
        throw const _JoinChatException('Server error. Try again later.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const _JoinChatException('Failed to join chat.');
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic> || decoded['id'] == null) {
        throw const FormatException('Unexpected room response.');
      }

      if (!mounted) return;
      navigator.pop(true);
    } on _JoinChatException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to join chat.')),
      );
    } finally {
      client.close(force: true);
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  Uri _roomJoinUri(String server) {
    final trimmed = server.trim();
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    return Uri.parse(withScheme).replace(path: '/room/join');
  }

  static String _errorMessageFrom(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
      }
    } catch (_) {
      // The status code is enough if the body is not JSON.
    }
    return 'Failed to join chat.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Join Chat')),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        color: theme.scaffoldBackgroundColor,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter invite code', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 16),
              Text(
                'Ask the chat creator for the invite code to join their conversation.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _inviteCodeController,
                enabled: !_isJoining,
                decoration: InputDecoration(
                  labelText: 'Invite code',
                  hintText: 'Enter invite code',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an invite code';
                  }
                  if (value.trim().length < 6) {
                    return 'Invite code must be at least 6 characters';
                  }
                  return null;
                },
                inputFormatters: const [_UpperCaseTextFormatter()],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _joinChat(),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _isJoining ? null : _joinChat,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isJoining
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Join chat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _JoinChatException implements Exception {
  const _JoinChatException(this.message);

  final String message;
}
