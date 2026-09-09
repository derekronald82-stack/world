import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/auth_store.dart';
import 'screens/admin_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CatwsAdminApp());
}

class CatwsAdminApp extends StatefulWidget {
  const CatwsAdminApp({super.key});

  @override
  State<CatwsAdminApp> createState() => _CatwsAdminAppState();
}

class _CatwsAdminAppState extends State<CatwsAdminApp> {
  late final AuthStore auth = AuthStore(ApiClient());
  bool ready = false;

  @override
  void initState() {
    super.initState();
    auth.addListener(_changed);
    auth.restore().then((_) {
      if (mounted) setState(() => ready = true);
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    auth.removeListener(_changed);
    auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CATWS SONGS ADMIN',
        theme: _adminTheme(),
        home: !ready || auth.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : auth.loggedIn && auth.isAdmin
                ? AdminScreen(api: auth.api, onChanged: _changed)
                : LoginScreen(auth: auth, adminOnly: true),
      );
}

ThemeData _adminTheme() {
  const accent = Color(0xFF984D45);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light),
    scaffoldBackgroundColor: const Color(0xFFFFFAF7),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFFFFAF7), foregroundColor: Color(0xFF403634), elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFFEEE9),
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)), borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
  );
}
