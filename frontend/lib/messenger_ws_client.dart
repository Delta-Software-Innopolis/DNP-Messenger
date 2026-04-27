import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

class MessengerWsClient extends ChangeNotifier {
  MessengerWsClient._();

  static final MessengerWsClient instance = MessengerWsClient._();

  WebSocket? _socket;
  Timer? _reconnectTimer;
  String? _alias;
  String? _server;
  bool _isConnecting = false;
  bool _intentionalDisconnect = false;
  int _reconnectAttempt = 0;
  Future<void>? _readStateFuture;
  Future<void>? _mutedRoomsFuture;

  final Set<String> _trackedRoomIds = {};
  final Set<String> _openRoomIds = {};
  final Map<String, String> _roomNames = {};
  final Map<String, Map<int, MessengerMessage>> _messagesByRoom = {};
  final Map<String, List<String>> _membersByRoom = {};
  final Map<String, DateTime> _membersSnapshotAt = {};
  final Map<String, int> _lastReadMessageIds = {};
  final Map<String, int> _latestRoomMessageIds = {};
  final Set<String> _mutedRoomIds = {};
  bool _isChatListVisible = false;

  bool get isConnected => _socket != null;

  Future<void> connect({required String alias, required String server}) async {
    final normalizedServer = server.trim();
    if (alias == _alias &&
        normalizedServer == _server &&
        (_socket != null || _isConnecting)) {
      return;
    }

    await disconnect();
    _alias = alias;
    _server = normalizedServer;
    _intentionalDisconnect = false;
    await _openSocket();
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close();
    }
    notifyListeners();
  }

  void setTrackedRooms(Map<String, String> rooms) {
    _trackedRoomIds
      ..clear()
      ..addAll(rooms.keys.where((id) => id.trim().isNotEmpty));
    _roomNames
      ..clear()
      ..addAll(rooms);

    unawaited(_syncTrackedRooms());
  }

  void setChatListVisible() {
    _isChatListVisible = true;
    _openRoomIds.clear();
  }

  Future<void> setRoomLastMessageId(String roomId, int? messageId) async {
    if (roomId.trim().isEmpty || messageId == null || messageId <= 0) return;

    _recordLatestRoomMessageId(roomId, messageId);
    await _ensureReadStateLoaded();

    if (!_lastReadMessageIds.containsKey(roomId)) {
      await markRoomRead(roomId, upToMessageId: messageId);
    } else {
      notifyListeners();
    }
  }

  void setRoomMembers(
    String roomId,
    List<String> members, {
    DateTime? snapshotAt,
  }) {
    if (roomId.trim().isEmpty) return;

    final normalizedMembers = _normalizeMembers(members);
    final previousMembers = _membersByRoom[roomId] ?? const <String>[];
    _membersByRoom[roomId] = normalizedMembers;
    _membersSnapshotAt[roomId] = (snapshotAt ?? DateTime.now()).toUtc();

    if (!listEquals(previousMembers, normalizedMembers)) {
      notifyListeners();
    }
  }

  List<String> membersForRoom(
    String roomId, {
    List<String> fallback = const [],
  }) {
    return _membersByRoom[roomId] ?? fallback;
  }

  List<MessengerMessage> messagesForRoom(String roomId) {
    final messages = List<MessengerMessage>.of(
      _messagesByRoom[roomId]?.values ?? const <MessengerMessage>[],
    );
    return messages..sort(MessengerMessage.compare);
  }

  MessengerMessage? latestMessageForRoom(String roomId) {
    final roomMessages = _messagesByRoom[roomId];
    if (roomMessages == null || roomMessages.isEmpty) return null;

    return roomMessages.values.reduce(
      (a, b) => MessengerMessage.compare(a, b) >= 0 ? a : b,
    );
  }

  String? latestMessagePreviewForRoom(String roomId) {
    final message = latestMessageForRoom(roomId);
    if (message == null) return null;
    return _previewMessage(message.displayText);
  }

  int unreadCountForRoom(String roomId) {
    final lastReadId = _lastReadMessageIds[roomId] ?? 0;
    final roomMessages = _messagesByRoom[roomId];
    if (roomMessages == null || roomMessages.isEmpty) return 0;

    return roomMessages.values
        .where(
          (message) =>
              message.id > lastReadId &&
              message.sender != _alias &&
              !message.isSystem,
        )
        .length;
  }

  bool isRoomMuted(String roomId) {
    return _mutedRoomIds.contains(roomId);
  }

  Future<void> setRoomMuted(String roomId, bool isMuted) async {
    if (roomId.trim().isEmpty) return;

    await _ensureMutedRoomsLoaded();

    if (isMuted) {
      _mutedRoomIds.add(roomId);
    } else {
      _mutedRoomIds.remove(roomId);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_mutedRoomsKey, _mutedRoomIds.toList());
    notifyListeners();
  }

  int? lastMessageIdForRoom(String roomId) {
    final roomMessages = _messagesByRoom[roomId];
    if (roomMessages == null || roomMessages.isEmpty) return null;
    return roomMessages.keys.reduce((a, b) => a > b ? a : b);
  }

  int? oldestMessageIdForRoom(String roomId) {
    final roomMessages = _messagesByRoom[roomId];
    if (roomMessages == null || roomMessages.isEmpty) return null;
    return roomMessages.keys.reduce((a, b) => a < b ? a : b);
  }

  bool sendTextMessage({required String roomId, required String text}) {
    final alias = _alias;
    if (alias == null || _socket == null || text.trim().isEmpty) {
      return false;
    }

    _send({'type': 2, 'text': text.trim(), 'alias': alias, 'room_id': roomId});
    return true;
  }

  bool requestOlderMessages({
    required String roomId,
    int count = 30,
    int? before,
  }) {
    final alias = _alias;
    if (alias == null || _socket == null) return false;

    _send({
      'type': 0,
      'count': count,
      'before': before ?? 9223372036854775807,
      'alias': alias,
      'room_id': roomId,
    });
    return true;
  }

  bool requestMessagesAfter({required String roomId, required int after}) {
    final alias = _alias;
    if (alias == null || _socket == null) return false;

    _send({'type': 1, 'after': after, 'alias': alias, 'room_id': roomId});
    return true;
  }

  Future<void> openRoom(String roomId) async {
    if (roomId.trim().isEmpty) return;

    _isChatListVisible = false;
    _openRoomIds.add(roomId);
    await markRoomRead(roomId);
  }

  Future<void> closeRoom(String roomId) async {
    if (roomId.trim().isEmpty) return;

    _openRoomIds.remove(roomId);
    await markRoomRead(roomId);
  }

  Future<void> markRoomRead(String roomId, {int? upToMessageId}) async {
    if (roomId.trim().isEmpty) return;

    await _ensureReadStateLoaded();

    final latestKnownId =
        upToMessageId ??
        lastMessageIdForRoom(roomId) ??
        _latestRoomMessageIds[roomId];
    if (latestKnownId == null || latestKnownId <= 0) return;

    final previousId = _lastReadMessageIds[roomId] ?? 0;
    if (latestKnownId <= previousId) return;

    _lastReadMessageIds[roomId] = latestKnownId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_readPreferenceKey(roomId), latestKnownId);
    notifyListeners();
  }

  Future<void> _openSocket() async {
    final alias = _alias;
    final server = _server;
    if (alias == null || alias.isEmpty || server == null || server.isEmpty) {
      return;
    }
    if (_isConnecting) return;

    _isConnecting = true;
    try {
      final socket = await WebSocket.connect(
        _wsUri(server, alias).toString(),
      ).timeout(const Duration(seconds: 10));
      socket.pingInterval = const Duration(seconds: 20);
      await _ensureMutedRoomsLoaded();

      _socket = socket;
      _reconnectAttempt = 0;
      notifyListeners();
      unawaited(_syncTrackedRooms());

      socket.listen(
        _handleSocketData,
        onDone: _handleSocketClosed,
        onError: (_) => _handleSocketClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  void _handleSocketData(dynamic data) {
    final payload = switch (data) {
      String value => value,
      List<int> value => utf8.decode(value),
      _ => null,
    };
    if (payload == null) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    final rawMessages = decoded['messages'];
    if (rawMessages is! List<dynamic>) return;

    var changed = false;
    final notifications = <MessengerMessage>[];
    for (final rawMessage in rawMessages) {
      if (rawMessage is! Map<String, dynamic>) continue;
      final message = MessengerMessage.fromJson(rawMessage);
      if (message == null) continue;

      final roomMessages = _messagesByRoom.putIfAbsent(
        message.roomId,
        () => <int, MessengerMessage>{},
      );
      final previous = roomMessages[message.id];
      roomMessages[message.id] = message;
      changed = changed || previous != message;

      if (previous == null) {
        _recordLatestRoomMessageId(message.roomId, message.id);
        changed = _applyMembershipEvent(message) || changed;
        if (_openRoomIds.contains(message.roomId)) {
          unawaited(markRoomRead(message.roomId, upToMessageId: message.id));
        }
        if (_shouldNotifyFor(message)) {
          notifications.add(message);
        }
      }
    }

    if (changed) {
      notifyListeners();
    }
    for (final message in notifications) {
      unawaited(_showNotificationFor(message));
    }
  }

  void _handleSocketClosed() {
    _socket = null;
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_alias == null || _server == null) return;
    if (_reconnectTimer?.isActive == true) return;

    _reconnectAttempt += 1;
    final delaySeconds = _reconnectAttempt.clamp(1, 8).toInt();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), _openSocket);
  }

  Future<void> _syncTrackedRooms() async {
    if (_socket == null) return;
    await _ensureReadStateLoaded();
    await _ensureMutedRoomsLoaded();

    for (final roomId in _trackedRoomIds) {
      final lastId = lastMessageIdForRoom(roomId);
      final lastReadId = _lastReadMessageIds[roomId];
      requestMessagesAfter(roomId: roomId, after: lastId ?? lastReadId ?? 0);
    }
  }

  void _send(Map<String, Object> payload) {
    _socket?.add(jsonEncode(payload));
  }

  bool _shouldNotifyFor(MessengerMessage message) {
    if (message.sender == _alias) return false;
    if (_mutedRoomIds.contains(message.roomId)) return false;
    if (_isChatListVisible && _openRoomIds.isEmpty) return false;
    if (_openRoomIds.contains(message.roomId)) return false;
    return true;
  }

  Future<void> _showNotificationFor(MessengerMessage message) async {
    final roomName = _roomNames[message.roomId] ?? 'New message';
    final body = message.isSystem
        ? message.displayText
        : '${message.sender}: ${message.text}';
    await NotificationService.instance.showMessage(
      id: message.id,
      title: roomName,
      body: body,
    );
  }

  void _recordLatestRoomMessageId(String roomId, int messageId) {
    if (roomId.trim().isEmpty || messageId <= 0) return;

    final previousId = _latestRoomMessageIds[roomId] ?? 0;
    if (messageId > previousId) {
      _latestRoomMessageIds[roomId] = messageId;
    }
  }

  Future<void> _ensureReadStateLoaded() {
    return _readStateFuture ??= _loadReadState();
  }

  Future<void> _ensureMutedRoomsLoaded() {
    return _mutedRoomsFuture ??= _loadMutedRooms();
  }

  Future<void> _loadMutedRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_mutedRoomsKey) ?? const <String>[];
    _mutedRoomIds
      ..clear()
      ..addAll(saved.where((id) => id.trim().isNotEmpty));
  }

  Future<void> _loadReadState() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_readPreferencePrefix)) continue;

      final roomId = key.substring(_readPreferencePrefix.length);
      final messageId = prefs.getInt(key);
      if (roomId.trim().isEmpty || messageId == null || messageId <= 0) {
        continue;
      }

      _lastReadMessageIds[roomId] = messageId;
    }
  }

  static const String _readPreferencePrefix = 'last_read_message_id_';
  static const String _mutedRoomsKey = 'muted_room_ids';

  static String _readPreferenceKey(String roomId) {
    return '$_readPreferencePrefix$roomId';
  }

  bool _applyMembershipEvent(MessengerMessage message) {
    if (!message.isMembershipEvent || message.sender.trim().isEmpty) {
      return false;
    }

    final snapshotAt = _membersSnapshotAt[message.roomId];
    if (snapshotAt != null && !message.timestamp.toUtc().isAfter(snapshotAt)) {
      return false;
    }

    final members = List<String>.of(
      _membersByRoom[message.roomId] ?? const <String>[],
    );
    final previousMembers = List<String>.of(members);

    if (message.isJoinEvent && !members.contains(message.sender)) {
      members.add(message.sender);
      members.sort();
    } else if (message.isLeaveEvent) {
      members.remove(message.sender);
    }

    final normalizedMembers = _normalizeMembers(members);
    _membersByRoom[message.roomId] = normalizedMembers;
    return !listEquals(previousMembers, normalizedMembers);
  }

  static List<String> _normalizeMembers(List<String> members) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final member in members) {
      final trimmed = member.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      normalized.add(trimmed);
    }
    return List.unmodifiable(normalized);
  }

  static String _previewMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return 'No messages yet';

    const maxLength = 80;
    final runes = trimmed.runes.toList();
    if (runes.length <= maxLength) return trimmed;
    return '${String.fromCharCodes(runes.take(maxLength))}...';
  }

  Uri _wsUri(String server, String alias) {
    final trimmed = server.trim();
    final withScheme =
        trimmed.startsWith('http://') ||
            trimmed.startsWith('https://') ||
            trimmed.startsWith('ws://') ||
            trimmed.startsWith('wss://')
        ? trimmed
        : 'ws://$trimmed';

    final uri = Uri.parse(withScheme);
    final wsScheme = switch (uri.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      'wss' => 'wss',
      _ => 'ws',
    };

    return uri.replace(
      scheme: wsScheme,
      path: '/ws',
      queryParameters: {'alias': alias},
    );
  }
}

