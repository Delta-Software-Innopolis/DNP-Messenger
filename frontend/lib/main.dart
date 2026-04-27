import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';
import 'chat_list_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const String _themeModeKey = 'theme_mode';

  final ValueNotifier<ThemeMode> _themeModeNotifier = ValueNotifier(
    ThemeMode.light,
  );

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeModeKey);
    if (!mounted) return;
    setState(() {
      _themeModeNotifier.value = saved == 'dark'
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  Future<void> _updateThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _themeModeKey,
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
    if (!mounted) return;
    setState(() {
      _themeModeNotifier.value = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeModeNotifier.value,
      initialRoute: '/',
      routes: {
        '/': (_) => SplashToRegisterScreen(
          themeModeNotifier: _themeModeNotifier,
          onThemeModeChanged: _updateThemeMode,
        ),
      },
    );
  }
}

class SplashToRegisterScreen extends StatefulWidget {
  const SplashToRegisterScreen({
    super.key,
    required this.themeModeNotifier,
    required this.onThemeModeChanged,
  });

  final ValueNotifier<ThemeMode> themeModeNotifier;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<SplashToRegisterScreen> createState() => _SplashToRegisterScreenState();
}

class _SplashToRegisterScreenState extends State<SplashToRegisterScreen> {
  static const String _aliasKey = 'user_alias';

  final TextEditingController _aliasController = TextEditingController();
  bool _showForm = false;
  bool _isSaving = false;
  bool notAFraud = false;
  String? _savedAlias;

  @override
  void initState() {
    super.initState();
    _loadSavedAlias();
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAlias() async {
    final prefs = await SharedPreferences.getInstance();
    final alias = prefs.getString(_aliasKey);
    if (!mounted) return;

    _savedAlias = alias;
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      if (_savedAlias?.isNotEmpty == true) {
        Navigator.of(context).pushReplacement(
          ChatListScreen.route(
            themeModeNotifier: widget.themeModeNotifier,
            onThemeModeChanged: widget.onThemeModeChanged,
          ),
        );
      } else {
        setState(() {
          _showForm = true;
        });
      }
    });
  }

  Future<void> _saveAlias(String alias) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aliasKey, alias);
  }

  Future<void> _handleSignUp() async {
    final alias = _aliasController.text.trim();
    if (alias.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an alias.')));
      return;
    }
    if (!notAFraud) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please confirm that you are not a fraud.'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    await _saveAlias(alias);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      ChatListScreen.route(
        themeModeNotifier: widget.themeModeNotifier,
        onThemeModeChanged: widget.onThemeModeChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeInOut,
              alignment: _showForm
                  ? const Alignment(0, -0.82)
                  : Alignment.center,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
                scale: _showForm ? 0.8 : 1.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/logo.png',
                      width: screenWidth * 0.4,
                      height: screenWidth * 0.4,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'OLEG',
                      style: TextStyle(
                        fontSize: screenWidth * 0.1,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            AnimatedOpacity(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOut,
              opacity: _showForm ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_showForm,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 220),

                        const SizedBox(height: 16),
                        TextField(
                          controller: _aliasController,
                          style: TextStyle(color: theme.colorScheme.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Alias',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          title: Text(
                            'I confirm that I am not a fraud',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          activeColor: theme.colorScheme.primary,
                          checkColor: theme.colorScheme.onPrimary,
                          value: notAFraud,
                          onChanged: (bool? value) {
                            setState(() {
                              notAFraud = value!;
                            });
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _handleSignUp,
                            child: _isSaving
                                ? CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.colorScheme.onPrimary,
                                    ),
                                  )
                                : const Text('Sign Up'),
                          ),
                        ),
                      ],
                    ),
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
