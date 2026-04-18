import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';

const String _mapStyle = '''
[
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#f8f8f8"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#e8e8e8"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#d4eaf7"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#f5f5f5"}]},
  {"featureType":"administrative","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]}
]
''';

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});
  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen>
    with TickerProviderStateMixin {

  // Mapa
  GoogleMapController? _mapCtrl;
  LatLng _currentPos   = const LatLng(-33.4489, -70.6693);
  Set<Marker> _markers = {};

  // Sheet
  late DraggableScrollableController _sheetCtrl;
  double _sheetSize = 0.28;

  // Animaciones
  late AnimationController _headerCtrl;
  late Animation<double>   _headerFade;
  late Animation<Offset>   _headerSlide;

  late AnimationController _btnCtrl;
  late Animation<double>   _btnScale;

  late AnimationController _sheetEntryCtrl;
  late Animation<double>   _sheetEntry;

  // Estado
  bool _headerVisible = true;
  bool _btnLoading    = false;

  static const double _snapMin = 0.28;
  static const double _snapMid = 0.50;
  static const double _snapMax = 0.88;

  final List<_Dest> _recents = [
    _Dest(Icons.work_outline_rounded,   'Oficina',  'Av. Providencia 1234'),
    _Dest(Icons.home_outlined,          'Casa',     'Lo Barnechea, Santiago'),
    _Dest(Icons.warehouse_outlined,     'Bodega',   'Pudahuel, Santiago'),
  ];

  @override
  void initState() {
    super.initState();

    _sheetCtrl = DraggableScrollableController();
    _sheetCtrl.addListener(_onSheetChanged);

    // Header
    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _headerFade = CurvedAnimation(
        parent: _headerCtrl, curve: Curves.easeInOut);
    _headerSlide = Tween<Offset>(
        begin: Offset.zero, end: const Offset(0, -1))
        .animate(CurvedAnimation(
            parent: _headerCtrl, curve: Curves.easeInOut));
    _headerCtrl.value = 0; // starts visible (reversed)

    // Botón
    _btnCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 130));
    _btnScale = Tween(begin: 1.0, end: 0.96).animate(
        CurvedAnimation(parent: _btnCtrl, curve: Curves.easeOut));

    // Sheet entry
    _sheetEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _sheetEntry = CurvedAnimation(
        parent: _sheetEntryCtrl, curve: Curves.easeOutCubic);
    _sheetEntryCtrl.forward();

    _requestLocation();
  }

  @override
  void dispose() {
    _sheetCtrl.removeListener(_onSheetChanged);
    _sheetCtrl.dispose();
    _headerCtrl.dispose();
    _btnCtrl.dispose();
    _sheetEntryCtrl.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  void _onSheetChanged() {
    final s = _sheetCtrl.size;
    setState(() => _sheetSize = s);

    if (s > 0.42 && _headerVisible) {
      setState(() => _headerVisible = false);
      _headerCtrl.forward(); // slide out
    } else if (s <= 0.42 && !_headerVisible) {
      setState(() => _headerVisible = true);
      _headerCtrl.reverse(); // slide in
    }
  }

  Future<void> _requestLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentPos = ll;
        _markers = {
          Marker(
            markerId: const MarkerId('me'),
            position: ll,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue),
          ),
        };
      });
      await _mapCtrl?.animateCamera(
          CameraUpdate.newLatLngZoom(ll, 15));
    } catch (_) {}
  }

  void _goToMyLocation() {
    HapticFeedback.lightImpact();
    _mapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(_currentPos, 15));
  }

  Future<void> _onSolicitar() async {
    HapticFeedback.mediumImpact();
    setState(() => _btnLoading = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _btnLoading = false);
    context.push('/client/create-freight');
  }

  bool get _isNight {
    final h = DateTime.now().hour;
    return h < 8 || h >= 21;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final name = user?.fullName.split(' ').first ?? 'Cliente';
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [

            // ── Mapa ────────────────────────────────────
            GoogleMap(
              initialCameraPosition: CameraPosition(
                  target: _currentPos, zoom: 14),
              onMapCreated: (c) async {
                _mapCtrl = c;
                await c.setMapStyle(_mapStyle);
                _requestLocation();
              },
              onCameraMoveStarted: () {
                if (_headerVisible) {
                  setState(() => _headerVisible = false);
                  _headerCtrl.forward();
                }
              },
              onCameraIdle: () {
                if (!_headerVisible && _sheetSize <= 0.42) {
                  setState(() => _headerVisible = true);
                  _headerCtrl.reverse();
                }
              },
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              padding: EdgeInsets.only(
                  bottom: size.height * _snapMin),
            ),

            // ── Header dinámico ──────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: ReverseAnimation(_headerFade),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Row(children: [

                        // Pill compacta
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(50),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.08),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(children: [
                              Container(
                                width: 26, height: 26,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                    Icons.local_shipping_rounded,
                                    size: 14,
                                    color: AppTheme.primary),
                              ),
                              const SizedBox(width: 8),
                              Text('Hola, $name',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.midnight,
                                  )),
                              const SizedBox(width: 4),
                              const Text('·',
                                  style: TextStyle(
                                      color: AppTheme.slate400)),
                              const SizedBox(width: 4),
                              const Text('FleteApp',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.slate400,
                                  )),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Mis fletes
                        GestureDetector(
                          onTap: () =>
                              context.push('/client/freights'),
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                                Icons.receipt_long_outlined,
                                size: 18,
                                color: AppTheme.midnight),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),

            // ── Botón ubicación ──────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              right: 16,
              bottom: size.height * _sheetSize + 12,
              child: GestureDetector(
                onTap: _goToMyLocation,
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.09),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.my_location_rounded,
                      size: 18, color: AppTheme.primary),
                ),
              ),
            ),

            // ── Bottom sheet ──────────────────────────────
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(_sheetEntry),
              child: DraggableScrollableSheet(
                controller:       _sheetCtrl,
                initialChildSize: _snapMin,
                minChildSize:     _snapMin,
                maxChildSize:     _snapMax,
                snap:             true,
                snapSizes:        const [_snapMin, _snapMid, _snapMax],
                builder: (ctx, scroll) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 28,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scroll,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    children: [

                      // Handle
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(
                              top: 10, bottom: 4),
                          width: 38, height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCDD5DF),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            20, 10, 20, 0),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [

                            // Input
                            _InputTile(onTap: _onSolicitar),
                            const SizedBox(height: 14),

                            // CTA
                            ScaleTransition(
                              scale: _btnScale,
                              child: GestureDetector(
                                onTapDown: (_) =>
                                    _btnCtrl.forward(),
                                onTapUp: (_) {
                                  _btnCtrl.reverse();
                                  _onSolicitar();
                                },
                                onTapCancel: () =>
                                    _btnCtrl.reverse(),
                                child: _PrimaryButton(
                                    loading: _btnLoading),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Banner urgente solo si aplica
                            if (_isNight) ...[
                              _NightBanner(onTap: _onSolicitar),
                              const SizedBox(height: 18),
                            ] else ...[
                              _UrgentRow(onTap: _onSolicitar),
                              const SizedBox(height: 18),
                            ],

                            // Recientes
                            const _Label('Recientes'),
                            const SizedBox(height: 10),
                            ..._recents.map((d) => _RecentTile(
                                dest: d, onTap: _onSolicitar)),
                            const SizedBox(height: 20),

                            // Cómo funciona
                            const _Label('Cómo funciona'),
                            const SizedBox(height: 12),
                            const _HowItWorks(),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ],
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

// ── Modelos ────────────────────────────────────────────────

class _Dest {
  final IconData icon;
  final String label, sub;
  const _Dest(this.icon, this.label, this.sub);
}

// ── Widgets ────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTheme.slate400,
        letterSpacing: 0.7,
      ));
}

