import 'package:flutter/material.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({
    super.key,
    required this.themeModeNotifier,
    required this.onThemeModeChanged,
  });

  final ValueNotifier<ThemeMode> themeModeNotifier;
  final ValueChanged<bool> onThemeModeChanged;

  static Route<void> route({
    required ValueNotifier<ThemeMode> themeModeNotifier,
    required ValueChanged<bool> onThemeModeChanged,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => AppearanceScreen(
        themeModeNotifier: themeModeNotifier,
        onThemeModeChanged: onThemeModeChanged,
      ),
    );
  }

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late bool _isDarkMode;
  late ThemeMode _lastThemeMode;

  @override
  void initState() {
    super.initState();
    _lastThemeMode = widget.themeModeNotifier.value;
    _isDarkMode = _lastThemeMode == ThemeMode.dark;
    widget.themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    widget.themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    final currentThemeMode = widget.themeModeNotifier.value;
    if (_lastThemeMode != currentThemeMode) {
      setState(() {
        _lastThemeMode = currentThemeMode;
        _isDarkMode = currentThemeMode == ThemeMode.dark;
      });
    }
  }

  void _handleThemeChanged(bool value) {
    setState(() {
      _isDarkMode = value;
      _lastThemeMode = value ? ThemeMode.dark : ThemeMode.light;
    });
    widget.onThemeModeChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        color: theme.scaffoldBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theme',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: theme.colorScheme.outline.withAlpha(64)),
              ),
              child: SwitchListTile(
                title: const Text('Dark theme'),
                subtitle: const Text('Use dark mode across the app'),
                value: _isDarkMode,
                activeThumbColor: theme.colorScheme.primary,
                onChanged: _handleThemeChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
