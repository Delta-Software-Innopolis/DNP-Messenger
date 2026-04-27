import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appearance_screen.dart';
import 'chat_messages_screen.dart';
import 'messenger_ws_client.dart';
import 'new_chat_options_screen.dart';
import 'notification_service.dart';
import 'server_list_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    required this.themeModeNotifier,
    required this.onThemeModeChanged,
  });

  final ValueNotifier<ThemeMode> themeModeNotifier;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();

  static Route<void> route({
    required ValueNotifier<ThemeMode> themeModeNotifier,
    required ValueChanged<ThemeMode> onThemeModeChanged,
  }) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 650),
      reverseTransitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, animation, __) => FadeTransition(
        opacity: animation,
        child: ChatListScreen(
          themeModeNotifier: themeModeNotifier,
          onThemeModeChanged: onThemeModeChanged,
        ),
      ),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _ChatListScreenState extends State<ChatListScreen> {
  static const String _aliasKey = 'user_alias';
  static const String _primaryServerKey = 'primary_server';

  int _selectedIndex = 0;
  String? _alias;
  String? _primaryServer;
  List<Chat> _chats = const [];
  bool _isLoadingChats = true;
  String? _chatLoadError;

  final player = AudioPlayer();

  void playMusic() async {
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource('audio/background.mp3'));
  }

  @override
  void initState() {
    super.initState();
    MessengerWsClient.instance.setChatListVisible();
    _loadAlias();
    widget.themeModeNotifier.addListener(_onThemeChanged);
    MessengerWsClient.instance.addListener(_onMessengerChanged);
    playMusic();
  }

  @override
  void dispose() {
    widget.themeModeNotifier.removeListener(_onThemeChanged);
    MessengerWsClient.instance.removeListener(_onMessengerChanged);
    player.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onMessengerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<Chat> _sortedChatsForDisplay() {
    final originalIndexes = <String, int>{
      for (var index = 0; index < _chats.length; index++)
        _chats[index].id: index,
    };
    final wsClient = MessengerWsClient.instance;
    final sortedChats = List<Chat>.of(_chats);

    sortedChats.sort((a, b) {
      final aMessage = wsClient.latestMessageForRoom(a.id);
      final bMessage = wsClient.latestMessageForRoom(b.id);

      if (aMessage != null && bMessage != null) {
        final timeCompare = bMessage.timestamp.compareTo(aMessage.timestamp);
        if (timeCompare != 0) return timeCompare;
        return bMessage.id.compareTo(aMessage.id);
      }
      if (aMessage != null) return -1;
      if (bMessage != null) return 1;

      return (originalIndexes[a.id] ?? 0).compareTo(originalIndexes[b.id] ?? 0);
    });

    return sortedChats;
  }

  Future<void> _loadAlias() async {
    final prefs = await SharedPreferences.getInstance();
    final alias = prefs.getString(_aliasKey);
    final primaryServer = prefs.getString(_primaryServerKey);
    if (!mounted) return;
    setState(() {
      _alias = alias;
      _primaryServer = primaryServer;
    });

    _ensureWebSocketSession();

    await _loadChats();
  }

  void _ensureWebSocketSession() {
    final alias = _alias;
    final primaryServer = _primaryServer;

    if (alias?.isNotEmpty == true && primaryServer?.isNotEmpty == true) {
      unawaited(NotificationService.instance.initialize());
      unawaited(
        MessengerWsClient.instance.connect(
          alias: alias!,
          server: primaryServer!,
        ),
      );
    } else {
      unawaited(MessengerWsClient.instance.disconnect());
    }
  }

  Future<void> _loadChats() async {
    final alias = _alias;
    final server = _primaryServer;

    if (alias == null || alias.isEmpty) {
      if (!mounted) return;
      setState(() {
        _chats = const [];
        _isLoadingChats = false;
        _chatLoadError = 'Alias is not configured.';
      });
      return;
    }

    if (server == null || server.isEmpty) {
      if (!mounted) return;
      setState(() {
        _chats = const [];
        _isLoadingChats = false;
        _chatLoadError = 'Select a server in settings.';
      });
      return;
    }

    setState(() {
      _isLoadingChats = true;
      _chatLoadError = null;
    });

    final client = HttpClient();
    final roomsRequestedAt = DateTime.now().toUtc();
    try {
      final request = await client
          .getUrl(_roomsUri(server))
          .timeout(const Duration(seconds: 10));
      final body = jsonEncode({'alias': alias});
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = utf8.encode(body).length;
      request.write(body);

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.internalServerError) {
        throw const _ChatLoadException('Server error. Try again later.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const _ChatLoadException('Failed to load chats.');
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected rooms response.');
      }

      final rooms = decoded['rooms'];
      final chats = rooms == null
          ? const <Chat>[]
          : (rooms as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .map(Chat.fromJson)
                .toList();

      if (!mounted) return;
      setState(() {
        _chats = chats;
        _isLoadingChats = false;
        _chatLoadError = null;
      });
      for (final chat in chats) {
        MessengerWsClient.instance.setRoomMembers(
          chat.id,
          chat.members,
          snapshotAt: roomsRequestedAt,
        );
        await MessengerWsClient.instance.setRoomLastMessageId(
          chat.id,
          chat.lastMessageId,
        );
      }
      MessengerWsClient.instance.setTrackedRooms({
        for (final chat in chats) chat.id: chat.name,
      });
    } on _ChatLoadException catch (error) {
      if (!mounted) return;
      setState(() {
        _chats = const [];
        _isLoadingChats = false;
        _chatLoadError = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _chats = const [];
        _isLoadingChats = false;
        _chatLoadError = 'Failed to load chats.';
      });
    } finally {
      client.close(force: true);
    }
  }

  Uri _roomsUri(String server) {
    final trimmed = server.trim();
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    return Uri.parse(withScheme).replace(path: '/rooms');
  }

  Future<void> _signOut() async {
    final shouldSignOut = await showDialog<bool>(
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

    if (shouldSignOut != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_aliasKey);
    await MessengerWsClient.instance.disconnect();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unreadCount = _chats.fold<int>(
      0,
      (total, chat) =>
          total + MessengerWsClient.instance.unreadCountForRoom(chat.id),
    );
    final chatsForDisplay = _sortedChatsForDisplay();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _selectedIndex == 0
              ? _ChatsTab(
                  chats: chatsForDisplay,
                  unreadCount: unreadCount,
                  isLoading: _isLoadingChats,
                  errorText: _chatLoadError,
                  onRefresh: _loadChats,
                )
              : _SettingsTab(
                  alias: _alias ?? 'No alias',
                  themeModeNotifier: widget.themeModeNotifier,
                  onThemeModeChanged: widget.onThemeModeChanged,
                  onServersChanged: _loadAlias,
                  onSignOut: _signOut,
                ),
        ),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _NavButton(
                icon: Icons.chat_bubble_rounded,
                label: 'Chats',
                isSelected: _selectedIndex == 0,
                badgeCount: unreadCount,
                onTap: () => setState(() => _selectedIndex = 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NavButton(
                icon: Icons.settings_rounded,
                label: 'Settings',
                isSelected: _selectedIndex == 1,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatLoadException implements Exception {
  const _ChatLoadException(this.message);

  final String message;
}

class _ChatsTab extends StatelessWidget {
  const _ChatsTab({
    required this.chats,
    required this.unreadCount,
    required this.isLoading,
    required this.errorText,
    required this.onRefresh,
  });

  final List<Chat> chats;
  final int unreadCount;
  final bool isLoading;
  final String? errorText;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('chats_tab'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your recent chats',
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _ActionButton(
                    icon: Icons.search_rounded,
                    onTap: () {
                      debugPrint('Search tapped');
                    },
                  ),
                  const SizedBox(width: 10),
                  _ActionButton(
                    icon: Icons.edit_rounded,
                    onTap: () async {
                      final shouldRefresh = await Navigator.of(
                        context,
                      ).push<bool>(NewChatOptionsScreen.route());
                      if (shouldRefresh == true) {
                        await onRefresh();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (unreadCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You have $unreadCount unread messages',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: _ChatListBody(
              chats: chats,
              isLoading: isLoading,
              errorText: errorText,
              onRetry: onRefresh,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatListBody extends StatelessWidget {
  const _ChatListBody({
    required this.chats,
    required this.isLoading,
    required this.errorText,
    required this.onRetry,
  });

  final List<Chat> chats;
  final bool isLoading;
  final String? errorText;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading && chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorText != null) {
      return _ChatStateMessage(
        icon: Icons.cloud_off_rounded,
        title: errorText!,
        buttonText: 'Try again',
        onPressed: onRetry,
      );
    }

    if (chats.isEmpty) {
      return const _ChatStateMessage(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No chats yet',
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      itemCount: chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final chat = chats[index];
        return _ChatTile(chat: chat, onChatLeft: onRetry);
      },
    );
  }
}

class _ChatStateMessage extends StatelessWidget {
  const _ChatStateMessage({
    required this.icon,
    required this.title,
    this.buttonText,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String? buttonText;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 64, 20, 8),
      children: [
        Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (buttonText != null && onPressed != null) ...[
          const SizedBox(height: 18),
          Center(
            child: FilledButton(
              onPressed: () => onPressed!(),
              child: Text(buttonText!),
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.alias,
    required this.themeModeNotifier,
    required this.onThemeModeChanged,
    required this.onServersChanged,
    required this.onSignOut,
  });

  final String alias;
  final ValueNotifier<ThemeMode> themeModeNotifier;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onServersChanged;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      key: const ValueKey('settings_tab'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          'Settings',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alias.isNotEmpty ? alias : 'No alias',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsTile(
          icon: Icons.cloud_rounded,
          title: 'Servers',
          onTap: () async {
            await Navigator.of(context).push(ServerListScreen.route());
            await onServersChanged();
          },
        ),
        const SizedBox(height: 16),
        _SettingsTile(
          icon: Icons.palette_rounded,
          title: 'Appearance',
          onTap: () => Navigator.of(context).push(
            AppearanceScreen.route(
              themeModeNotifier: themeModeNotifier,
              onThemeModeChanged: (isDark) =>
                  onThemeModeChanged(isDark ? ThemeMode.dark : ThemeMode.light),
            ),
          ),
        ),
        const _SettingsTile(icon: Icons.info_rounded, title: 'About app'),
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.logout_rounded,
          title: 'Sign Out',
          iconColor: Colors.red,
          textColor: Colors.red,
          onTap: onSignOut,
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.onChatLeft});

  final Chat chat;
  final Future<void> Function() onChatLeft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wsClient = MessengerWsClient.instance;

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          final members = wsClient.membersForRoom(
            chat.id,
            fallback: chat.members,
          );
          final leftChat = await Navigator.of(context).push<bool>(
            ChatMessagesScreen.route(
              roomId: chat.id,
              roomName: chat.name,
              invite: chat.invite,
              members: members,
              lastMessageId: chat.lastMessageId,
              color: chat.color,
            ),
          );
          MessengerWsClient.instance.setChatListVisible();
          if (leftChat == true && context.mounted) {
            await onChatLeft();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: chat.color.withAlpha(41),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  chat.name.characters.first,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: chat.color,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedBuilder(
                      animation: wsClient,
                      builder: (context, _) {
                        final message =
                            wsClient.latestMessagePreviewForRoom(chat.id) ??
                            chat.message;
                        return Text(
                          message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: wsClient,
                builder: (context, _) {
                  final unreadCount = wsClient.unreadCountForRoom(chat.id);
                  if (unreadCount == 0) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.iconColor,
    this.textColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Color? iconColor;
  final Color? textColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? theme.colorScheme.onSurface),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: textColor ?? theme.colorScheme.onSurface,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withAlpha(31) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: isSelected ? Colors.white : Colors.white70),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (badgeCount > 0)
              Positioned(
                right: -2,
                top: -10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}

class Chat {
  final String id;
  final String name;
  final String message;
  final int? lastMessageId;
  final String invite;
  final List<String> members;
  final int unreadCount;
  final Color color;

  const Chat({
    required this.id,
    required this.name,
    required this.message,
    required this.lastMessageId,
    required this.invite,
    required this.members,
    required this.unreadCount,
    required this.color,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    final invite = (json['invite'] as String?) ?? '';
    final lastMessage = (json['last_msg'] as String?) ?? '';
    final lastMessageId =
        (json['last_msg_id'] as num?)?.toInt() ??
        (json['last_message_id'] as num?)?.toInt() ??
        (json['lastMessageId'] as num?)?.toInt();
    final name = (json['name'] as String?)?.trim();

    return Chat(
      id: _stringFromJson(json['id']) ?? '',
      name: name?.isNotEmpty == true ? name! : 'Unnamed room',
      message: _previewMessage(lastMessage),
      lastMessageId: lastMessageId,
      invite: invite,
      members:
          (json['members'] as List<dynamic>?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      unreadCount: 0,
      color: _colorFromInvite(invite),
    );
  }

  static String? _stringFromJson(Object? value) {
    return switch (value) {
      String value => value.trim(),
      num value => value.toString(),
      _ => null,
    };
  }

  static String _previewMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return 'No messages yet';

    const maxLength = 80;
    final chars = trimmed.characters;
    if (chars.length <= maxLength) return trimmed;
    return '${chars.take(maxLength)}...';
  }

  static Color _colorFromInvite(String invite) {
    var hash = 0;
    for (final codeUnit in invite.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));

    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.64, 0.52).toColor();
  }
}
