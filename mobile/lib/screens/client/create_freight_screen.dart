import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/freight_service.dart';
import '../../services/api_service.dart';
import '../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class CreateFreightScreen extends StatefulWidget {
  const CreateFreightScreen({super.key});
  @override
  State<CreateFreightScreen> createState() => _CreateFreightScreenState();
}

class _CreateFreightScreenState extends State<CreateFreightScreen> {
  final _formKey = GlobalKey<FormState>();
  final _freightService = FreightService();
  final _api = ApiService();

  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _cargoCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  GoogleMapController? _mapController;
  LatLng? _originLatLng = const LatLng(-33.4489, -70.6693);
  LatLng? _destLatLng   = const LatLng(-33.4700, -70.6500);
  bool _selectingOrigin = true; // true=origen, false=destino

  final Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  int _helpers = 0;
  bool _loading = false;
  bool _estimating = false;
  double? _estimatedPrice;
  double? _estimatedDistance;
  String? _estimatedDuration;
  String? _error;

  // Santiago, Chile como centro inicial
  static const LatLng _initialPosition = LatLng(-33.4489, -70.6693);

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    _cargoCtrl.dispose();
    _weightCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always) {
      _goToMyLocation();
    }
  }

  Future<void> _goToMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final latLng = LatLng(pos.latitude, pos.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 14));
    } catch (_) {}
  }

  void _onMapTap(LatLng tapped) {
    setState(() {
      if (_selectingOrigin) {
        _originLatLng = tapped;
        _originCtrl.text =
            'Lat: ${tapped.latitude.toStringAsFixed(5)}, Lng: ${tapped.longitude.toStringAsFixed(5)}';
        _markers.removeWhere((m) => m.markerId.value == 'origin');
        _markers.add(Marker(
          markerId: const MarkerId('origin'),
          position: tapped,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Origen'),
        ));
      } else {
        _destLatLng = tapped;
        _destCtrl.text =
            'Lat: ${tapped.latitude.toStringAsFixed(5)}, Lng: ${tapped.longitude.toStringAsFixed(5)}';
        _markers.removeWhere((m) => m.markerId.value == 'dest');
        _markers.add(Marker(
          markerId: const MarkerId('dest'),
          position: tapped,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destino'),
        ));
      }

      if (_originLatLng != null && _destLatLng != null) {
        _drawLine();
        _estimatePrice();
      }
    });
  }

  void _drawLine() {
    if (_originLatLng == null || _destLatLng == null) return;
    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          color: AppTheme.primary,
          width: 4,
          points: [_originLatLng!, _destLatLng!],
        ),
      };
    });
    // Ajusta la cámara para mostrar ambos puntos
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(
          _originLatLng!.latitude < _destLatLng!.latitude
              ? _originLatLng!.latitude
              : _destLatLng!.latitude,
          _originLatLng!.longitude < _destLatLng!.longitude
              ? _originLatLng!.longitude
              : _destLatLng!.longitude,
        ),
        northeast: LatLng(
          _originLatLng!.latitude > _destLatLng!.latitude
              ? _originLatLng!.latitude
              : _destLatLng!.latitude,
          _originLatLng!.longitude > _destLatLng!.longitude
              ? _originLatLng!.longitude
              : _destLatLng!.longitude,
        ),
      ),
      80,
    ));
  }

  Future<void> _estimatePrice() async {
    if (_originLatLng == null || _destLatLng == null) return;
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) return;

    setState(() {
      _estimating = true;
    });
    try {
      final res = await _api.get('/freights/estimate', params: {
        'origin_lat': _originLatLng!.latitude,
        'origin_lng': _originLatLng!.longitude,
        'destination_lat': _destLatLng!.latitude,
        'destination_lng': _destLatLng!.longitude,
        'cargo_weight_kg': weight,
        'requires_helpers': _helpers,
      });
      setState(() {
        _estimatedPrice = (res.data['estimated_price_clp'] as num).toDouble();
        _estimatedDistance = (res.data['distance_km'] as num).toDouble();
        _estimatedDuration = res.data['duration_text'];
      });
    } catch (_) {
    } finally {
      setState(() {
        _estimating = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_originLatLng == null) {
      setState(() {
        _error = 'Selecciona el punto de origen en el mapa';
      });
      return;
    }
    if (_destLatLng == null) {
      setState(() {
        _error = 'Selecciona el punto de destino en el mapa';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _freightService.createFreight(
        originAddress: _originCtrl.text,
        originLat: _originLatLng!.latitude,
        originLng: _originLatLng!.longitude,
        destinationAddress: _destCtrl.text,
        destinationLat: _destLatLng!.latitude,
        destinationLng: _destLatLng!.longitude,
        cargoDescription: _cargoCtrl.text,
        cargoWeightKg: double.parse(_weightCtrl.text),
        requiresHelpers: _helpers,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('¡Flete creado exitosamente!'),
            backgroundColor: AppTheme.success),
      );
      context.go('/client/freights');
    } catch (e) {
      setState(() {
        _error = 'Error al crear el flete. Verifica tu conexión.';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Solicitar flete')),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              // ── Mapa ──────────────────────────────────────────────
              SizedBox(
                height: 260,
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
                    // Selector origen / destino
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Row(children: [
                        Expanded(
                            child: _MapToggle(
                                label: 'Marcar origen',
                                active: _selectingOrigin,
                                color: AppTheme.success,
                                onTap: () =>
                                    setState(() => _selectingOrigin = true))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _MapToggle(
                                label: 'Marcar destino',
                                active: !_selectingOrigin,
                                color: AppTheme.error,
                                onTap: () =>
                                    setState(() => _selectingOrigin = false))),
                      ]),
                    ),
                    // Botón mi ubicación
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'location',
                        backgroundColor: Colors.white,
                        onPressed: _goToMyLocation,
                        child: const Icon(Icons.my_location,
                            color: AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Formulario ────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppTheme.error, fontSize: 13)),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Precio estimado
                      if (_estimating)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(8),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)))
                      else if (_estimatedPrice != null)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: const Color(0xFFE3F2FD),
                              borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            const Icon(Icons.calculate_outlined,
                                color: AppTheme.primary),
                            const SizedBox(width: 10),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Precio estimado',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary)),
                                  Text(
                                      '\$${NumberFormat('#,##0', 'es_CL').format(_estimatedPrice)} CLP',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primary)),
                                ]),
                            const Spacer(),
                            if (_estimatedDistance != null)
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                        '${_estimatedDistance!.toStringAsFixed(1)} km',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    if (_estimatedDuration != null)
                                      Text(_estimatedDuration!,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary)),
                                  ]),
                          ]),
                        ),

                      const SizedBox(height: 14),

                      // Coords seleccionadas
                      _CoordField(
                          label: 'Origen',
                          ctrl: _originCtrl,
                          set: _originLatLng != null,
                          color: AppTheme.success),
                      const SizedBox(height: 10),
                      _CoordField(
                          label: 'Destino',
                          ctrl: _destCtrl,
                          set: _destLatLng != null,
                          color: AppTheme.error),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _cargoCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Descripción de la carga',
                            prefixIcon: Icon(Icons.inventory_2_outlined)),
                        validator: (v) => (v?.isNotEmpty ?? false)
                            ? null
                            : 'Describe la carga',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Peso aproximado (kg)',
                            prefixIcon: Icon(Icons.scale_outlined)),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          return (n != null && n > 0) ? null : 'Peso inválido';
                        },
                        onChanged: (_) => _estimatePrice(),
                      ),
                      const SizedBox(height: 12),

                      Row(children: [
                        const Text('Ayudantes:',
                            style: TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 14)),
                        const Spacer(),
                        IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _helpers > 0
                                ? () {
                                    setState(() => _helpers--);
                                    _estimatePrice();
                                  }
                                : null),
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
                            }),
                      ]),
                      const SizedBox(height: 20),

                      ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Confirmar y solicitar flete'),
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

class _MapToggle extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _MapToggle(
      {required this.label,
      required this.active,
      required this.color,
      required this.onTap});

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

class _CoordField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final bool set;
  final Color color;
  const _CoordField(
      {required this.label,
      required this.ctrl,
      required this.set,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: set ? color.withValues(alpha: 0.07) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: set ? color : const Color(0xFFDDDDDD)),
        ),
        child: Row(children: [
          Icon(set ? Icons.check_circle : Icons.radio_button_unchecked,
              color: set ? color : Colors.grey, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: set ? color : Colors.grey,
                        fontWeight: FontWeight.w500)),
                Text(
                  ctrl.text.isEmpty ? 'Toca el mapa para marcar' : ctrl.text,
                  style: TextStyle(
                      fontSize: 12,
                      color: set ? AppTheme.textPrimary : Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ])),
        ]),
      );
}
