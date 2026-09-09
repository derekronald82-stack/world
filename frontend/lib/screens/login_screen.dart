import 'package:flutter/material.dart';
import '../core/auth_store.dart';
import '../core/api_client.dart';

class LoginScreen extends StatefulWidget {
  final AuthStore auth;
  final bool adminOnly;
  const LoginScreen({super.key, required this.auth, this.adminOnly = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final user = TextEditingController();
  final pass = TextEditingController();
  bool registerMode = false;
  bool busy = false;
  bool hide = true;
  bool rememberMe = true;
  String? error;

  static const navy = Color(0xFF081552);
  static const blue = Color(0xFF2B43FF);

  @override
  void dispose() {
    user.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (user.text.trim().isEmpty || pass.text.isEmpty) {
      setState(() => error = 'Enter username and password.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (registerMode && !widget.adminOnly) {
        await widget.auth.register(user.text.trim(), pass.text);
      } else {
        await widget.auth.login(user.text.trim(), pass.text);
        if (widget.adminOnly && !widget.auth.isAdmin) {
          await widget.auth.logout();
          throw Exception('Admin access required.');
        }
        if (mounted && widget.adminOnly) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = friendlyApiError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void toggleMode() {
    setState(() {
      registerMode = !registerMode;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return wide ? _desktop() : _mobile();
        },
      ),
    );
  }

  Widget _desktop() {
    return Row(
      children: [
        Expanded(flex: 58, child: _HeroPanel()),
        Expanded(
          flex: 42,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0B1B68),
                  Color(0xFF101253),
                  Color(0xFF25105D)
                ],
              ),
            ),
            child: Stack(
              children: [
                const Positioned(
                    right: -70,
                    top: -70,
                    child: _GlowBall(
                        size: 220,
                        colors: [Color(0xFF19D8FF), Color(0xFF9848FF)])),
                const Positioned(
                    right: -80,
                    bottom: 140,
                    child: _GlowBall(
                        size: 180,
                        colors: [Color(0xFFFF33D2), Color(0xFF6C2BFF)])),
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 28),
                      child: _LoginCard(
                          adminOnly: widget.adminOnly,
                          registerMode: registerMode,
                          child: _form()),
                    ),
                  ),
                ),
                const Positioned(
                  right: 30,
                  bottom: 28,
                  child: Text(
                    'Music\nConnects\nUs',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        height: 1.05),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobile() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFBFA), Color(0xFFF7F5FF)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            children: [
              const Row(
                children: [
                  _BrandMark(compact: true),
                  Spacer(),
                  Icon(Icons.dark_mode_outlined, color: navy),
                ],
              ),
              const SizedBox(height: 26),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                      colors: [Color(0xFF0D1A66), Color(0xFF5723C9)]),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Music for Every Mood',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900)),
                          SizedBox(height: 6),
                          Text('Stream • Discover • Create • Share',
                              style: TextStyle(
                                  color: Color(0xFFD9E0FF), fontSize: 12)),
                        ],
                      ),
                    ),
                    Icon(Icons.headphones_rounded,
                        size: 62, color: Color(0xFFFFD54A)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _LoginCard(
                  adminOnly: widget.adminOnly,
                  registerMode: registerMode,
                  child: _form(),
                  compact: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: user,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration:
              _inputDecoration('Username', Icons.person_outline_rounded),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: pass,
          obscureText: hide,
          onSubmitted: (_) => submit(),
          autofillHints: const [AutofillHints.password],
          decoration:
              _inputDecoration('Password', Icons.lock_outline_rounded).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                  hide
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF77809B)),
              onPressed: () => setState(() => hide = !hide),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: rememberMe,
                activeColor: blue,
                side: const BorderSide(color: Color(0xFFB7BFD2)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                onChanged:
                    busy ? null : (v) => setState(() => rememberMe = v ?? true),
              ),
            ),
            const SizedBox(width: 7),
            const Text('Remember me',
                style: TextStyle(color: navy, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(
              onPressed: busy
                  ? null
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Forgot password can be connected to your email reset flow later.')),
                      ),
              child: const Text('Forgot password?',
                  style: TextStyle(color: blue, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFECEC),
                borderRadius: BorderRadius.circular(12)),
            child: Text(error!,
                style: const TextStyle(
                    color: Color(0xFFB42318), fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
          ),
        ],
        const SizedBox(height: 16),
        _GradientButton(
          label: busy
              ? (registerMode ? 'Creating...' : 'Logging in...')
              : (registerMode ? 'Create Account' : 'Login'),
          loading: busy,
          onTap: busy ? null : submit,
        ),
        const SizedBox(height: 22),
        const Row(
          children: [
            Expanded(child: Divider(color: Color(0xFFDDE1EA))),
          ],
        ),
        const SizedBox(height: 18),
        if (!widget.adminOnly)
          OutlinedButton.icon(
            onPressed: busy ? null : toggleMode,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              side: const BorderSide(color: blue, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
              foregroundColor: blue,
            ),
            icon: Icon(registerMode
                ? Icons.login_rounded
                : Icons.person_add_alt_1_rounded),
            label: Text(
              registerMode
                  ? 'Already a User? Login'
                  : 'New User? Create Account',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          color: Color(0xFF8C93A6), fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, color: const Color(0xFF77809B)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 19, horizontal: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFD5DAE5), width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFF23A9F4), width: 1.8),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final bool adminOnly;
  final bool registerMode;
  final Widget child;
  final bool compact;
  const _LoginCard(
      {required this.adminOnly,
      required this.registerMode,
      required this.child,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 500 : 560),
      child: Container(
        padding: EdgeInsets.fromLTRB(compact ? 22 : 38, compact ? 28 : 48,
            compact ? 22 : 38, compact ? 28 : 42),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 24 : 20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(.08),
                blurRadius: 26,
                offset: const Offset(0, 10))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              adminOnly
                  ? 'Admin Login'
                  : registerMode
                      ? 'Create Account'
                      : 'Welcome Back!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF081552),
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5),
            ),
            const SizedBox(height: 8),
            Text(
              adminOnly
                  ? 'Authorized admin access only'
                  : registerMode
                      ? 'Create your Catws Songs account'
                      : 'Login to continue to Catws Songs',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF858CA1),
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            SizedBox(height: compact ? 28 : 34),
            child,
          ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  const _GradientButton(
      {required this.label, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: const LinearGradient(
            colors: [Color(0xFF3041FF), Color(0xFF27C6F1)]),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF3041FF).withOpacity(.18),
              blurRadius: 18,
              offset: const Offset(0, 8))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 23,
                    height: 23,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.login_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFFEFD),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: CustomPaint(painter: _HeroPainter())),
          const Positioned(left: 38, top: 24, child: _BrandMark()),
          const Positioned(
            right: 44,
            top: 27,
            child: Row(
              children: [
                Text('Home',
                    style: TextStyle(
                        color: Color(0xFF081552), fontWeight: FontWeight.w800)),
                SizedBox(width: 28),
                Text('About',
                    style: TextStyle(
                        color: Color(0xFF081552), fontWeight: FontWeight.w800)),
                SizedBox(width: 28),
                Text('Help',
                    style: TextStyle(
                        color: Color(0xFF081552), fontWeight: FontWeight.w800)),
                SizedBox(width: 24),
                Icon(Icons.dark_mode_outlined, color: Color(0xFF081552)),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 92,
            child: Column(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFFFC928), size: 54),
                Transform.rotate(
                  angle: -0.035,
                  child: const Text(
                    'catws\nsongs',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFF082B93),
                        fontSize: 68,
                        height: .73,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -4),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Music for Every Mood',
                    style: TextStyle(
                        color: Color(0xFF0A286E),
                        fontSize: 24,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                const Text('Stream • Discover • Create • Share',
                    style: TextStyle(
                        color: Color(0xFF6E7895),
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ],
            ),
          ),
          const Positioned(left: 70, top: 430, child: _VibeBadge()),
          const Positioned(right: 80, top: 180, child: _PhoneMockup()),
          const Positioned(left: 195, bottom: 120, child: _DjIllustration()),
          Positioned(
            left: 36,
            bottom: 34,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                  color: const Color(0xFF07164E),
                  borderRadius: BorderRadius.circular(12)),
              child: const Text('Life Sounds\nBetter Here ♡',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.15,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const Positioned(
              left: 38,
              bottom: 10,
              child: Text('© 2026 Catws Songs. All rights reserved.',
                  style: TextStyle(color: Color(0xFF8990A3), fontSize: 10))),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  final bool compact;
  const _BrandMark({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 34 : 38,
          height: compact ? 34 : 38,
          decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(11)),
          child: Icon(Icons.music_note_rounded,
              color: const Color(0xFF304CFF), size: compact ? 23 : 27),
        ),
        const SizedBox(width: 9),
        Text('catws songs',
            style: TextStyle(
                color: const Color(0xFF081552),
                fontSize: compact ? 21 : 23,
                fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _GlowBall extends StatelessWidget {
  final double size;
  final List<Color> colors;
  const _GlowBall({required this.size, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
          boxShadow: [
            BoxShadow(color: colors.last.withOpacity(.5), blurRadius: 60)
          ]),
    );
  }
}

class _VibeBadge extends StatelessWidget {
  const _VibeBadge();
  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
            color: const Color(0xFFFFD236),
            borderRadius: BorderRadius.circular(24)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq_rounded, color: Color(0xFF0A2C8B)),
            SizedBox(width: 10),
            Text('Your Music\nYour Vibe',
                style: TextStyle(
                    color: Color(0xFF0A2C8B),
                    fontWeight: FontWeight.w900,
                    height: 1.05)),
          ],
        ),
      ),
    );
  }
}

