import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../services/freight_service.dart';
import '../../services/api_service.dart';
import '../../core/theme/app_theme.dart';

class CreateFreightScreen extends StatefulWidget {
  final String? destAddress;
  final double? destLat;
  final double? destLng;
  final String? originAddress;
  final double? originLat;
  final double? originLng;

  const CreateFreightScreen({
    super.key,
    this.destAddress,
    this.destLat,
    this.destLng,
    this.originAddress,
    this.originLat,
    this.originLng,
  });

  @override
  State<CreateFreightScreen> createState() => _CreateFreightScreenState();
}

class _CreateFreightScreenState extends State<CreateFreightScreen>
    with SingleTickerProviderStateMixin {

  final _formKey        = GlobalKey<FormState>();
  final _freightService = FreightService();
  final _api            = ApiService();

  final _cargoCtrl  = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _originCtrl = TextEditingController(text: 'Santiago Centro');
  final _destCtrl   = TextEditingController(text: 'Las Condes');

  // Mapa
  GoogleMapController? _mapController;
  LatLng? _originLatLng = const LatLng(-33.4489, -70.6693);
  LatLng? _destLatLng   = const LatLng(-33.4700, -70.6500);
  bool _selectingOrigin = true;
  Set<Marker>   _markers   = {};
  Set<Polyline> _polylines = {};
  bool _showMap = false;

  // Modo
  bool _isUrgent = false;
  late TabController _modeTab;

  // Programado
  DateTime?  _scheduledDate;
  TimeOfDay? _scheduledTime;

  // Peonetas
  int _helpers = 0;

  // Estado
  bool   _loading    = false;
  bool   _estimating = false;
  String? _error;

  // Precio
  double? _clientPays;
  double? _driverReceives;
  double? _distanceKm;
  String? _durationText;

  static const LatLng _santiago = LatLng(-33.4489, -70.6693);

  @override
  void initState() {
    super.initState();
    _modeTab = TabController(length: 2, vsync: this);
    _modeTab.addListener(() {
      if (_modeTab.indexIsChanging) return;
      setState(() {
        _isUrgent = _modeTab.index == 1;
        _clientPays = null;
        _scheduledDate = null;
        _scheduledTime = null;
      });
      _estimatePrice();
    });
    _initMarkers();
    _requestLocation();
    // Pre-llenar destino si viene del home
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.destAddress?.isNotEmpty ?? false) {
        _destCtrl.text = widget.destAddress!;
      }
      if (widget.destLat != null && widget.destLng != null) {
        setState(() {
          _destLatLng = LatLng(widget.destLat!, widget.destLng!);
        });
      }
      if (widget.originAddress?.isNotEmpty ?? false) {
        _originCtrl.text = widget.originAddress!;
      }
      if (widget.originLat != null && widget.originLng != null) {
        setState(() {
          _originLatLng = LatLng(widget.originLat!, widget.originLng!);
        });
      }
      _initMarkers();
      _estimatePrice();
    });
  }

  @override
  void dispose() {
    _modeTab.dispose();
    _cargoCtrl.dispose();
    _weightCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _initMarkers() {
    _markers = {
      if (_originLatLng != null) Marker(
        markerId: const MarkerId('origin'),
        position: _originLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Origen'),
      ),
      if (_destLatLng != null) Marker(
        markerId: const MarkerId('dest'),
        position: _destLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destino'),
      ),
    };
    if (_originLatLng != null && _destLatLng != null) {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          color: AppTheme.primary,
          width: 3,
          points: [_originLatLng!, _destLatLng!],
        ),
      };
    }
  }

  Future<void> _requestLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        setState(() {
          _originLatLng = LatLng(pos.latitude, pos.longitude);
          _originCtrl.text =
              'Lat: ${pos.latitude.toStringAsFixed(4)}, '
              'Lng: ${pos.longitude.toStringAsFixed(4)}';
        });
        _initMarkers();
        _estimatePrice();
      } catch (_) {}
    }
    _estimatePrice();
  }

  void _onMapTap(LatLng tapped) {
    setState(() {
      if (_selectingOrigin) {
        _originLatLng = tapped;
        _originCtrl.text =
            'Lat: ${tapped.latitude.toStringAsFixed(4)}, '
            'Lng: ${tapped.longitude.toStringAsFixed(4)}';
      } else {
        _destLatLng = tapped;
        _destCtrl.text =
            'Lat: ${tapped.latitude.toStringAsFixed(4)}, '
            'Lng: ${tapped.longitude.toStringAsFixed(4)}';
      }
      _initMarkers();
    });
    if (_originLatLng != null && _destLatLng != null) {
      _estimatePrice();
    }
  }

  Future<void> _estimatePrice() async {
    if (_originLatLng == null || _destLatLng == null) return;
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) return;

    setState(() => _estimating = true);
    try {
      DateTime? scheduledAt;
      if (!_isUrgent &&
          _scheduledDate != null &&
          _scheduledTime != null) {
        scheduledAt = DateTime(
          _scheduledDate!.year, _scheduledDate!.month,
          _scheduledDate!.day, _scheduledTime!.hour,
          _scheduledTime!.minute,
        );
      }
      final res = await _api.get('/freights/estimate', params: {
        'origin_lat':       _originLatLng!.latitude,
        'origin_lng':       _originLatLng!.longitude,
        'destination_lat':  _destLatLng!.latitude,
        'destination_lng':  _destLatLng!.longitude,
        'cargo_weight_kg':  weight,
        'requires_helpers': _helpers,
        'is_urgent':        _isUrgent,
        if (scheduledAt != null)
          'scheduled_at': scheduledAt.toIso8601String(),
      });
      setState(() {
        _clientPays     = (res.data['client_pays'] as num?)?.toDouble();
        _driverReceives = (res.data['driver_receives'] as num?)?.toDouble();
        _distanceKm     = (res.data['distance_km'] as num?)?.toDouble();
        _durationText   = res.data['duration_text'];
      });
    } catch (_) {} finally {
      setState(() => _estimating = false);
    }
  }

  Future<void> _pickDate() async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (date != null && mounted) {
      setState(() => _scheduledDate = date);
      await _pickTime();
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (time != null && mounted) {
      setState(() => _scheduledTime = time);
      _estimatePrice();
    }
  }

  String get _scheduledLabel {
    if (_scheduledDate == null || _scheduledTime == null) {
      return 'Seleccionar fecha y hora';
    }
    final d = DateFormat('EEE d MMM', 'es').format(_scheduledDate!);
    final t = _scheduledTime!.format(context);
    return '$d · $t';
  }

  bool get _isNight {
    final h = DateTime.now().hour;
    return h < 8 || h >= 21;
  }

  bool get _canSubmit {
    return _originLatLng != null &&
        _destLatLng != null &&
        _cargoCtrl.text.isNotEmpty &&
        (double.tryParse(_weightCtrl.text) ?? 0) > 0 &&
        (_isUrgent ||
            (_scheduledDate != null && _scheduledTime != null));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_canSubmit) {
      setState(() => _error = _isUrgent
          ? 'Completa todos los campos'
          : 'Selecciona fecha y hora del flete');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() { _loading = true; _error = null; });

    try {
      DateTime? scheduledAt;
      if (!_isUrgent) {
        scheduledAt = DateTime(
          _scheduledDate!.year, _scheduledDate!.month,
          _scheduledDate!.day, _scheduledTime!.hour,
          _scheduledTime!.minute,
        );
      }

      await _freightService.createFreight(
        originAddress:      _originCtrl.text,
        originLat:          _originLatLng!.latitude,
        originLng:          _originLatLng!.longitude,
        destinationAddress: _destCtrl.text,
        destinationLat:     _destLatLng!.latitude,
        destinationLng:     _destLatLng!.longitude,
        cargoDescription:   _cargoCtrl.text,
        cargoWeightKg:      double.parse(_weightCtrl.text),
        requiresHelpers:    _helpers,
        isUrgent:           _isUrgent,
        scheduledAt:        scheduledAt,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isUrgent
            ? '⚡ Flete urgente creado — buscando conductor'
            : '📅 Flete programado correctamente'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ));
      context.go('/client/freights');
    } catch (_) {
      setState(() => _error = 'Error al crear el flete. Intenta de nuevo.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'es_CL');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Nuevo flete'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.midnight,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppTheme.slate200),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [

            // ── 1. Tipo de flete ─────────────────────────
            _ModeSelector(controller: _modeTab),
            const SizedBox(height: 16),

            // ── 2. Urgente — info de tarifa ──────────────
            if (_isUrgent) ...[
              _TarifaBanner(isNight: _isNight),
              const SizedBox(height: 16),
            ],

            // ── 3. Fecha y hora (solo programado) ────────
            if (!_isUrgent) ...[
              _SectionCard(
                title: 'Cuándo',
                icon: Icons.schedule_rounded,
                child: _DateTimePicker(
                  label: _scheduledLabel,
                  isSet: _scheduledDate != null && _scheduledTime != null,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── 4. Origen y destino ──────────────────────
            _SectionCard(
              title: 'Ruta',
              icon: Icons.route_rounded,
              child: Column(children: [
                _LocationRow(
                  label: 'Origen',
                  value: _originCtrl.text,
                  color: AppTheme.success,
                  icon: Icons.my_location_rounded,
                  isSet: _originLatLng != null,
                  onTap: () => setState(() {
                    _selectingOrigin = true;
                    _showMap = true;
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Container(
                    height: 20, width: 1,
                    color: AppTheme.slate200,
                  ),
                ),
                _LocationRow(
                  label: 'Destino',
                  value: _destCtrl.text,
                  color: AppTheme.error,
                  icon: Icons.location_on_rounded,
                  isSet: _destLatLng != null,
                  onTap: () => setState(() {
                    _selectingOrigin = false;
                    _showMap = true;
                  }),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Mapa expandible ──────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: _showMap
                  ? Column(children: [
                      _MapSection(
                        initialPos: _originLatLng ?? _santiago,
                        selectingOrigin: _selectingOrigin,
                        markers: _markers,
                        polylines: _polylines,
                        onMapCreated: (c) => _mapController = c,
                        onTap: _onMapTap,
                        onToggle: (v) =>
                            setState(() => _selectingOrigin = v),
                        onClose: () =>
                            setState(() => _showMap = false),
                      ),
                      const SizedBox(height: 12),
                    ])
                  : const SizedBox.shrink(),
            ),

            // ── 5. Detalles de carga ─────────────────────
            _SectionCard(
              title: 'Carga',
              icon: Icons.inventory_2_outlined,
              child: Column(children: [
                TextFormField(
                  controller: _cargoCtrl,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 14, color: AppTheme.midnight),
                  decoration: const InputDecoration(
                    hintText:
                        'Ej: Muebles de living, cajas de ropa, electrodomésticos...',
                    hintStyle: TextStyle(
                        fontSize: 13, color: AppTheme.slate400),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  validator: (v) => (v?.isNotEmpty ?? false)
                      ? null
                      : 'Describe la carga',
                  onChanged: (_) => setState(() {}),
                ),
                const Divider(height: 20),
                Row(children: [
                  const Icon(Icons.scale_outlined,
                      size: 16, color: AppTheme.slate400),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _weightCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.midnight),
                      decoration: const InputDecoration(
                        hintText: 'Peso en kg (ej: 150)',
                        hintStyle: TextStyle(
                            fontSize: 13, color: AppTheme.slate400),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        suffixText: 'kg',
                        suffixStyle: TextStyle(
                            color: AppTheme.slate400, fontSize: 13),
                      ),
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        return (n != null && n > 0)
                            ? null
                            : 'Ingresa el peso';
                      },
                      onChanged: (_) => _estimatePrice(),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 12),

            // ── 6. Peonetas ──────────────────────────────
            _SectionCard(
              title: 'Peoneta adicional',
              icon: Icons.people_outline_rounded,
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ayudante para carga/descarga',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.midnight,
                          )),
                      Text('+\$${fmt.format(10000)} CLP por peoneta',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.slate400,
                          )),
                    ],
                  ),
                ),
                _Counter(
                  value: _helpers,
                  onDecrement: _helpers > 0
                      ? () {
                          setState(() => _helpers--);
                          _estimatePrice();
                        }
                      : null,
                  onIncrement: () {
                    setState(() => _helpers++);
                    _estimatePrice();
                  },
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── 7. Precio estimado ───────────────────────
            if (_estimating)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primary),
                ),
              )
            else if (_clientPays != null)
              _PriceCard(
                clientPays:     _clientPays!,
                driverReceives: _driverReceives,
                distanceKm:     _distanceKm,
                durationText:   _durationText,
                isUrgent:       _isUrgent,
                fmt:            fmt,
              ),

            // ── Error ────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.error.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppTheme.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                          color: AppTheme.error, fontSize: 13)),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),

      // ── CTA sticky ───────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16,
            MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: AppTheme.slate200, width: 0.5),
          ),
        ),
        child: _SubmitButton(
          isUrgent:  _isUrgent,
          canSubmit: _canSubmit,
          loading:   _loading,
          onTap:     _submit,
        ),
      ),
    );
  }
}

