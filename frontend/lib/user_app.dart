import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_update_service.dart';
import 'core/auth_store.dart';
import 'core/local_library_store.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CatwsUserApp());
}

class CatwsUserApp extends StatefulWidget {
  const CatwsUserApp({super.key});

  @override
  State<CatwsUserApp> createState() => _CatwsUserAppState();
}

class _CatwsUserAppState extends State<CatwsUserApp> {
  late final AuthStore auth = AuthStore(ApiClient());
  late final LocalLibraryStore localLibrary = LocalLibraryStore();
  bool ready = false;
  bool _updateCheckStarted = false;

  @override
  void initState() {
    super.initState();
    auth.addListener(_changed);
    _restore();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    await Future.wait([auth.restore(), localLibrary.restore()]);
    if (mounted) {
      setState(() => ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    if (_updateCheckStarted || !mounted) return;
    _updateCheckStarted = true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) await checkAndShowAppUpdate(context, auth.api);
  }

  @override
  void dispose() {
    auth.removeListener(_changed);
    auth.dispose();
    localLibrary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CATWS SONGS',
        theme: _theme(),
        home: !ready || auth.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : auth.loggedIn
                ? HomeScreen(
                    auth: auth,
                    localLibrary: localLibrary,
                    showAdminControls: false)
                : LoginScreen(auth: auth),
      );
}

ThemeData _theme() {
  const accent = Color(0xFF984D45);
  return ThemeData(
    useMaterial3: true,
    colorScheme:
        ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light),
    scaffoldBackgroundColor: const Color(0xFFFFFAF7),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFFFFAF7),
      foregroundColor: Color(0xFF403634),
      centerTitle: false,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFFEEE9),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
