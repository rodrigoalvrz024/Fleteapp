import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../services/driver_onboarding_service.dart';
import '../../core/theme/app_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {

  double _logoOpacity     = 0;
  double _logoScale       = 0.88;
  double _titleOpacity    = 0;
  double _subtitleOpacity = 0;
  double _cardOpacity     = 0;
  double _cardOffset      = 12;
  double _loaderOpacity   = 0;

  bool   _isFirstTime = false;
  String _loadingText = 'Iniciando…';
  int    _msgIndex    = 0;

  final List<String> _loadingMsgs = [
    'Detectando tu ubicación…',
    'Preparando tu experiencia…',
    'Conectando con conductores…',
    'Casi listo…',
  ];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final prefs     = await SharedPreferences.getInstance();
    final firstTime = prefs.getBool('first_time') ?? true;
    if (firstTime) {
      await prefs.setBool('first_time', false);
      if (mounted) setState(() => _isFirstTime = true);
    }

    await _delay(100);
    _set(() { _logoOpacity = 1; _logoScale = 1.0; });
    await _delay(280);
    _set(() => _titleOpacity = 1);
    await _delay(160);
    _set(() => _subtitleOpacity = 1);
    await _delay(160);
    _set(() { _cardOpacity = 1; _cardOffset = 0; });
    await _delay(200);
    _set(() => _loaderOpacity = 1);

    _rotateMsgs();

    await Future.wait([
      Future.delayed(Duration(
          milliseconds: _isFirstTime ? 2600 : 1600)),
      ref.read(authProvider.notifier).checkAuth(),
    ]);

    if (!mounted) return;
    final auth = ref.read(authProvider);

    // No autenticado → login
    if (!auth.isAuthenticated) {
      context.go('/login');
      return;
    }

    // Cliente → home directo
    if (auth.user?.role != 'driver') {
      context.go('/client');
      return;
    }

    // Conductor → verificar estado antes de entrar
    _set(() => _loadingText = 'Verificando tu cuenta…');
    try {
      final driver = await DriverOnboardingService().getMyDriver();
      if (!mounted) return;
      context.go(driver.isApproved ? '/driver' : '/driver/onboarding');
    } catch (_) {
      if (mounted) context.go('/driver/onboarding');
    }
  }

  Future<void> _delay(int ms) =>
      Future.delayed(Duration(milliseconds: ms));

  void _set(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _rotateMsgs() async {
    await _delay(500);
    for (final msg in _loadingMsgs) {
      if (!mounted) return;
      setState(() { _loadingText = msg; _msgIndex++; });
      await _delay(550);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: size.height,
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [

                    AnimatedOpacity(
                      opacity:  _logoOpacity,
                      duration: const Duration(milliseconds: 300),
                      curve:    Curves.easeOut,
                      child: AnimatedScale(
                        scale:    _logoScale,
                        duration: const Duration(milliseconds: 350),
                        curve:    Curves.easeOutBack,
                        child: Container(
                          width: 84, height: 84,
                          decoration: BoxDecoration(
                            color: Colors.white
                                .withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white
                                  .withValues(alpha: 0.18),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.local_shipping_rounded,
                            size: 44, color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    AnimatedOpacity(
                      opacity:  _titleOpacity,
                      duration: const Duration(milliseconds: 280),
                      curve:    Curves.easeOut,
                      child: const Text('FleteApp',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          )),
                    ),
                    const SizedBox(height: 8),

                    AnimatedOpacity(
                      opacity:  _subtitleOpacity,
                      duration: const Duration(milliseconds: 260),
                      curve:    Curves.easeOut,
                      child: Column(children: [
                        const Text(
                          'Pide tu flete en minutos 🚚',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Rápido, seguro y sin complicaciones',
                          style: TextStyle(
                            color: Colors.white
                                .withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 28),

                    AnimatedOpacity(
                      opacity:  _cardOpacity,
                      duration: const Duration(milliseconds: 280),
                      curve:    Curves.easeOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve:    Curves.easeOut,
                        transform: Matrix4.translationValues(
                            0, _cardOffset, 0),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 36),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white
                                .withValues(alpha: 0.12),
                            width: 0.5,
                          ),
                        ),
                        child: Column(children: [
                          _Step(
                            icon: Icons.touch_app_rounded,
                            text: 'Solicita un flete',
                          ),
                          const SizedBox(height: 7),
                          _Step(
                            icon: Icons.person_pin_circle_rounded,
                            text: 'Un conductor acepta',
                          ),
                          const SizedBox(height: 7),
                          _Step(
                            icon: Icons.track_changes_rounded,
                            text: 'Sigue tu envío en vivo',
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),

              AnimatedOpacity(
                opacity:  _loaderOpacity,
                duration: const Duration(milliseconds: 280),
                curve:    Curves.easeInOut,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 1.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AnimatedSwitcher(
                        duration: const Duration(
                            milliseconds: 280),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(
                                opacity: anim, child: child),
                        child: Text(
                          _loadingText,
                          key: ValueKey('$_msgIndex-$_loadingText'),
                          style: TextStyle(
                            color: Colors.white
                                .withValues(alpha: 0.45),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
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

class _Step extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Step({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon,
          size: 12,
          color: Colors.white.withValues(alpha: 0.55)),
      const SizedBox(width: 8),
      Text(text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 12,
          )),
    ],
  );
}