class _InputTile extends StatelessWidget {
  final VoidCallback onTap;
  const _InputTile({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFDDE3EC),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.location_on_rounded,
              size: 13, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('¿A dónde va el flete?',
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.slate400,
              )),
        ),
        const Icon(Icons.arrow_forward_ios_rounded,
            size: 13, color: AppTheme.slate400),
      ]),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  final bool loading;
  const _PrimaryButton({required this.loading});

  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF4F94F8), Color(0xFF2563EB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF2563EB).withValues(alpha: 0.28),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: const Color(0xFF2563EB).withValues(alpha: 0.12),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withValues(alpha: 0.15),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        onTap: null,
        child: Center(
          child: loading
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_shipping_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text('Solicitar flete',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        )),
                  ],
                ),
        ),
      ),
    ),
  );
}

class _NightBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _NightBanner({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B4B).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.deepPurple.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(children: [
        Icon(Icons.nightlight_round,
            size: 15,
            color: Colors.deepPurple.shade300),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Tarifa nocturna activa · Mínimo \$40.000',
            style: TextStyle(
              fontSize: 12,
              color: Colors.deepPurple.shade400,
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded,
            size: 14,
            color: Colors.deepPurple.shade300),
      ]),
    ),
  );
}

class _UrgentRow extends StatelessWidget {
  final VoidCallback onTap;
  const _UrgentRow({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.urgent.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(children: [
        Icon(Icons.flash_on_rounded,
            size: 15, color: AppTheme.urgent),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Modo urgente disponible · Mínimo \$30.000',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFB45309),
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded,
            size: 14, color: AppTheme.urgent),
      ]),
    ),
  );
}

class _RecentTile extends StatelessWidget {
  final _Dest dest;
  final VoidCallback onTap;
  const _RecentTile({required this.dest, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppTheme.slate100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(dest.icon,
              size: 17, color: AppTheme.slate600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dest.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.midnight,
                  )),
              Text(dest.sub,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slate400,
                  )),
            ],
          ),
        ),
        const Icon(Icons.north_west_rounded,
            size: 13, color: AppTheme.slate400),
      ]),
    ),
  );
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) => const Row(children: [
    _Step(Icons.pin_drop_outlined,          'Marca\norigen y destino'),
    _Arrow(),
    _Step(Icons.local_shipping_outlined,    'Conductor\nacepta'),
    _Arrow(),
    _Step(Icons.check_circle_outline_rounded, 'Entrega\nconfirmada'),
  ]);
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Step(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 19, color: AppTheme.primary),
      ),
      const SizedBox(height: 7),
      Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            color: AppTheme.slate400,
            height: 1.4,
          )),
    ]),
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 18),
    child: Icon(Icons.arrow_forward_rounded,
        size: 12, color: AppTheme.slate400),
  );
}