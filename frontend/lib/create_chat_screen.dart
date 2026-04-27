import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key});

  static Route<bool> route() {
    return MaterialPageRoute<bool>(builder: (_) => const CreateChatScreen());
  }

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  static const String _aliasKey = 'user_alias';
  static const String _primaryServerKey = 'primary_server';

  final _chatNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isCreating = false;

  @override
  void dispose() {
    _chatNameController.dispose();
    super.dispose();
  }

  Future<void> _createChat() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isCreating) {
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
      _isCreating = true;
    });

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(_roomCreateUri(server))
          .timeout(const Duration(seconds: 10));
      final body = jsonEncode({
        'alias': alias,
        'name': _chatNameController.text.trim(),
      });
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = utf8.encode(body).length;
      request.write(body);

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.internalServerError) {
        throw const _CreateChatException('Server error. Try again later.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const _CreateChatException('Failed to create chat.');
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic> || decoded['id'] == null) {
        throw const FormatException('Unexpected room response.');
      }

      if (!mounted) return;
      navigator.pop(true);
    } on _CreateChatException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to create chat.')),
      );
    } finally {
      client.close(force: true);
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Uri _roomCreateUri(String server) {
    final trimmed = server.trim();
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    return Uri.parse(withScheme).replace(path: '/room/create');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create New Chat')),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        color: theme.scaffoldBackgroundColor,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chat details', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 24),
              TextFormField(
                controller: _chatNameController,
                decoration: InputDecoration(
                  labelText: 'Chat name',
                  hintText: 'Enter chat name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a chat name';
                  }
                  if (value.trim().length < 3) {
                    return 'Chat name must be at least 3 characters';
                  }
                  return null;
                },
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _createChat(),
                enabled: !_isCreating,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _isCreating ? null : _createChat,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isCreating
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Create chat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateChatException implements Exception {
  const _CreateChatException(this.message);

  final String message;
}
