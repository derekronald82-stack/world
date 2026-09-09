import 'package:flutter/material.dart';
import 'core/api_client.dart';
import 'core/auth_store.dart';
import 'core/local_library_store.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EightDMusicApp());
}

class EightDMusicApp extends StatefulWidget {
  const EightDMusicApp({super.key});
  @override
  State<EightDMusicApp> createState() => _EightDMusicAppState();
}

class _EightDMusicAppState extends State<EightDMusicApp> {
  late final AuthStore auth = AuthStore(ApiClient());
  late final LocalLibraryStore localLibrary = LocalLibraryStore();
  bool ready = false;

  @override
  void initState() {
    super.initState();
    auth.addListener(_refresh);
    _restore();
  }

  void _refresh() => setState(() {});

  Future<void> _restore() async {
    await Future.wait([auth.restore(), localLibrary.restore()]);
    if (mounted) setState(() => ready = true);
  }

  @override
  void dispose() {
    auth.removeListener(_refresh);
    auth.dispose();
    localLibrary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF984D45);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Catws Songs',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: accent, brightness: Brightness.light),
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
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      home: !ready || auth.loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : auth.loggedIn
          ? HomeScreen(auth: auth, localLibrary: localLibrary, showAdminControls: false)
            : LoginScreen(auth: auth),
    );
  }
}