class _PhoneMockup extends StatelessWidget {
  const _PhoneMockup();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: .22,
      child: Container(
        width: 100,
        height: 188,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
            color: const Color(0xFF080A16),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(.25),
                  blurRadius: 18,
                  offset: const Offset(6, 10))
            ]),
        child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF190E34), Color(0xFF0A0A17)])),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Container(
                    width: 28,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 12),
                ...List.generate(
                    3,
                    (r) => Expanded(
                        child: Row(
                            children: List.generate(
                                2,
                                (c) => Expanded(
                                    child: Container(
                                        margin: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            color: [
                                              const Color(0xFF8D45D9),
                                              const Color(0xFF10A8D5),
                                              const Color(0xFFCA3E91),
                                              const Color(0xFFEF7E45)
                                            ][(r + c) % 4]))))))),
                const SizedBox(height: 7),
                const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Icon(Icons.home_rounded, color: Colors.white54, size: 12),
                      Icon(Icons.search, color: Colors.white54, size: 12),
                      Icon(Icons.person, color: Colors.white54, size: 12)
                    ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DjIllustration extends StatelessWidget {
  const _DjIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      height: 245,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 18,
            child: Container(
              width: 265,
              height: 72,
              decoration: BoxDecoration(
                  color: const Color(0xFF7AD82A),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF0A2C8B), width: 2)),
              child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Icon(Icons.album_rounded,
                        size: 58, color: Color(0xFFFFD52B)),
                    Icon(Icons.equalizer_rounded,
                        size: 58, color: Color(0xFFEF3E52)),
                    Icon(Icons.album_rounded,
                        size: 58, color: Color(0xFFFFD52B))
                  ]),
            ),
          ),
          Positioned(
            top: 15,
            child: Container(
              width: 105,
              height: 145,
              decoration: BoxDecoration(
                  color: const Color(0xFF69D936),
                  borderRadius: BorderRadius.circular(45),
                  border: Border.all(color: const Color(0xFF0A2C8B), width: 2)),
              child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.headphones_rounded,
                        size: 66, color: Color(0xFFEF4B5F)),
                    SizedBox(height: 4),
                    Icon(Icons.music_note_rounded,
                        color: Color(0xFF0A2C8B), size: 30)
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPainter extends CustomPainter {
  const _HeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final pale = Paint()..color = const Color(0xFFFFE9E4);
    canvas.drawCircle(Offset(35, size.height * .30), 92, pale);
    canvas.drawCircle(Offset(size.width * .36, size.height * .87), 120,
        Paint()..color = const Color(0xFFFFF0EA));

    final navy = Paint()..color = const Color(0xFF0A1E70);
    final path = Path()
      ..moveTo(size.width * .78, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * .93, size.height)
      ..cubicTo(size.width * .90, size.height * .78, size.width * .86,
          size.height * .70, size.width * .92, size.height * .58)
      ..cubicTo(size.width * .99, size.height * .44, size.width * .84,
          size.height * .37, size.width * .86, size.height * .26)
      ..cubicTo(size.width * .89, size.height * .13, size.width * .80,
          size.height * .12, size.width * .78, 0)
      ..close();
    canvas.drawPath(path, navy);

    final gridPaint = Paint()
      ..color = const Color(0xFF7E8CB5).withOpacity(.07)
      ..strokeWidth = 1;
    const step = 22.0;
    for (double x = 0; x < size.width * .78; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width * .78, y), gridPaint);
    }

    final doodle = Paint()
      ..color = const Color(0xFF2847D8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(
            center: Offset(size.width * .18, size.height * .53), radius: 30),
        -.8,
        4.6,
        false,
        doodle);
    canvas.drawLine(Offset(size.width * .18, size.height * .50),
        Offset(size.width * .18, size.height * .58), doodle);
    canvas.drawCircle(Offset(size.width * .16, size.height * .59), 8, doodle);
    canvas.drawCircle(Offset(size.width * .20, size.height * .59), 8, doodle);

    final yellow = Paint()..color = const Color(0xFFFFD333);
    canvas.drawCircle(Offset(size.width * .72, size.height * .40), 12, yellow);
    canvas.drawCircle(Offset(size.width * .59, size.height * .14), 7,
        Paint()..color = const Color(0xFFEF3D54));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
