import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'messenger_ws_client.dart';

class ChatMessagesScreen extends StatefulWidget {
  const ChatMessagesScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.invite,
    required this.members,
    required this.lastMessageId,
    required this.color,
  });

  final String roomId;
  final String roomName;
  final String invite;
  final List<String> members;
  final int? lastMessageId;
  final Color color;

  static Route<bool> route({
    required String roomId,
    required String roomName,
    required String invite,
    required List<String> members,
    required int? lastMessageId,
    required Color color,
  }) {
    return MaterialPageRoute<bool>(
      builder: (_) => ChatMessagesScreen(
        roomId: roomId,
        roomName: roomName,
        invite: invite,
        members: members,
        lastMessageId: lastMessageId,
        color: color,
      ),
    );
  }

  @override
  State<ChatMessagesScreen> createState() => _ChatMessagesScreenState();
}

class _ChatMessagesScreenState extends State<ChatMessagesScreen> {
  final TextEditingController _messageController = TextEditingController();
  final MessengerWsClient _wsClient = MessengerWsClient.instance;
  String? _alias;
  bool _requestedInitialMessages = false;

  @override
  void initState() {
    super.initState();
    _wsClient.setRoomMembers(widget.roomId, widget.members);
    unawaited(_wsClient.openRoom(widget.roomId));
    _loadAlias();
    _wsClient.addListener(_requestInitialMessagesIfReady);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestInitialMessagesIfReady();
    });
  }

  @override
  void dispose() {
    _wsClient.removeListener(_requestInitialMessagesIfReady);
    unawaited(_wsClient.closeRoom(widget.roomId));
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadAlias() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _alias = prefs.getString('user_alias');
    });
  }

  void _requestInitialMessagesIfReady() {
    if (_requestedInitialMessages || !_wsClient.isConnected) return;
    final oldestId = _wsClient.oldestMessageIdForRoom(widget.roomId);
    final before = oldestId ?? _initialHistoryBeforeId();
    _requestedInitialMessages = _wsClient.requestOlderMessages(
      roomId: widget.roomId,
      count: 30,
      before: before,
    );
  }

  int? _initialHistoryBeforeId() {
    final lastMessageId = widget.lastMessageId;
    if (lastMessageId == null) return null;
    return lastMessageId + 1;
  }

  Future<void> _openChatInfo() async {
    final members = _wsClient.membersForRoom(
      widget.roomId,
      fallback: widget.members,
    );
    final leftChat = await Navigator.of(context).push<bool>(
      ChatInfoScreen.route(
        roomId: widget.roomId,
        roomName: widget.roomName,
        invite: widget.invite,
        members: members,
        color: widget.color,
      ),
    );
    if (leftChat == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final sent = _wsClient.sendTextMessage(
      roomId: widget.roomId,
      text: message,
    );
    if (sent) {
      _messageController.clear();
      FocusScope.of(context).unfocus();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Connection is not ready.')));
    }
  }

  void _loadOlderMessages() {
    final oldestId = _wsClient.oldestMessageIdForRoom(widget.roomId);
    _wsClient.requestOlderMessages(
      roomId: widget.roomId,
      count: 30,
      before: oldestId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _openChatInfo,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedBuilder(
            animation: _wsClient,
            builder: (context, _) {
              final members = _wsClient.membersForRoom(
                widget.roomId,
                fallback: widget.members,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    _RoomAvatar(
                      name: widget.roomName,
                      color: widget.color,
                      size: 42,
                      radius: 14,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.roomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${members.length} members',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _wsClient,
              builder: (context, _) {
                final messages = _wsClient.messagesForRoom(widget.roomId);
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  itemCount: messages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: TextButton(
                            onPressed: _loadOlderMessages,
                            child: const Text('Load older messages'),
                          ),
                        ),
                      );
                    }

                    final message = messages[messages.length - 1 - index];
                    if (message.isSystem) {
                      return _SystemMessageBubble(message: message);
                    }

                    return _MessageBubble(
                      message: message,
                      isMine: message.sender == _alias,
                    );
                  },
                );
              },
            ),
          ),
          _MessageComposer(
            controller: _messageController,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.invite,
    required this.members,
    required this.color,
  });

  final String roomId;
  final String roomName;
  final String invite;
  final List<String> members;
  final Color color;

  static Route<bool> route({
    required String roomId,
    required String roomName,
    required String invite,
    required List<String> members,
    required Color color,
  }) {
    return MaterialPageRoute<bool>(
      builder: (_) => ChatInfoScreen(
        roomId: roomId,
        roomName: roomName,
        invite: invite,
        members: members,
        color: color,
      ),
    );
  }

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  static const String _aliasKey = 'user_alias';
  static const String _primaryServerKey = 'primary_server';

  final MessengerWsClient _wsClient = MessengerWsClient.instance;
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    _wsClient.setRoomMembers(widget.roomId, widget.members);
  }

  Future<void> _copyInvite() async {
    if (widget.invite.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: widget.invite));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invite code copied.')));
  }

  Future<void> _leaveChat() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (shouldLeave != true || _isLeaving) return;
    if (!mounted) return;

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
      _isLeaving = true;
    });

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(_roomLeaveUri(server))
          .timeout(const Duration(seconds: 10));
      final body = jsonEncode({'alias': alias, 'room_id': widget.roomId});
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = utf8.encode(body).length;
      request.write(body);

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != HttpStatus.ok) {
        throw const _LeaveChatException('Failed to leave chat.');
      }

      if (!mounted) return;
      navigator.pop(true);
    } on _LeaveChatException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to leave chat.')),
      );
    } finally {
      client.close(force: true);
      if (mounted) {
        setState(() {
          _isLeaving = false;
        });
      }
    }
  }

  Uri _roomLeaveUri(String server) {
    final trimmed = server.trim();
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    return Uri.parse(withScheme).replace(path: '/room/leave');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Chat info')),
      body: AnimatedBuilder(
        animation: _wsClient,
        builder: (context, _) {
          final members = _wsClient.membersForRoom(
            widget.roomId,
            fallback: widget.members,
          );
          final isMuted = _wsClient.isRoomMuted(widget.roomId);
          final notificationsEnabled = !isMuted;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Column(
                children: [
                  _RoomAvatar(
                    name: widget.roomName,
                    color: widget.color,
                    size: 92,
                    radius: 28,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.roomName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${members.length} members',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _InfoTile(
                icon: Icons.key_rounded,
                title: 'Invite code',
                trailing: widget.invite.isEmpty
                    ? 'No invite code'
                    : widget.invite,
                onLongPress: _copyInvite,
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: notificationsEnabled,
                onChanged: (value) {
                  unawaited(_wsClient.setRoomMuted(widget.roomId, !value));
                },
                secondary: Icon(
                  notificationsEnabled
                      ? Icons.notifications_rounded
                      : Icons.notifications_off_rounded,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  'Notifications',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  notificationsEnabled
                      ? 'On for this chat'
                      : 'Off for this chat',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                tileColor: theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Members',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              if (members.isEmpty)
                _InfoTile(
                  icon: Icons.group_rounded,
                  title: 'No members',
                  trailing: '',
                )
              else
                ...members.map(
                  (member) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MemberTile(alias: member),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLeaving ? null : _leaveChat,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _isLeaving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Leave chat'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(120),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(hintText: 'Message'),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onSend,
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(
                    Icons.send_rounded,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomAvatar extends StatelessWidget {
  const _RoomAvatar({
    required this.name,
    required this.color,
    required this.size,
    required this.radius,
  });

  final String name;
  final Color color;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(41),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.trailing,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (trailing.isNotEmpty)
                Flexible(
                  child: Text(
                    trailing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaveChatException implements Exception {
  const _LeaveChatException(this.message);

  final String message;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final MessengerMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMine ? theme.colorScheme.primary : theme.cardColor;
    final textColor = isMine
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final metaColor = isMine
        ? theme.colorScheme.onPrimary.withAlpha(180)
        : theme.colorScheme.onSurfaceVariant;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 6),
              bottomRight: Radius.circular(isMine ? 6 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMine) ...[
                Text(
                  message.sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                message.text,
                style: TextStyle(color: textColor, fontSize: 15, height: 1.25),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    color: metaColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemMessageBubble extends StatelessWidget {
  const _SystemMessageBubble({required this.message});

  final MessengerMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(190),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          message.displayText,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _formatTime(DateTime timestamp) {
  final local = timestamp.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.alias});

  final String alias;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = alias.trim().isEmpty ? '?' : alias.trim().characters.first;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primary.withAlpha(35),
            foregroundColor: theme.colorScheme.primary,
            child: Text(
              initial,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              alias,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