// ── Widgets ────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  final TabController controller;
  const _ModeSelector({required this.controller});

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(
      color: AppTheme.slate100,
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.all(4),
    child: TabBar(
      controller: controller,
      indicator: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      indicatorSize:    TabBarIndicatorSize.tab,
      dividerColor:     Colors.transparent,
      labelColor:       AppTheme.midnight,
      unselectedLabelColor: AppTheme.slate400,
      labelStyle: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w400),
      tabs: const [
        Tab(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_today_rounded, size: 14),
              SizedBox(width: 6),
              Text('Programado'),
            ],
          ),
        ),
        Tab(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.flash_on_rounded, size: 14),
              SizedBox(width: 6),
              Text('Urgente'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TarifaBanner extends StatelessWidget {
  final bool isNight;
  const _TarifaBanner({required this.isNight});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
        horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: isNight
          ? const Color(0xFF1E1B4B).withValues(alpha: 0.05)
          : const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isNight
            ? Colors.deepPurple.withValues(alpha: 0.2)
            : AppTheme.urgent.withValues(alpha: 0.25),
        width: 0.5,
      ),
    ),
    child: Row(children: [
      Icon(
        isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
        size: 16,
        color: isNight
            ? Colors.deepPurple.shade300
            : AppTheme.urgent,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          isNight
              ? 'Tarifa nocturna (21:00 - 08:00) · Mínimo \$40.000'
              : 'Tarifa diurna (08:00 - 21:00) · Mínimo \$30.000',
          style: TextStyle(
            fontSize: 12,
            color: isNight
                ? Colors.deepPurple.shade400
                : const Color(0xFFB45309),
          ),
        ),
      ),
    ]),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.slate200, width: 0.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 14, color: AppTheme.slate400),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate400,
                letterSpacing: 0.5,
              )),
        ]),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _DateTimePicker extends StatelessWidget {
  final String label;
  final bool isSet;
  final VoidCallback onTap;
  const _DateTimePicker({
    required this.label,
    required this.isSet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isSet
            ? AppTheme.primary.withValues(alpha: 0.05)
            : const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSet ? AppTheme.primary.withValues(alpha: 0.3)
              : AppTheme.slate200,
          width: 0.8,
        ),
      ),
      child: Row(children: [
        Icon(Icons.calendar_month_rounded,
            size: 18,
            color: isSet ? AppTheme.primary : AppTheme.slate400),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(
                fontSize: 14,
                color: isSet
                    ? AppTheme.midnight
                    : AppTheme.slate400,
                fontWeight: isSet
                    ? FontWeight.w500
                    : FontWeight.normal,
              )),
        ),
        Icon(Icons.chevron_right_rounded,
            size: 16,
            color: isSet ? AppTheme.primary : AppTheme.slate400),
      ]),
    ),
  );
}