class MessengerMessage {
  const MessengerMessage({
    required this.id,
    required this.type,
    required this.text,
    required this.sender,
    required this.timestamp,
    required this.roomId,
  });

  final int id;
  final int type;
  final String text;
  final String sender;
  final DateTime timestamp;
  final String roomId;

  bool get isSystem => type == 1 || type == 2;
  bool get isJoinEvent => type == 1;
  bool get isLeaveEvent => type == 2;
  bool get isMembershipEvent => isJoinEvent || isLeaveEvent;

  String get displayText {
    if (isJoinEvent) return '$sender joined the chat';
    if (isLeaveEvent) return '$sender left the chat';
    return text;
  }

  static MessengerMessage? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    final type = (json['type'] as num?)?.toInt();
    final roomId = _stringFromJson(json['room_id']);
    final timestampRaw = json['timestamp'] as String?;

    if (id == null ||
        type == null ||
        roomId == null ||
        roomId.isEmpty ||
        timestampRaw == null) {
      return null;
    }

    return MessengerMessage(
      id: id,
      type: type,
      text: (json['text'] as String?) ?? '',
      sender: (json['sender'] as String?) ?? '',
      timestamp: DateTime.tryParse(timestampRaw) ?? DateTime.now().toUtc(),
      roomId: roomId,
    );
  }

  static String? _stringFromJson(Object? value) {
    return switch (value) {
      String value => value.trim(),
      num value => value.toString(),
      _ => null,
    };
  }

  static int compare(MessengerMessage a, MessengerMessage b) {
    final timeCompare = a.timestamp.compareTo(b.timestamp);
    if (timeCompare != 0) return timeCompare;
    return a.id.compareTo(b.id);
  }

  @override
  bool operator ==(Object other) {
    return other is MessengerMessage &&
        other.id == id &&
        other.type == type &&
        other.text == text &&
        other.sender == sender &&
        other.timestamp == timestamp &&
        other.roomId == roomId;
  }

  @override
  int get hashCode => Object.hash(id, type, text, sender, timestamp, roomId);
}
