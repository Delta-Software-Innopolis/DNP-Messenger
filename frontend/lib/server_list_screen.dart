import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'messenger_ws_client.dart';

class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const ServerListScreen());
  }

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  static const String _aliasKey = 'user_alias';
  static const String _serversKey = 'server_list';
  static const String _primaryServerKey = 'primary_server';

  final TextEditingController _controller = TextEditingController();
  List<String> _servers = [];
  String? _primaryServer;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_serversKey) ?? [];
    final primary = prefs.getString(_primaryServerKey);
    if (!mounted) return;
    setState(() {
      _servers = saved;
      _primaryServer = primary;
      if (_primaryServer != null && !_servers.contains(_primaryServer)) {
        _primaryServer = null;
      }
    });
  }

  Future<void> _saveServers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_serversKey, _servers);
  }

  Future<void> _savePrimaryServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (_primaryServer == null) {
      await prefs.remove(_primaryServerKey);
    } else {
      await prefs.setString(_primaryServerKey, _primaryServer!);
    }
  }

  Future<void> _showAddServerDialog() async {
    _controller.clear();

    final added = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add server'),
          content: TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'IP:PORT'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final input = _controller.text.trim();
                if (input.isEmpty) return;
                Navigator.of(context).pop(true);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (added != true) return;

    final server = _controller.text.trim();
    if (server.isEmpty) return;

    setState(() {
      _servers = List.of(_servers)..add(server);
    });
    await _saveServers();
  }

  Future<void> _deleteServer(int index) async {
    final removedServer = _servers[index];
    setState(() {
      _servers = List.of(_servers)..removeAt(index);
      if (_primaryServer == removedServer) {
        _primaryServer = null;
      }
    });
    await _saveServers();
    await _savePrimaryServer();
    await _syncWebSocketSession();
  }

  Future<void> _setPrimaryServer(String? server) async {
    setState(() {
      _primaryServer = server;
    });
    await _savePrimaryServer();
    await _syncWebSocketSession();
  }

  Future<void> _syncWebSocketSession() async {
    final prefs = await SharedPreferences.getInstance();
    final alias = prefs.getString(_aliasKey);
    final primaryServer = prefs.getString(_primaryServerKey);

    if (alias?.isNotEmpty == true && primaryServer?.isNotEmpty == true) {
      await MessengerWsClient.instance.connect(
        alias: alias!,
        server: primaryServer!,
      );
    } else {
      await MessengerWsClient.instance.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: Navigator.of(context).pop,
        ),
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        color: theme.scaffoldBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Configured servers', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _primaryServer != null && _primaryServer!.isNotEmpty
                        ? _primaryServer
                        : null,
                    isExpanded: true,
                    hint: const Text('Select Server'),
                    items: _servers.map((server) {
                      return DropdownMenuItem(
                        value: server,
                        child: Text(server),
                      );
                    }).toList(),
                    onChanged: _servers.isEmpty ? null : _setPrimaryServer,
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                  child: IconButton(
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    onPressed: _showAddServerDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _servers.isEmpty
                  ? Center(
                      child: Text(
                        'No servers yet. Tap + to add one.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _servers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final server = _servers[index];
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: Color(0xFFE5EBF5)),
                          ),
                          child: ListTile(
                            title: Text(server),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_rounded,
                                color: Colors.red,
                              ),
                              onPressed: () => _deleteServer(index),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