class _LocationRow extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  final bool isSet;
  final VoidCallback onTap;
  const _LocationRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.isSet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate400,
                  letterSpacing: 0.4,
                )),
            const SizedBox(height: 2),
            Text(
              value.isEmpty ? 'Toca para seleccionar' : value,
              style: TextStyle(
                fontSize: 13,
                color: isSet
                    ? AppTheme.midnight
                    : AppTheme.slate400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      Icon(Icons.edit_location_alt_outlined,
          size: 16, color: AppTheme.slate400),
    ]),
  );
}

class _MapSection extends StatelessWidget {
  final LatLng initialPos;
  final bool selectingOrigin;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final void Function(GoogleMapController) onMapCreated;
  final void Function(LatLng) onTap;
  final void Function(bool) onToggle;
  final VoidCallback onClose;

  const _MapSection({
    required this.initialPos,
    required this.selectingOrigin,
    required this.markers,
    required this.polylines,
    required this.onMapCreated,
    required this.onTap,
    required this.onToggle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 240,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.slate200, width: 0.5),
    ),
    clipBehavior: Clip.hardEdge,
    child: Stack(children: [
      GoogleMap(
        initialCameraPosition: CameraPosition(
            target: initialPos, zoom: 13),
        onMapCreated: onMapCreated,
        onTap: onTap,
        markers: markers,
        polylines: polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
      ),
      // Toggle
      Positioned(
        top: 10, left: 10, right: 10,
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 8),
                decoration: BoxDecoration(
                  color: selectingOrigin
                      ? AppTheme.success
                      : Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4)
                  ],
                ),
                child: Text('Marcar origen',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selectingOrigin
                          ? Colors.white
                          : AppTheme.success,
                    )),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(false),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 8),
                decoration: BoxDecoration(
                  color: !selectingOrigin
                      ? AppTheme.error
                      : Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4)
                  ],
                ),
                child: Text('Marcar destino',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: !selectingOrigin
                          ? Colors.white
                          : AppTheme.error,
                    )),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4)
                ],
              ),
              child: const Icon(Icons.close_rounded,
                  size: 16, color: AppTheme.midnight),
            ),
          ),
        ]),
      ),
    ]),
  );
}

