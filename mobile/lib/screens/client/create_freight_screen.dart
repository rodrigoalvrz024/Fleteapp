import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../services/freight_service.dart';
import '../../services/api_service.dart';
import '../../core/theme/app_theme.dart';

class CreateFreightScreen extends StatefulWidget {
  const CreateFreightScreen({super.key});
  @override
  State<CreateFreightScreen> createState() => _CreateFreightScreenState();
}

class _CreateFreightScreenState extends State<CreateFreightScreen>
    with SingleTickerProviderStateMixin {

  final _formKey        = GlobalKey<FormState>();
  final _freightService = FreightService();
  final _api            = ApiService();

  final _originCtrl = TextEditingController(text: 'Santiago Centro');
  final _destCtrl   = TextEditingController(text: 'Las Condes');
  final _cargoCtrl  = TextEditingController();
  final _weightCtrl = TextEditingController();

  // Mapa
  GoogleMapController? _mapController;
  LatLng? _originLatLng = const LatLng(-33.4489, -70.6693);
  LatLng? _destLatLng   = const LatLng(-33.4700, -70.6500);
  bool _selectingOrigin = true;
  Set<Marker>   _markers   = {};
  Set<Polyline> _polylines = {};

  // Modo
  bool _isUrgent = false;
  late TabController _modeTabController;

  // Programado — fecha y hora
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  // Helpers
  int    _helpers        = 0;
  bool   _loading        = false;
  bool   _estimating     = false;
  String? _error;

  // Precio estimado
  double? _clientPays;
  double? _driverReceives;
  double? _platformFee;
  double? _distanceKm;
  String? _durationText;
  double? _minimumApplied;
  String? _mode;

  static const LatLng _initialPosition = LatLng(-33.4489, -70.6693);

  @override
  void initState() {
    super.initState();
    _modeTabController = TabController(length: 2, vsync: this);
    _modeTabController.addListener(() {
      setState(() {
        _isUrgent = _modeTabController.index == 1;
        _scheduledDate = null;
        _scheduledTime = null;
        _clientPays = null;
      });
      _estimatePrice();
    });
    _initMarkers();
    _requestLocation();
  }

  @override
  void dispose() {
    _modeTabController.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _cargoCtrl.dispose();
    _weightCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _initMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId('origin'),
        position: _originLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Origen'),
      ),
      Marker(
        markerId: const MarkerId('dest'),
        position: _destLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destino'),
      ),
    };
    _polylines = {
      Polyline(
        polylineId: const PolylineId('route'),
        color: AppTheme.primary,
        width: 4,
        points: [_originLatLng!, _destLatLng!],
      ),
    };
  }

  Future<void> _requestLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always) {
      _goToMyLocation();
    }
    _estimatePrice();
  }

  Future<void> _goToMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 13));
    } catch (_) {}
  }

  void _onMapTap(LatLng tapped) {
    setState(() {
      if (_selectingOrigin) {
        _originLatLng = tapped;
        _originCtrl.text =
            'Lat: ${tapped.latitude.toStringAsFixed(4)}, Lng: ${tapped.longitude.toStringAsFixed(4)}';
        _markers.removeWhere((m) => m.markerId.value == 'origin');
        _markers.add(Marker(
          markerId: const MarkerId('origin'),
          position: tapped,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Origen'),
        ));
      } else {
        _destLatLng = tapped;
        _destCtrl.text =
            'Lat: ${tapped.latitude.toStringAsFixed(4)}, Lng: ${tapped.longitude.toStringAsFixed(4)}';
        _markers.removeWhere((m) => m.markerId.value == 'dest');
        _markers.add(Marker(
          markerId: const MarkerId('dest'),
          position: tapped,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destino'),
        ));
      }
      if (_originLatLng != null && _destLatLng != null) {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: AppTheme.primary,
            width: 4,
            points: [_originLatLng!, _destLatLng!],
          ),
        };
        _estimatePrice();
      }
    });
  }

  Future<void> _estimatePrice() async {
    if (_originLatLng == null || _destLatLng == null) return;
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) return;

    setState(() => _estimating = true);
    try {
      DateTime? scheduledAt;
      if (!_isUrgent && _scheduledDate != null && _scheduledTime != null) {
        scheduledAt = DateTime(
          _scheduledDate!.year, _scheduledDate!.month, _scheduledDate!.day,
          _scheduledTime!.hour, _scheduledTime!.minute,
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
        _clientPays      = (res.data['client_pays'] as num?)?.toDouble();
        _driverReceives  = (res.data['driver_receives'] as num?)?.toDouble();
        _platformFee     = (res.data['platform_fee'] as num?)?.toDouble();
        _distanceKm      = (res.data['distance_km'] as num?)?.toDouble();
        _durationText    = res.data['duration_text'];
        _minimumApplied  = (res.data['minimum_applied'] as num?)?.toDouble();
        _mode            = res.data['mode'];
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
      helpText: 'Selecciona la fecha del flete',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (date != null) {
      setState(() => _scheduledDate = date);
      await _pickTime();
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Selecciona la hora del flete',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (time != null) {
      setState(() => _scheduledTime = time);
      _estimatePrice();
    }
  }

  String get _scheduledLabel {
    if (_scheduledDate == null || _scheduledTime == null) {
      return 'Seleccionar fecha y hora';
    }
    final date = DateFormat('EEE d MMM', 'es').format(_scheduledDate!);
    final time = _scheduledTime!.format(context);
    return '$date a las $time';
  }

  bool get _isNightUrgent {
    final hour = DateTime.now().hour;
    return hour < 8 || hour >= 21;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_originLatLng == null) {
      setState(() => _error = 'Selecciona el origen en el mapa');
      return;
    }
    if (_destLatLng == null) {
      setState(() => _error = 'Selecciona el destino en el mapa');
      return;
    }
    if (!_isUrgent &&
        (_scheduledDate == null || _scheduledTime == null)) {
      setState(() => _error = 'Selecciona la fecha y hora del flete');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      DateTime? scheduledAt;
      if (!_isUrgent) {
        scheduledAt = DateTime(
          _scheduledDate!.year, _scheduledDate!.month, _scheduledDate!.day,
          _scheduledTime!.hour, _scheduledTime!.minute,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isUrgent
              ? '⚡ Flete urgente creado — buscando conductor'
              : '📅 Flete programado para $_scheduledLabel'),
          backgroundColor: AppTheme.success,
        ),
      );
      context.go('/client/freights');
    } catch (e) {
      setState(() => _error = 'Error al crear el flete. Verifica tu conexión.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'es_CL');

    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar flete')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [

            // ── Selector de modo ─────────────────────────────
            Container(
              color: AppTheme.primary,
              child: TabBar(
                controller: _modeTabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                tabs: const [
                  Tab(icon: Icon(Icons.calendar_today, size: 18), text: 'Programado'),
                  Tab(icon: Icon(Icons.flash_on, size: 18),       text: 'Urgente'),
                ],
              ),
            ),

            // ── Mapa ─────────────────────────────────────────
            SizedBox(
              height: 220,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: const CameraPosition(
                        target: _initialPosition, zoom: 12),
                    onMapCreated: (c) => _mapController = c,
                    onTap: _onMapTap,
                    markers: _markers,
                    polylines: _polylines,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                  Positioned(
                    top: 10, left: 10, right: 10,
                    child: Row(children: [
                      Expanded(child: _MapToggle(
                        label: 'Marcar origen',
                        active: _selectingOrigin,
                        color: AppTheme.success,
                        onTap: () => setState(() => _selectingOrigin = true),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _MapToggle(
                        label: 'Marcar destino',
                        active: !_selectingOrigin,
                        color: AppTheme.error,
                        onTap: () => setState(() => _selectingOrigin = false),
                      )),
                    ]),
                  ),
                  Positioned(
                    bottom: 10, right: 10,
                    child: FloatingActionButton.small(
                      heroTag: 'loc',
                      backgroundColor: Colors.white,
                      onPressed: _goToMyLocation,
                      child: const Icon(Icons.my_location, color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
            ),

            // ── Formulario ───────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    // Error
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(color: AppTheme.error)),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Modo programado: selector fecha/hora ──
                    if (!_isUrgent) ...[
                      _SectionTitle(title: 'Fecha y hora', icon: Icons.schedule),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (_scheduledDate != null && _scheduledTime != null)
                                  ? AppTheme.primary
                                  : const Color(0xFFE0E0E0),
                              width: (_scheduledDate != null && _scheduledTime != null) ? 2 : 1,
                            ),
                          ),
                          child: Row(children: [
                            Icon(
                              Icons.calendar_month,
                              color: (_scheduledDate != null)
                                  ? AppTheme.primary
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _scheduledLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: (_scheduledDate != null)
                                      ? AppTheme.textPrimary
                                      : Colors.grey,
                                  fontWeight: (_scheduledDate != null)
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Colors.grey),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Modo urgente: badge horario ───────────
                    if (_isUrgent) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isNightUrgent
                              ? const Color(0xFF1A1A2E)
                              : const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isNightUrgent
                                ? Colors.deepPurple
                                : Colors.orange,
                          ),
                        ),
                        child: Row(children: [
                          Icon(
                            _isNightUrgent ? Icons.nightlight : Icons.wb_sunny,
                            color: _isNightUrgent ? Colors.purple : Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isNightUrgent
                                      ? 'Tarifa nocturna (21:00 - 08:00)'
                                      : 'Tarifa diurna (08:00 - 21:00)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: _isNightUrgent
                                        ? Colors.purple
                                        : Colors.orange.shade800,
                                  ),
                                ),
                                Text(
                                  _isNightUrgent
                                      ? 'Mínimo \$40.000 CLP'
                                      : 'Mínimo \$30.000 CLP',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _isNightUrgent
                                        ? Colors.purple.shade200
                                        : Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Precio estimado ───────────────────────
                    if (_estimating)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_clientPays != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.success),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Tú pagas',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary)),
                                    Text(
                                      '\$${fmt.format(_clientPays)} CLP',
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primary),
                                    ),
                                  ],
                                ),
                                if (_distanceKm != null)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${_distanceKm!.toStringAsFixed(1)} km',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                      if (_durationText != null)
                                        Text(
                                          _durationText!,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                            const Divider(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Conductor recibe: \$${fmt.format(_driverReceives)} CLP',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _isUrgent
                                        ? Colors.orange
                                        : AppTheme.primary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _isUrgent ? '⚡ Urgente' : '📅 Programado',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // ── Coordenadas ───────────────────────────
                    _CoordField(
                        label: 'Origen', ctrl: _originCtrl,
                        isSet: _originLatLng != null, color: AppTheme.success),
                    const SizedBox(height: 8),
                    _CoordField(
                        label: 'Destino', ctrl: _destCtrl,
                        isSet: _destLatLng != null, color: AppTheme.error),
                    const SizedBox(height: 14),

                    // ── Descripción ───────────────────────────
                    TextFormField(
                      controller: _cargoCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descripción de la carga',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      validator: (v) =>
                          (v?.isNotEmpty ?? false) ? null : 'Describe la carga',
                    ),
                    const SizedBox(height: 12),

                    // ── Peso ──────────────────────────────────
                    TextFormField(
                      controller: _weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Peso aproximado (kg)',
                        prefixIcon: Icon(Icons.scale_outlined),
                      ),
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        return (n != null && n > 0) ? null : 'Peso inválido';
                      },
                      onChanged: (_) => _estimatePrice(),
                    ),
                    const SizedBox(height: 12),

                    // ── Peonetas ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.people_outline,
                            color: AppTheme.textSecondary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Peonetas adicionales',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14)),
                              Text('+\$10.000 CLP por peoneta',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _helpers > 0
                              ? () {
                                  setState(() => _helpers--);
                                  _estimatePrice();
                                }
                              : null,
                        ),
                        Text('$_helpers',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: AppTheme.primary),
                          onPressed: () {
                            setState(() => _helpers++);
                            _estimatePrice();
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // ── Botón confirmar ───────────────────────
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isUrgent ? Colors.orange : AppTheme.primary,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: Icon(_isUrgent
                          ? Icons.flash_on
                          : Icons.calendar_today),
                      label: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(_isUrgent
                              ? 'Solicitar flete urgente'
                              : 'Programar flete'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ─────────────────────────────────────

class _MapToggle extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _MapToggle({required this.label, required this.active,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: active ? color : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: active ? Colors.white : color,
              fontWeight: FontWeight.w600,
              fontSize: 12)),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: AppTheme.primary, size: 18),
    const SizedBox(width: 8),
    Text(title,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary)),
  ]);
}

class _CoordField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final bool isSet;
  final Color color;
  const _CoordField({required this.label, required this.ctrl,
      required this.isSet, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: isSet ? color.withValues(alpha: 0.07) : const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
          color: isSet ? color : const Color(0xFFDDDDDD)),
    ),
    child: Row(children: [
      Icon(isSet ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isSet ? color : Colors.grey, size: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: isSet ? color : Colors.grey,
                  fontWeight: FontWeight.w500)),
          Text(
            ctrl.text.isEmpty ? 'Toca el mapa para marcar' : ctrl.text,
            style: TextStyle(
                fontSize: 12,
                color: isSet ? AppTheme.textPrimary : Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    ]),
  );
}