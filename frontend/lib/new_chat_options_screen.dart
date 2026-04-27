import 'package:flutter/material.dart';

import 'create_chat_screen.dart';
import 'join_chat_screen.dart';

class NewChatOptionsScreen extends StatelessWidget {
  const NewChatOptionsScreen({super.key});

  static Route<bool> route() {
    return MaterialPageRoute<bool>(
      builder: (_) => const NewChatOptionsScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('New Chat')),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        color: theme.scaffoldBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose an option', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 32),
            _OptionButton(
              icon: Icons.add,
              title: 'Create new chat',
              subtitle: 'Start a new conversation',
              onTap: () async {
                final created = await Navigator.of(
                  context,
                ).push<bool>(CreateChatScreen.route());
                if (created == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
            ),
            const SizedBox(height: 16),
            _OptionButton(
              icon: Icons.group_add,
              title: 'Join chat',
              subtitle: 'Join an existing conversation',
              onTap: () async {
                final joined = await Navigator.of(
                  context,
                ).push<bool>(JoinChatScreen.route());
                if (joined == true && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outline.withAlpha(64)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