class _Counter extends StatelessWidget {
  final int value;
  final VoidCallback? onDecrement;
  final VoidCallback onIncrement;
  const _Counter({
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      GestureDetector(
        onTap: onDecrement,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: onDecrement != null
                ? AppTheme.slate100
                : const Color(0xFFF4F4F4),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.slate200, width: 0.5),
          ),
          child: Icon(Icons.remove_rounded,
              size: 16,
              color: onDecrement != null
                  ? AppTheme.midnight
                  : AppTheme.slate400),
        ),
      ),
      SizedBox(
        width: 36,
        child: Text('$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.midnight,
            )),
      ),
      GestureDetector(
        onTap: onIncrement,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: const Icon(Icons.add_rounded,
              size: 16, color: AppTheme.primary),
        ),
      ),
    ],
  );
}

class _PriceCard extends StatelessWidget {
  final double clientPays;
  final double? driverReceives;
  final double? distanceKm;
  final String? durationText;
  final bool isUrgent;
  final NumberFormat fmt;
  const _PriceCard({
    required this.clientPays,
    required this.driverReceives,
    required this.distanceKm,
    required this.durationText,
    required this.isUrgent,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppTheme.success.withValues(alpha: 0.3),
        width: 0.8,
      ),
    ),
    child: Column(children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total a pagar',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.slate400,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 2),
                Text('\$${fmt.format(clientPays)} CLP',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.midnight,
                    )),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isUrgent
                  ? AppTheme.urgent.withValues(alpha: 0.1)
                  : AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isUrgent ? '⚡ Urgente' : '📅 Programado',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isUrgent
                    ? AppTheme.urgent
                    : AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
      const Divider(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (distanceKm != null)
            _PriceMeta(
              icon: Icons.route_rounded,
              label: '${distanceKm!.toStringAsFixed(1)} km',
            ),
          if (durationText != null)
            _PriceMeta(
              icon: Icons.schedule_rounded,
              label: durationText!,
            ),
          if (driverReceives != null)
            _PriceMeta(
              icon: Icons.person_outline_rounded,
              label: 'Conductor: \$${fmt.format(driverReceives)}',
            ),
        ],
      ),
    ]),
  );
}

