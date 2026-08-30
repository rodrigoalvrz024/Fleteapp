import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/place_suggestion.dart';
import '../../services/places_service.dart';
import '../../widgets/muvv_mobile_ui.dart';
import 'package:uuid/uuid.dart';

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
        'label': label,
        'address': address,
        'lat': latLng.latitude,
        'lng': latLng.longitude,
      };

  factory _SavedPlace.fromJson(Map<String, dynamic> j) => _SavedPlace(
        label: j['label'],
        address: j['address'],
        latLng: LatLng(j['lat'], j['lng']),
        icon: Icons.history_rounded,
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
  LatLng _currentPos = const LatLng(-33.4489, -70.6693);
  Set<Marker> _markers = {};
  Set<Circle> _locationHalo = {};
  bool _locationLoading = true;
  String _currentAddress = 'Obteniendo ubicación...';

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _placesService = PlacesService();
  bool _isSearching = false;
  Timer? _suggestionDebounce;
  List<PlaceSuggestion> _placeSuggestions = const [];
  bool _loadingSuggestions = false;
  int _suggestionRequest = 0;
  String _placesSessionToken = const Uuid().v4();

  late DraggableScrollableController _sheetCtrl;
  double _sheetSize = 0.44;
  bool _headerVisible = true;
  String? _selectedService;
  bool _isInitializingHome = true;

  late AnimationController _headerCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late AnimationController _sheetEntryCtrl;
  late Animation<double> _sheetEntry;

  List<_SavedPlace> _recents = [];

  static const double _snapMin = 0.44;
  static const double _snapMiddle = 0.68;
  static const double _snapMax = 0.92;

  @override
  void initState() {
    super.initState();

    _sheetCtrl = DraggableScrollableController();
    _sheetCtrl.addListener(_onSheetChanged);

    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeInOut);
    _headerSlide = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -1))
        .animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeInOut));

    _sheetEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _sheetEntry =
        CurvedAnimation(parent: _sheetEntryCtrl, curve: Curves.easeOutCubic);
    _sheetEntryCtrl.forward();

    // Start on the compact map-first state even if a previous focused field
    // causes Flutter to restore the scrollable sheet at a larger snap point.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 220), () {
        if (mounted && _sheetCtrl.isAttached) {
          _searchFocus.unfocus();
          _sheetCtrl.animateTo(
            _snapMin,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _isInitializingHome = false;
        });
      });
    });

    _searchFocus.addListener(() {
      setState(() => _isSearching = _searchFocus.hasFocus);
      if (_searchFocus.hasFocus && !_isInitializingHome) _expandSheet();
    });

    _loadRecents();
    _requestLocation();
  }

  @override
  void dispose() {
    _sheetCtrl.removeListener(_onSheetChanged);
    _sheetCtrl.dispose();
    _headerCtrl.dispose();
    _sheetEntryCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _suggestionDebounce?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('recent_places') ?? [];
      setState(() {
        _recents =
            stored.map((s) => _SavedPlace.fromJson(jsonDecode(s))).toList();
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
      setState(() => _locationLoading = false);
      setState(() => _currentAddress = 'Permiso denegado');
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final ll = LatLng(pos.latitude, pos.longitude);

      const address = 'Mi ubicación actual';

      setState(() {
        _currentPos = ll;
        _currentAddress = address;
        _markers = {
          Marker(
            markerId: const MarkerId('me'),
            position: ll,
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
            infoWindow: const InfoWindow(title: address),
          ),
        };
        _locationHalo = {
          Circle(
            circleId: const CircleId('muvv-location-halo'),
            center: ll,
            radius: 115,
            fillColor: AppTheme.primary.withValues(alpha: 0.12),
            strokeColor: AppTheme.primary.withValues(alpha: 0.25),
            strokeWidth: 1,
          ),
        };
        _locationLoading = false;
      });
      await _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(ll, 15));
    } catch (_) {
      setState(() => _locationLoading = false);
      setState(() => _currentAddress = 'No se pudo obtener ubicación');
    }
  }

  void _onSheetChanged() {
    final s = _sheetCtrl.size;
    final shouldShowHeader = s <= 0.72;
    final needsSizeUpdate = (_sheetSize - s).abs() > 0.002;
    final headerChanged = _headerVisible != shouldShowHeader;
    if (needsSizeUpdate || headerChanged) {
      setState(() {
        _sheetSize = s;
        _headerVisible = shouldShowHeader;
      });
    }
    if (!shouldShowHeader && headerChanged) {
      _headerCtrl.forward();
    } else if (shouldShowHeader && headerChanged) {
      _headerCtrl.reverse();
    }
  }

  void _expandSheet() => _sheetCtrl.animateTo(_snapMax,
      duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic);

  void _collapseSheet() {
    _searchFocus.unfocus();
    _sheetCtrl.animateTo(_snapMin,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic);
  }

  void _goToMyLocation() {
    HapticFeedback.lightImpact();
    _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(_currentPos, 15));
  }

  void _navigateToCreate({
    String destAddress = '',
    double? destLat,
    double? destLng,
    String originAddress = '',
    double? originLat,
    double? originLng,
    bool urgent = false,
  }) {
    HapticFeedback.mediumImpact();
    final uri = Uri(
      path: '/app/client/create-freight',
      queryParameters: {
        if (destAddress.isNotEmpty) 'dest_address': destAddress,
        if (destLat != null) 'dest_lat': destLat.toString(),
        if (destLng != null) 'dest_lng': destLng.toString(),
        if (originAddress.isNotEmpty) 'origin_address': originAddress,
        if (originLat != null) 'origin_lat': originLat.toString(),
        if (originLng != null) 'origin_lng': originLng.toString(),
        if (_selectedServiceLabel != null) 'service': _selectedServiceLabel!,
        if (urgent) 'urgent': 'true',
      },
    );
    context.push(uri.toString());
  }

  String? get _selectedServiceLabel => switch (_selectedService) {
        'package' => 'Paquetería',
        'moving' => 'Mudanza',
        'home-office' => 'Hogar u oficina',
        'urgent' => 'Envío urgente',
        _ => null,
      };

  void _onSolicitar() {
    final address = _searchCtrl.text.trim();
    _navigateToCreate(
      destAddress: address,
      originAddress: _currentAddress,
      originLat: _currentPos.latitude,
      originLng: _currentPos.longitude,
    );
  }

  void _openOriginFlow() {
    _navigateToCreate(
      originAddress: _currentAddress,
      originLat: _currentPos.latitude,
      originLng: _currentPos.longitude,
    );
  }

  void _selectService(String service) {
    HapticFeedback.selectionClick();
    setState(() => _selectedService = service);
    _searchFocus.requestFocus();
  }

  void _openUrgentFlow() {
    _navigateToCreate(
      originAddress: _currentAddress,
      originLat: _currentPos.latitude,
      originLng: _currentPos.longitude,
      urgent: true,
    );
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    _suggestionDebounce?.cancel();
    final request = ++_suggestionRequest;
    if (query.length < 3) {
      setState(() {
        _placeSuggestions = const [];
        _loadingSuggestions = false;
      });
      return;
    }

    setState(() => _loadingSuggestions = true);
    _suggestionDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final suggestions = await _placesService.autocomplete(
          query,
          sessionToken: _placesSessionToken,
          latitude: _currentPos.latitude,
          longitude: _currentPos.longitude,
        );
        if (!mounted || request != _suggestionRequest) return;
        setState(() => _placeSuggestions = suggestions);
      } catch (_) {
        if (!mounted || request != _suggestionRequest) return;
        setState(() => _placeSuggestions = const []);
      } finally {
        if (mounted && request == _suggestionRequest) {
          setState(() => _loadingSuggestions = false);
        }
      }
    });
  }

  Future<void> _selectPlaceSuggestion(PlaceSuggestion suggestion) async {
    HapticFeedback.lightImpact();
    setState(() => _loadingSuggestions = true);
    try {
      final place = await _placesService.getAddress(
        suggestion.placeId,
        sessionToken: _placesSessionToken,
      );
      if (!mounted) return;
      final saved = _SavedPlace(
        label: suggestion.label,
        address: place.address,
        latLng: LatLng(place.latitude, place.longitude),
        icon: Icons.history_rounded,
      );
      _searchCtrl.text = place.address;
      _searchFocus.unfocus();
      _suggestionDebounce?.cancel();
      _placesSessionToken = const Uuid().v4();
      _saveRecent(saved);
      _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(saved.latLng, 15));
      setState(() {
        _placeSuggestions = const [];
        _markers = {
          Marker(
            markerId: const MarkerId('dest'),
            position: saved.latLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(title: saved.label),
          ),
          if (_markers.any((marker) => marker.markerId.value == 'me'))
            _markers.firstWhere((marker) => marker.markerId.value == 'me'),
        };
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _navigateToCreate(
        destAddress: saved.address,
        destLat: saved.latLng.latitude,
        destLng: saved.latLng.longitude,
        originAddress: _currentAddress,
        originLat: _currentPos.latitude,
        originLng: _currentPos.longitude,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos cargar esa direccion. Intenta otra vez.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  void _selectPlace(_SavedPlace place) {
    HapticFeedback.lightImpact();
    _searchCtrl.text = place.address;
    _searchFocus.unfocus();
    _saveRecent(place);
    _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(place.latLng, 15));
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('dest'),
          position: place.latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: place.label),
        ),
        if (_markers.any((m) => m.markerId.value == 'me'))
          _markers.firstWhere((m) => m.markerId.value == 'me'),
      };
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _navigateToCreate(
        destAddress: place.address,
        destLat: place.latLng.latitude,
        destLng: place.latLng.longitude,
        originAddress: _currentAddress,
        originLat: _currentPos.latitude,
        originLng: _currentPos.longitude,
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
        onProfile: () {
          Navigator.pop(context);
          context.push('/app/client/account');
        },
        onFreights: () {
          Navigator.pop(context);
          context.push('/app/client/freights');
        },
        onAddresses: () {
          Navigator.pop(context);
          context.push('/app/client/addresses');
        },
        onLogout: () async {
          Navigator.pop(context);
          await ref.read(authProvider.notifier).logout();
          if (mounted) context.go('/auth/login');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final name = user?.fullName.split(' ').first ?? 'Cliente';
    final size = MediaQuery.of(context).size;
    final desktop = size.width >= 900;
    final showExpandedContent = _sheetSize >= _snapMiddle - 0.01;
    final hasSearchQuery = _searchCtrl.text.trim().length >= 3;
    final showSuggestions = _isSearching && hasSearchQuery;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        resizeToAvoidBottomInset: false,
        bottomNavigationBar: desktop
            ? null
            : const MuvvBottomNavigation(
                selected: MuvvNavigationSection.home,
              ),
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentPos,
                zoom: 14.5,
              ),
              onMapCreated: (controller) {
                _mapCtrl = controller;
                _mapCtrl?.setMapStyle(_mapStyle);
              },
              onTap: (_) {
                _searchFocus.unfocus();
                if (_sheetSize > _snapMin) _collapseSheet();
              },
              markers: _markers,
              circles: _locationHalo,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              padding: EdgeInsets.only(
                left: desktop ? 460 : 0,
                bottom: desktop ? 0 : size.height * _sheetSize,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: ReverseAnimation(_headerFade),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: _MuvvMapHeader(
                        location: _currentAddress,
                        isLoading: _locationLoading,
                        onLocationTap: _openOriginFlow,
                        onProfileTap: _showProfileMenu,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              right: 16,
              bottom: desktop ? 28 : size.height * _sheetSize + 18,
              child: Semantics(
                button: true,
                label: 'Recentrar mi ubicación',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _goToMyLocation,
                    borderRadius: BorderRadius.circular(24),
                    child: Ink(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.slate200),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.midnight.withValues(alpha: 0.10),
                            blurRadius: 18,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.my_location_rounded,
                        size: 21,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(_sheetEntry),
              child: Align(
                alignment:
                    desktop ? Alignment.bottomLeft : Alignment.bottomCenter,
                child: SizedBox(
                  width: desktop ? 440 : double.infinity,
                  child: DraggableScrollableSheet(
                    controller: _sheetCtrl,
                    expand: !desktop,
                    initialChildSize: desktop ? 0.76 : _snapMin,
                    minChildSize: desktop ? 0.76 : _snapMin,
                    maxChildSize: desktop ? 0.76 : _snapMax,
                    snap: !desktop,
                    snapSizes: desktop
                        ? null
                        : const [_snapMin, _snapMiddle, _snapMax],
                    builder: (context, scrollController) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: desktop
                            ? const BorderRadius.only(
                                topRight: Radius.circular(28),
                              )
                            : const BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                        border: Border.all(
                          color: AppTheme.slate200.withValues(alpha: 0.9),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.midnight.withValues(alpha: 0.11),
                            blurRadius: 30,
                            offset: const Offset(0, -8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: desktop
                            ? const BorderRadius.only(
                                topRight: Radius.circular(28),
                              )
                            : const BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                        child: ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          physics: const ClampingScrollPhysics(),
                          children: [
                            Center(
                              child: Container(
                                margin:
                                    const EdgeInsets.only(top: 8, bottom: 5),
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppTheme.slate200,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _MuvvHomePanelHeader(
                                    name: name,
                                    onFreights: () =>
                                        context.push('/app/client/freights'),
                                  ),
                                  const SizedBox(height: 10),
                                  _MuvvOriginSelector(
                                    address: _currentAddress,
                                    isLoading: _locationLoading,
                                    onTap: _openOriginFlow,
                                  ),
                                  const SizedBox(height: 8),
                                  _MuvvDestinationField(
                                    controller: _searchCtrl,
                                    focusNode: _searchFocus,
                                    onChanged: _onSearchChanged,
                                    onClear: () {
                                      _searchCtrl.clear();
                                      _onSearchChanged('');
                                    },
                                  ),
                                  if (showSuggestions) ...[
                                    const SizedBox(height: 9),
                                    _PlaceSuggestions(
                                      suggestions: _placeSuggestions,
                                      isLoading: _loadingSuggestions,
                                      onSelected: _selectPlaceSuggestion,
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  MuvvGradientButton(
                                    label: _searchCtrl.text.trim().isEmpty
                                        ? 'Solicitar un flete'
                                        : 'Calcular precio',
                                    icon: Icons.local_shipping_rounded,
                                    onPressed: _onSolicitar,
                                  ),
                                  if (!showSuggestions && !showExpandedContent)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: _MuvvCargoPickerPrompt(
                                        selected: _selectedService,
                                        onTap: _expandSheet,
                                      ),
                                    ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 260),
                                    curve: Curves.easeOutCubic,
                                    child: showSuggestions
                                        ? const SizedBox(height: 18)
                                        : showExpandedContent
                                            ? Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  const SizedBox(height: 24),
                                                  const Text(
                                                    '¿Qué necesitas mover?',
                                                    style: TextStyle(
                                                      color: AppTheme.midnight,
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  _MuvvServiceGrid(
                                                    selected: _selectedService,
                                                    onSelected: _selectService,
                                                  ),
                                                  const SizedBox(height: 18),
                                                  const _MuvvPriceHint(),
                                                  const SizedBox(height: 14),
                                                  _MuvvUrgentOption(
                                                    onTap: _openUrgentFlow,
                                                  ),
                                                  if (_recents.isNotEmpty) ...[
                                                    const SizedBox(height: 26),
                                                    const Text(
                                                      'Recientes',
                                                      style: TextStyle(
                                                        color:
                                                            AppTheme.midnight,
                                                        fontSize: 17,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    ..._recents.map(
                                                      (place) =>
                                                          _MuvvRecentPlaceTile(
                                                        place: place,
                                                        onTap: () =>
                                                            _selectPlace(place),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              )
                                            : const SizedBox(height: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

// ── Menú de perfil (bottom sheet) ──────────────────────────

class _MuvvMapHeader extends StatelessWidget {
  final String location;
  final bool isLoading;
  final VoidCallback onLocationTap;
  final VoidCallback onProfileTap;

  const _MuvvMapHeader({
    required this.location,
    required this.isLoading,
    required this.onLocationTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.slate200),
          boxShadow: [
            BoxShadow(
              color: AppTheme.midnight.withValues(alpha: 0.09),
              blurRadius: 20,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/branding/muvv-app-icon.png',
                width: 34,
                height: 34,
              ),
            ),
            const SizedBox(width: 9),
            const Text(
              'Muvv',
              style: TextStyle(
                color: AppTheme.midnight,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onLocationTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: AppTheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mi ubicación',
                                style: TextStyle(
                                  color: AppTheme.slate400,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                isLoading
                                    ? 'Obteniendo ubicación...'
                                    : location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.slate600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onProfileTap,
                borderRadius: BorderRadius.circular(20),
                child: Ink(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.slate100,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: AppTheme.midnight,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _MuvvHomePanelHeader extends StatelessWidget {
  final String name;
  final VoidCallback onFreights;

  const _MuvvHomePanelHeader({
    required this.name,
    required this.onFreights,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '¿Qué necesitas mover hoy?',
                  style: TextStyle(
                    color: AppTheme.midnight,
                    fontSize: 19,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Semantics(
            button: true,
            label: 'Ver mis fletes',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onFreights,
                borderRadius: BorderRadius.circular(13),
                child: Ink(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.14),
                    ),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class _MuvvOriginSelector extends StatelessWidget {
  final String address;
  final bool isLoading;
  final VoidCallback onTap;

  const _MuvvOriginSelector({
    required this.address,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.my_location_rounded,
                    color: AppTheme.success,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Desde',
                        style: TextStyle(
                          color: AppTheme.slate400,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLoading ? 'Obteniendo ubicación...' : address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.slate600,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.edit_location_alt_outlined,
                  color: AppTheme.slate400,
                  size: 19,
                ),
              ],
            ),
          ),
        ),
      );
}

class _MuvvDestinationField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _MuvvDestinationField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        textField: true,
        label: 'Destino del flete',
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.slate200),
            boxShadow: [
              BoxShadow(
                color: AppTheme.midnight.withValues(alpha: 0.035),
                blurRadius: 13,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(
              color: AppTheme.midnight,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: '¿A dónde llevamos tu carga?',
              hintStyle: const TextStyle(
                color: AppTheme.slate400,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: const Icon(
                Icons.location_on_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar destino',
                      onPressed: onClear,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppTheme.slate400,
                      ),
                    ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      );
}

class _MuvvServiceGrid extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;

  const _MuvvServiceGrid({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const services = [
      _MuvvServiceOption(
        id: 'package',
        label: 'Paquetería',
        icon: Icons.inventory_2_outlined,
      ),
      _MuvvServiceOption(
        id: 'moving',
        label: 'Mudanza',
        icon: Icons.local_shipping_outlined,
      ),
      _MuvvServiceOption(
        id: 'home-office',
        label: 'Hogar u oficina',
        icon: Icons.chair_outlined,
      ),
      _MuvvServiceOption(
        id: 'urgent',
        label: 'Envío urgente',
        icon: Icons.bolt_rounded,
        urgent: true,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.7,
      children: [
        for (final service in services)
          _MuvvServiceCard(
            service: service,
            selected: selected == service.id,
            onTap: () => onSelected(service.id),
          ),
      ],
    );
  }
}

class _MuvvCargoPickerPrompt extends StatelessWidget {
  final String? selected;
  final VoidCallback onTap;

  const _MuvvCargoPickerPrompt({
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.inventory_2_outlined,
      Icons.local_shipping_outlined,
      Icons.chair_outlined,
      Icons.bolt_rounded,
    ];
    final label = switch (selected) {
      'package' => 'Paquetería',
      'moving' => 'Mudanza',
      'home-office' => 'Hogar u oficina',
      'urgent' => 'Envío urgente',
      _ => 'Elige el tipo de carga',
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.slate100,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Row(
            children: [
              for (var index = 0; index < icons.length; index++) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: index == icons.length - 1
                        ? AppTheme.urgent.withValues(alpha: 0.10)
                        : AppTheme.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icons[index],
                    size: 16,
                    color: index == icons.length - 1
                        ? AppTheme.urgent
                        : AppTheme.primary,
                  ),
                ),
                if (index != icons.length - 1) const SizedBox(width: 5),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: AppTheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MuvvServiceOption {
  final String id;
  final String label;
  final IconData icon;
  final bool urgent;

  const _MuvvServiceOption({
    required this.id,
    required this.label,
    required this.icon,
    this.urgent = false,
  });
}

class _MuvvServiceCard extends StatelessWidget {
  final _MuvvServiceOption service;
  final bool selected;
  final VoidCallback onTap;

  const _MuvvServiceCard({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = service.urgent ? AppTheme.urgent : AppTheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.10) : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? color : AppTheme.slate200,
              width: selected ? 1.25 : 0.9,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(service.icon, color: color, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  service.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? color : AppTheme.slate600,
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
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

class _MuvvPriceHint extends StatelessWidget {
  const _MuvvPriceHint();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppTheme.primary,
              size: 15,
            ),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'El precio se calcula automáticamente al completar la solicitud.',
              style: TextStyle(
                color: AppTheme.slate600,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
}

class _MuvvUrgentOption extends StatelessWidget {
  final VoidCallback onTap;

  const _MuvvUrgentOption({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.urgent.withValues(alpha: 0.20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.urgent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: AppTheme.urgent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¿Lo necesitas ahora?',
                        style: TextStyle(
                          color: AppTheme.midnight,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Solicita un conductor con prioridad.',
                        style: TextStyle(
                          color: AppTheme.slate600,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Ver opción',
                  style: TextStyle(
                    color: AppTheme.urgent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _MuvvRecentPlaceTile extends StatelessWidget {
  final _SavedPlace place;
  final VoidCallback onTap;

  const _MuvvRecentPlaceTile({
    required this.place,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.slate100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    place.icon,
                    color: AppTheme.slate600,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.midnight,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        place.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.slate400,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.north_east_rounded,
                  color: AppTheme.slate400,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      );
}

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
    final user = ref.watch(authProvider).user;
    final name = user?.fullName ?? 'Usuario';
    final email = user?.email ?? '';
    final initials =
        name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
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
              width: 52,
              height: 52,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
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
            icon: Icons.receipt_long_outlined,
            label: 'Mis fletes',
            sub: 'Ver historial de solicitudes',
            onTap: onFreights,
          ),
          _MenuOption(
            icon: Icons.location_on_outlined,
            label: 'Mis direcciones',
            sub: 'Casa, trabajo y más',
            onTap: onAddresses,
          ),
          _MenuOption(
            icon: Icons.person_outline_rounded,
            label: 'Mi perfil',
            sub: 'Datos personales y cuenta',
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
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, size: 16, color: AppTheme.error),
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
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(8),
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

class _ClientPanelHeader extends StatelessWidget {
  final String name;
  final String address;
  final VoidCallback onFreights;

  const _ClientPanelHeader({
    required this.name,
    required this.address,
    required this.onFreights,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.midnight,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.my_location_rounded,
                      color: AppTheme.primary,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.slate600,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Mis fletes',
            child: IconButton(
              onPressed: onFreights,
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.background,
                foregroundColor: AppTheme.midnight,
                side: const BorderSide(color: AppTheme.slate200, width: 0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
            ),
          ),
        ],
      );
}

class _MobileClientPanelHeader extends StatelessWidget {
  final String name;
  final String address;
  final VoidCallback onFreights;

  const _MobileClientPanelHeader({
    required this.name,
    required this.address,
    required this.onFreights,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                'Hola, $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Tooltip(
              message: 'Mis fletes',
              child: IconButton(
                onPressed: onFreights,
                icon: const Icon(Icons.receipt_long_outlined),
                color: AppTheme.midnight,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Que necesitas mover hoy?',
            style: TextStyle(
              color: AppTheme.midnight,
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(
              Icons.my_location_rounded,
              color: AppTheme.success,
              size: 15,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.slate600,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ],
      );
}

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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDDE3EC), width: 0.8),
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 15, color: AppTheme.midnight),
          decoration: InputDecoration(
            hintText: 'A donde llevamos tu carga?',
            hintStyle: const TextStyle(fontSize: 15, color: AppTheme.slate400),
            prefixIcon: Container(
              margin: const EdgeInsets.all(10),
              width: 24,
              height: 24,
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      );
}

class _PlaceSuggestions extends StatelessWidget {
  final List<PlaceSuggestion> suggestions;
  final bool isLoading;
  final ValueChanged<PlaceSuggestion> onSelected;

  const _PlaceSuggestions({
    required this.suggestions,
    required this.isLoading,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && suggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.slate200, width: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var index = 0; index < suggestions.length; index++) ...[
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.location_on_outlined,
                color: AppTheme.primary,
              ),
              title: Text(
                suggestions[index].label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                suggestions[index].address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.slate400, fontSize: 12),
              ),
              onTap: () => onSelected(suggestions[index]),
            ),
            if (index < suggestions.length - 1)
              const Divider(height: 1, indent: 56),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Resultados de Google',
                style: TextStyle(color: AppTheme.slate400, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCurrentTile extends StatelessWidget {
  final String address;
  final VoidCallback onTap;
  const _LocationCurrentTile({required this.address, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.12),
              width: 0.5,
            ),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: 0.5),
          ),
          child: Row(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 10),
            Expanded(
                child:
                    Text(text, style: TextStyle(fontSize: 12, color: color))),
            Icon(Icons.chevron_right_rounded, size: 14, color: color),
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
        letterSpacing: 0,
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
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.slate100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(place.icon, size: 17, color: AppTheme.slate600),
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
        _Step(Icons.pin_drop_outlined, 'Marca\norigen y destino'),
        _Arrow(),
        _Step(Icons.local_shipping_outlined, 'Conductor\nacepta'),
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
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
