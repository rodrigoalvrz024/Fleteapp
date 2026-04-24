import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
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
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#f5f5f5"}]}
]
''';

class _SavedPlace {
  final String label;
  final String address;
  final LatLng latLng;
  final IconData icon;

  const _SavedPlace({
    required this.label,
    required this.address,
    required this.latLng,
    required this.icon,
  });

  Map<String, dynamic> toJson() => {
    'label':   label,
    'address': address,
    'lat':     latLng.latitude,
    'lng':     latLng.longitude,
  };

  factory _SavedPlace.fromJson(Map<String, dynamic> j) => _SavedPlace(
    label:   j['label'],
    address: j['address'],
    latLng:  LatLng(j['lat'], j['lng']),
    icon:    Icons.history_rounded,
  );
}

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});
  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen>
    with TickerProviderStateMixin {

  GoogleMapController? _mapCtrl;
  LatLng _currentPos     = const LatLng(-33.4489, -70.6693);
  Set<Marker> _markers   = {};
  String _currentAddress = 'Obteniendo ubicación...';

  final _searchCtrl  = TextEditingController();
  final _searchFocus = FocusNode();
  bool _isSearching  = false;

  late DraggableScrollableController _sheetCtrl;
  double _sheetSize   = 0.28;
  bool _headerVisible = true;

  late AnimationController _headerCtrl;
  late Animation<double>   _headerFade;
  late Animation<Offset>   _headerSlide;
  late AnimationController _btnCtrl;
  late Animation<double>   _btnScale;
  late AnimationController _sheetEntryCtrl;
  late Animation<double>   _sheetEntry;

  List<_SavedPlace> _recents = [];

  static const double _snapMin = 0.28;
  static const double _snapMax = 0.88;

  final List<_SavedPlace> _defaultPlaces = const [
    _SavedPlace(
      label:   'Oficina',
      address: 'Av. Providencia 1234, Providencia',
      latLng:  LatLng(-33.4319, -70.6108),
      icon:    Icons.work_outline_rounded,
    ),
    _SavedPlace(
      label:   'Casa',
      address: 'Lo Barnechea, Santiago',
      latLng:  LatLng(-33.3516, -70.5150),
      icon:    Icons.home_outlined,
    ),
    _SavedPlace(
      label:   'Bodega',
      address: 'Pudahuel, Santiago',
      latLng:  LatLng(-33.4430, -70.7575),
      icon:    Icons.warehouse_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _sheetCtrl = DraggableScrollableController();
    _sheetCtrl.addListener(_onSheetChanged);

    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _headerFade  = CurvedAnimation(
        parent: _headerCtrl, curve: Curves.easeInOut);
    _headerSlide = Tween<Offset>(
        begin: Offset.zero, end: const Offset(0, -1))
        .animate(CurvedAnimation(
            parent: _headerCtrl, curve: Curves.easeInOut));

    _btnCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 130));
    _btnScale = Tween(begin: 1.0, end: 0.96).animate(
        CurvedAnimation(parent: _btnCtrl, curve: Curves.easeOut));

    _sheetEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _sheetEntry = CurvedAnimation(
        parent: _sheetEntryCtrl, curve: Curves.easeOutCubic);
    _sheetEntryCtrl.forward();

    _searchFocus.addListener(() {
      setState(() => _isSearching = _searchFocus.hasFocus);
      if (_searchFocus.hasFocus) _expandSheet();
    });

    _loadRecents();
    _requestLocation();
  }

  @override
  void dispose() {
    _sheetCtrl.removeListener(_onSheetChanged);
    _sheetCtrl.dispose();
    _headerCtrl.dispose();
    _btnCtrl.dispose();
    _sheetEntryCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('recent_places') ?? [];
      setState(() {
        _recents = stored
            .map((s) => _SavedPlace.fromJson(jsonDecode(s)))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _saveRecent(_SavedPlace place) async {
    try {
      final updated = [
        place,
        ..._recents.where((p) => p.address != place.address),
      ].take(5).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'recent_places',
        updated.map((p) => jsonEncode(p.toJson())).toList(),
      );
      setState(() => _recents = updated);
    } catch (_) {}
  }

  Future<void> _requestLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      setState(() => _currentAddress = 'Permiso denegado');
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final ll = LatLng(pos.latitude, pos.longitude);

      String address = 'Mi ubicación';
      try {
        final marks = await placemarkFromCoordinates(
            pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          final parts = [
            if (p.street?.isNotEmpty ?? false) p.street,
            if (p.subLocality?.isNotEmpty ?? false) p.subLocality,
            if (p.locality?.isNotEmpty ?? false) p.locality,
          ].whereType<String>().toList();
          if (parts.isNotEmpty) address = parts.join(', ');
        }
      } catch (_) {}

      setState(() {
        _currentPos     = ll;
        _currentAddress = address;
        _markers = {
          Marker(
            markerId: const MarkerId('me'),
            position: ll,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(title: address),
          ),
        };
      });
      await _mapCtrl?.animateCamera(
          CameraUpdate.newLatLngZoom(ll, 15));
    } catch (_) {
      setState(() => _currentAddress = 'No se pudo obtener ubicación');
    }
  }

  void _onSheetChanged() {
    final s = _sheetCtrl.size;
    setState(() => _sheetSize = s);
    if (s > 0.42 && _headerVisible) {
      setState(() => _headerVisible = false);
      _headerCtrl.forward();
    } else if (s <= 0.42 && !_headerVisible) {
      setState(() => _headerVisible = true);
      _headerCtrl.reverse();
    }
  }

  void _expandSheet() => _sheetCtrl.animateTo(
      0.88,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut);

  void _collapseSheet() {
    _searchFocus.unfocus();
    _sheetCtrl.animateTo(
        _snapMin,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut);
  }

  void _goToMyLocation() {
    HapticFeedback.lightImpact();
    _mapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(_currentPos, 15));
  }

  void _navigateToCreate({
    String destAddress = '',
    double? destLat,
    double? destLng,
    String originAddress = '',
    double? originLat,
    double? originLng,
  }) {
    HapticFeedback.mediumImpact();
    final uri = Uri(
      path: '/client/create-freight',
      queryParameters: {
        if (destAddress.isNotEmpty)   'dest_address':   destAddress,
        if (destLat != null)          'dest_lat':       destLat.toString(),
        if (destLng != null)          'dest_lng':       destLng.toString(),
        if (originAddress.isNotEmpty) 'origin_address': originAddress,
        if (originLat != null)        'origin_lat':     originLat.toString(),
        if (originLng != null)        'origin_lng':     originLng.toString(),
      },
    );
    context.push(uri.toString());
  }

  void _onSolicitar() {
    final address = _searchCtrl.text.trim();
    _navigateToCreate(
      destAddress:   address,
      originAddress: _currentAddress,
      originLat:     _currentPos.latitude,
      originLng:     _currentPos.longitude,
    );
  }

  void _selectPlace(_SavedPlace place) {
    HapticFeedback.lightImpact();
    _searchCtrl.text = place.address;
    _searchFocus.unfocus();
    _saveRecent(place);
    _mapCtrl?.animateCamera(
        CameraUpdate.newLatLngZoom(place.latLng, 15));
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('dest'),
          position: place.latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: place.label),
        ),
        if (_markers.any((m) => m.markerId.value == 'me'))
          _markers.firstWhere((m) => m.markerId.value == 'me'),
      };
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _navigateToCreate(
        destAddress:   place.address,
        destLat:       place.latLng.latitude,
        destLng:       place.latLng.longitude,
        originAddress: _currentAddress,
        originLat:     _currentPos.latitude,
        originLng:     _currentPos.longitude,
      );
    });
  }

  // ── Menú de perfil ─────────────────────────────────────
  void _showProfileMenu() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProfileMenu(
        onProfile:   () { Navigator.pop(context); context.push('/profile'); },
        onFreights:  () { Navigator.pop(context); context.push('/client/freights'); },
        onAddresses: () { Navigator.pop(context); context.push('/profile'); },
        onLogout: () async {
          Navigator.pop(context);
          await ref.read(authProvider.notifier).logout();
          if (mounted) context.go('/login');
        },
      ),
    );
  }

  bool get _isNight {
    final h = DateTime.now().hour;
    return h < 8 || h >= 21;
  }

  List<_SavedPlace> get _displayRecents =>
      _recents.isEmpty ? _defaultPlaces : _recents;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final name = user?.fullName.split(' ').first ?? 'Cliente';
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [

            // ── Mapa ────────────────────────────────────
            GoogleMap(
              initialCameraPosition: CameraPosition(
                  target: _currentPos, zoom: 14),
              onMapCreated: (c) async {
                _mapCtrl = c;
                await c.setMapStyle(_mapStyle);
              },
              onCameraMoveStarted: () {
                if (_isSearching) _searchFocus.unfocus();
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
                      padding: const EdgeInsets.fromLTRB(
                          16, 10, 16, 0),
                      child: Row(children: [

                        // Pill de saludo
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(50),
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
                              Expanded(
                                child: Text('Hola, $name',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.midnight,
                                    ),
                                    overflow:
                                        TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '· $_currentAddress',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.slate400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Botón perfil — único
                        GestureDetector(
                          onTap: _showProfileMenu,
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
                                Icons.person_outline_rounded,
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

            // ── Botón mi ubicación ────────────────────────
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
                        color: Colors.black
                            .withValues(alpha: 0.09),
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
                snapSizes:        const [_snapMin, 0.52, _snapMax],
                builder: (ctx, scroll) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: 0.10),
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
                            borderRadius:
                                BorderRadius.circular(2),
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

                            // Input búsqueda
                            _SearchInput(
                              controller: _searchCtrl,
                              focusNode:  _searchFocus,
                              onChanged:  (v) => setState(() {}),
                              onClear: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 14),

                            // CTA solicitar flete
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
                                child: Container(
                                  height: 54,
                                  decoration: BoxDecoration(
                                    gradient:
                                        const LinearGradient(
                                      colors: [
                                        Color(0xFF4F94F8),
                                        Color(0xFF2563EB),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF2563EB)
                                            .withValues(alpha: 0.28),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                          Icons.local_shipping_rounded,
                                          color: Colors.white,
                                          size: 20),
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
                            const SizedBox(height: 20),

                            // Banner urgente / nocturno
                            if (_isNight)
                              _InfoRow(
                                icon:   Icons.nightlight_round,
                                color:  Colors.deepPurple.shade300,
                                bg:     const Color(0xFF1E1B4B)
                                    .withValues(alpha: 0.05),
                                border: Colors.deepPurple
                                    .withValues(alpha: 0.15),
                                text:   'Tarifa nocturna · Mínimo \$40.000',
                                onTap:  _onSolicitar,
                              )
                            else
                              _InfoRow(
                                icon:   Icons.flash_on_rounded,
                                color:  AppTheme.urgent,
                                bg:     const Color(0xFFFFF7ED),
                                border: AppTheme.urgent
                                    .withValues(alpha: 0.2),
                                text:   'Modo urgente · Mínimo \$30.000',
                                onTap:  _onSolicitar,
                              ),
                            const SizedBox(height: 22),

                            // Ubicación actual
                            _LocationCurrentTile(
                              address: _currentAddress,
                              onTap: () {
                                _searchCtrl.text = _currentAddress;
                                _mapCtrl?.animateCamera(
                                  CameraUpdate.newLatLngZoom(
                                      _currentPos, 15),
                                );
                                _collapseSheet();
                              },
                            ),
                            const SizedBox(height: 16),

                            // Recientes
                            const _Label('Recientes'),
                            const SizedBox(height: 10),
                            ..._displayRecents.map((d) =>
                                _RecentTile(
                                  place: d,
                                  onTap: () => _selectPlace(d),
                                )),
                            const SizedBox(height: 22),

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

// ── Menú de perfil (bottom sheet) ──────────────────────────

class _ProfileMenu extends ConsumerWidget {
  final VoidCallback onProfile;
  final VoidCallback onFreights;
  final VoidCallback onAddresses;
  final VoidCallback onLogout;

  const _ProfileMenu({
    required this.onProfile,
    required this.onFreights,
    required this.onAddresses,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user     = ref.watch(authProvider).user;
    final name     = user?.fullName ?? 'Usuario';
    final email    = user?.email ?? '';
    final initials = name.trim().split(' ')
        .take(2).map((w) => w[0].toUpperCase()).join();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20,
          MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.slate200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Avatar + info + botón editar
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(initials,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    )),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.midnight,
                      )),
                  Text(email,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate400,
                      )),
                ],
              ),
            ),
            GestureDetector(
              onTap: onProfile,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Editar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primary,
                    )),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Container(height: 0.5, color: AppTheme.slate200),
          const SizedBox(height: 8),

          // Opciones
          _MenuOption(
            icon:  Icons.receipt_long_outlined,
            label: 'Mis fletes',
            sub:   'Ver historial de solicitudes',
            onTap: onFreights,
          ),
          _MenuOption(
            icon:  Icons.location_on_outlined,
            label: 'Mis direcciones',
            sub:   'Casa, trabajo y más',
            onTap: onAddresses,
          ),
          _MenuOption(
            icon:  Icons.person_outline_rounded,
            label: 'Mi perfil',
            sub:   'Datos personales y cuenta',
            onTap: onProfile,
          ),
          const SizedBox(height: 8),

          // Cerrar sesión
          GestureDetector(
            onTap: onLogout,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded,
                      size: 16, color: AppTheme.error),
                  SizedBox(width: 8),
                  Text('Cerrar sesión',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.error,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  const _MenuOption({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 12, horizontal: 4),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppTheme.slate100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppTheme.slate600),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.midnight,
                  )),
              Text(sub,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate400,
                  )),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded,
            size: 16, color: AppTheme.slate400),
      ]),
    ),
  );
}

// ── Widgets del bottom sheet ────────────────────────────────

class _SearchInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchInput({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF4F6F8),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: const Color(0xFFDDE3EC), width: 0.8),
    ),
    child: TextField(
      controller:      controller,
      focusNode:       focusNode,
      onChanged:       onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(
          fontSize: 15, color: AppTheme.midnight),
      decoration: InputDecoration(
        hintText: '¿A dónde va el flete?',
        hintStyle: const TextStyle(
            fontSize: 15, color: AppTheme.slate400),
        prefixIcon: Container(
          margin: const EdgeInsets.all(10),
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.location_on_rounded,
              size: 13, color: AppTheme.primary),
        ),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 16, color: AppTheme.slate400),
                onPressed: onClear,
              )
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 16),
      ),
    ),
  );
}

class _LocationCurrentTile extends StatelessWidget {
  final String address;
  final VoidCallback onTap;
  const _LocationCurrentTile(
      {required this.address, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.my_location_rounded,
              size: 18, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mi ubicación actual',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.midnight,
                  )),
              Text(address,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const Icon(Icons.north_west_rounded,
            size: 13, color: AppTheme.primary),
      ]),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color, bg, border;
  final String text;
  final VoidCallback onTap;
  const _InfoRow({
    required this.icon,
    required this.color,
    required this.bg,
    required this.border,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color))),
        Icon(Icons.chevron_right_rounded,
            size: 14, color: color),
      ]),
    ),
  );
}

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

class _RecentTile extends StatelessWidget {
  final _SavedPlace place;
  final VoidCallback onTap;
  const _RecentTile({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: 10, horizontal: 4),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(place.icon,
                size: 17, color: AppTheme.slate600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(place.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.midnight,
                    )),
                Text(place.address,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slate400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Icon(Icons.north_west_rounded,
              size: 13, color: AppTheme.slate400),
        ]),
      ),
    ),
  );
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();
  @override
  Widget build(BuildContext context) => const Row(children: [
    _Step(Icons.pin_drop_outlined,            'Marca\norigen y destino'),
    _Arrow(),
    _Step(Icons.local_shipping_outlined,      'Conductor\nacepta'),
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