class _PriceMeta extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PriceMeta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: AppTheme.slate400),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(
            fontSize: 11, color: AppTheme.slate400)),
    ],
  );
}

class _SubmitButton extends StatefulWidget {
  final bool isUrgent, canSubmit, loading;
  final VoidCallback onTap;
  const _SubmitButton({
    required this.isUrgent,
    required this.canSubmit,
    required this.loading,
    required this.onTap,
  });

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.97).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: GestureDetector(
      onTapDown:   widget.canSubmit && !widget.loading
          ? (_) => _ctrl.forward() : null,
      onTapUp:     widget.canSubmit && !widget.loading
          ? (_) { _ctrl.reverse(); widget.onTap(); } : null,
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          gradient: widget.canSubmit
              ? LinearGradient(
                  colors: widget.isUrgent
                      ? [const Color(0xFFFF8C00),
                         const Color(0xFFF97316)]
                      : [const Color(0xFF4F94F8),
                         const Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: widget.canSubmit ? null : AppTheme.slate200,
          borderRadius: BorderRadius.circular(14),
          boxShadow: widget.canSubmit ? [
            BoxShadow(
              color: (widget.isUrgent
                  ? AppTheme.urgent
                  : AppTheme.primary).withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ] : [],
        ),
        child: Center(
          child: widget.loading
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.isUrgent
                          ? Icons.flash_on_rounded
                          : Icons.check_circle_outline_rounded,
                      color: widget.canSubmit
                          ? Colors.white
                          : AppTheme.slate400,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isUrgent
                          ? 'Solicitar flete urgente'
                          : 'Confirmar flete',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: widget.canSubmit
                            ? Colors.white
                            : AppTheme.slate400,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}