import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../models/place_suggestion.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/freight_service.dart';
import '../../services/places_service.dart';
import '../../utils/api_error_message.dart';
import '../../widgets/muvv_mobile_ui.dart';
import '../shared/web_layout.dart';

class CreateFreightScreen extends ConsumerStatefulWidget {
  final String? destAddress;
  final double? destLat;
  final double? destLng;
  final String? originAddress;
  final double? originLat;
  final double? originLng;
  final bool initialUrgent;
  final String? initialServiceType;

  const CreateFreightScreen({
    super.key,
    this.destAddress,
    this.destLat,
    this.destLng,
    this.originAddress,
    this.originLat,
    this.originLng,
    this.initialUrgent = false,
    this.initialServiceType,
  });

  @override
  ConsumerState<CreateFreightScreen> createState() =>
      _CreateFreightScreenState();
}

class _CreateFreightScreenState extends ConsumerState<CreateFreightScreen> {
  final _freightService = FreightService();
  final _api = ApiService();
  final _cargoCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _volumeCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();

  static const _santiago = LatLng(-33.4489, -70.6693);

  GoogleMapController? _mapController;
  LatLng? _originLatLng;
  LatLng? _destLatLng;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _showMap = false;
  bool _selectingOrigin = true;

  int _currentStep = 0;
  String? _serviceType;
  bool _isUrgent = false;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  int _helpers = 0;

  bool _loading = false;
  bool _estimating = false;
  String? _error;
  double? _clientPays;
  double? _basePrice;
  double? _helpersCost;
  double? _timeCharge;
  double? _urgencyCharge;
  double? _tolls;
  double? _distanceKm;
  String? _durationText;
  String? _recommendedVehicleName;
  String? _quoteId;
  bool _requiresManualQuote = false;
  bool _minimumApplied = false;

  @override
  void initState() {
    super.initState();
    _isUrgent = widget.initialUrgent;
    _serviceType = _validServiceType(widget.initialServiceType);
    _applyInitialRoute();
    _requestLocation();
  }

  @override
  void dispose() {
    _cargoCtrl.dispose();
    _weightCtrl.dispose();
    _volumeCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _applyInitialRoute() {
    if (widget.originAddress?.isNotEmpty ?? false) {
      _originCtrl.text = widget.originAddress!;
    }
    if (widget.originLat != null && widget.originLng != null) {
      _originLatLng = LatLng(widget.originLat!, widget.originLng!);
    }
    if (widget.destAddress?.isNotEmpty ?? false) {
      _destCtrl.text = widget.destAddress!;
    }
    if (widget.destLat != null && widget.destLng != null) {
      _destLatLng = LatLng(widget.destLat!, widget.destLng!);
    }
    _refreshRouteVisuals();
  }

  void _refreshRouteVisuals() {
    _markers = {
      if (_originLatLng != null)
        Marker(
          markerId: const MarkerId('origin'),
          position: _originLatLng!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Origen'),
        ),
      if (_destLatLng != null)
        Marker(
          markerId: const MarkerId('destination'),
          position: _destLatLng!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Destino'),
        ),
    };
    _polylines = _originLatLng != null && _destLatLng != null
        ? {
            Polyline(
              polylineId: const PolylineId('selected-route'),
              points: [_originLatLng!, _destLatLng!],
              width: 4,
              color: AppTheme.primary,
            ),
          }
        : {};
  }

  Future<void> _requestLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted || _originLatLng != null) return;
      setState(() {
        _originLatLng = LatLng(position.latitude, position.longitude);
        _originCtrl.text = 'Mi ubicación actual';
        _refreshRouteVisuals();
      });
      _estimatePrice();
    } catch (_) {
      // The user can still choose their pickup point on the map or by search.
    }
  }

  Future<void> _openAddressSelector({required bool origin}) async {
    final selected = await showModalBottomSheet<_SelectedAddress>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressSearchSheet(
        title: origin ? 'Punto de retiro' : 'Destino',
        initialPosition: origin ? _originLatLng : _destLatLng,
      ),
    );
    if (!mounted || selected == null) return;

    setState(() {
      if (origin) {
        _originCtrl.text = selected.address;
        _originLatLng = selected.position;
      } else {
        _destCtrl.text = selected.address;
        _destLatLng = selected.position;
      }
      _showMap = false;
      _clearEstimate();
      _error = null;
      _refreshRouteVisuals();
    });
    _estimatePrice();
  }

  void _openMapSelector({required bool origin}) {
    setState(() {
      _selectingOrigin = origin;
      _showMap = true;
      _error = null;
    });
  }

  void _onMapTap(LatLng point) {
    setState(() {
      const label = 'Ubicación seleccionada en el mapa';
      if (_selectingOrigin) {
        _originLatLng = point;
        _originCtrl.text = label;
      } else {
        _destLatLng = point;
        _destCtrl.text = label;
      }
      _refreshRouteVisuals();
      _clearEstimate();
      _error = null;
    });
    _estimatePrice();
  }

  double? get _cargoWeight =>
      double.tryParse(_weightCtrl.text.trim().replaceAll(',', '.'));

  double? get _cargoVolume =>
      double.tryParse(_volumeCtrl.text.trim().replaceAll(',', '.'));

  bool get _routeReady => _originLatLng != null && _destLatLng != null;

  bool get _cargoReady =>
      _serviceType != null &&
      _cargoCtrl.text.trim().isNotEmpty &&
      (_cargoWeight ?? 0) > 0;

  bool get _timingReady =>
      _isUrgent || (_scheduledDate != null && _scheduledTime != null);

  bool get _priceReady => _clientPays != null;

  void _clearEstimate() {
    _clientPays = null;
    _basePrice = null;
    _helpersCost = null;
    _timeCharge = null;
    _urgencyCharge = null;
    _tolls = null;
    _distanceKm = null;
    _durationText = null;
    _recommendedVehicleName = null;
    _quoteId = null;
    _requiresManualQuote = false;
    _minimumApplied = false;
  }

  String get _scheduledLabel {
    if (_scheduledDate == null || _scheduledTime == null) {
      return 'Elegir fecha y hora';
    }
    final date = DateFormat('EEE d MMM', 'es').format(_scheduledDate!);
    return '$date · ${_scheduledTime!.format(context)}';
  }

  Future<void> _estimatePrice() async {
    if (!_routeReady || !_cargoReady || !_timingReady) return;

    setState(() => _estimating = true);
    try {
      DateTime? scheduledAt;
      if (!_isUrgent && _scheduledDate != null && _scheduledTime != null) {
        scheduledAt = DateTime(
          _scheduledDate!.year,
          _scheduledDate!.month,
          _scheduledDate!.day,
          _scheduledTime!.hour,
          _scheduledTime!.minute,
        );
      }
      final response = await _api.post(ApiConstants.pricingEstimate, {
        'origin_lat': _originLatLng!.latitude,
        'origin_lng': _originLatLng!.longitude,
        'destination_lat': _destLatLng!.latitude,
        'destination_lng': _destLatLng!.longitude,
        'origin_address': _originCtrl.text.trim(),
        'destination_address': _destCtrl.text.trim(),
        'cargo_weight_kg': _cargoWeight,
        if (_cargoVolume != null) 'cargo_volume_m3': _cargoVolume,
        'cargo_description': _cargoCtrl.text.trim(),
        'service_type': _serviceTypeApiValue,
        'requires_helpers': _helpers,
        'is_urgent': _isUrgent,
        if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
      });
      if (!mounted) return;
      setState(() {
        _requiresManualQuote = response.data['requires_manual_quote'] == true;
        _clientPays = _requiresManualQuote
            ? null
            : (response.data['customer_price'] as num?)?.toDouble();
        _basePrice = (response.data['base_price'] as num?)?.toDouble();
        _helpersCost = (response.data['helper_charge'] as num?)?.toDouble();
        _timeCharge = (response.data['time_charge'] as num?)?.toDouble();
        _urgencyCharge = (response.data['urgency_charge'] as num?)?.toDouble();
        _tolls = (response.data['estimated_tolls'] as num?)?.toDouble();
        _distanceKm = (response.data['distance_km'] as num?)?.toDouble();
        _durationText = response.data['duration_text']?.toString();
        _recommendedVehicleName =
            response.data['recommended_vehicle_name']?.toString();
        _quoteId = response.data['quote_id']?.toString();
        _minimumApplied = response.data['minimum_applied'] == true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clearEstimate();
        _error = apiErrorMessage(
          error,
          fallback:
              'No pudimos calcular el precio. Estamos teniendo problemas para obtener la tarifa. Intenta nuevamente.',
        );
      });
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledDate = date;
      _scheduledTime = time;
      _clearEstimate();
      _error = null;
    });
  }

  void _selectTiming({required bool urgent}) {
    setState(() {
      _isUrgent = urgent;
      if (urgent) {
        _scheduledDate = null;
        _scheduledTime = null;
      }
      _clearEstimate();
      _error = null;
    });
  }

  void _setServiceType(String service) {
    HapticFeedback.selectionClick();
    setState(() {
      _serviceType = service;
      _clearEstimate();
      _error = null;
    });
  }

  String? _validServiceType(String? value) {
    const serviceTypes = {
      'Paquetería',
      'Mudanza',
      'Hogar u oficina',
      'Envío urgente',
    };
    return serviceTypes.contains(value) ? value : null;
  }

  String? get _serviceTypeApiValue => switch (_serviceType) {
        'Paquetería' => 'package',
        'Mudanza' => 'moving',
        'Hogar u oficina' => 'home_office',
        'Envío urgente' => 'urgent',
        _ => null,
      };

  void _setHelpers(int helpers) {
    HapticFeedback.selectionClick();
    setState(() {
      _helpers = helpers;
      _clearEstimate();
      _error = null;
    });
  }

  String get _helpersSummary => switch (_helpers) {
        0 => 'Sin ayudante',
        1 => '1 ayudante',
        _ => '$_helpers ayudantes',
      };

  void _goToStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _currentStep = step;
      _error = null;
    });
  }

  Future<void> _continue() async {
    if (_currentStep == 0) {
      if (!_routeReady) {
        setState(() => _error = 'Selecciona un punto de retiro y un destino.');
        return;
      }
      _goToStep(1);
      return;
    }
    if (_currentStep == 1) {
      if (_serviceType == null) {
        setState(() => _error = 'Elige el tipo de carga para continuar.');
        return;
      }
      if (_cargoCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Describe la carga que necesitas mover.');
        return;
      }
      if ((_cargoWeight ?? 0) <= 0) {
        setState(
            () => _error = 'Ingresa un peso estimado para calcular el precio.');
        return;
      }
      _goToStep(2);
      return;
    }
    if (_currentStep == 2) {
      if (!_timingReady) {
        setState(() => _error = 'Elige cuándo necesitas el flete.');
        return;
      }
      _goToStep(3);
      await _estimatePrice();
      return;
    }
    if (!_priceReady) {
      await _estimatePrice();
      if (mounted && !_priceReady && !_requiresManualQuote) {
        setState(() =>
            _error = 'No pudimos calcular el precio. Intenta nuevamente.');
      }
      return;
    }
    await _submit();
  }

  Future<bool> _ensureClientSession() async {
    if (!ref.read(authProvider).isAuthenticated) {
      await ref.read(authProvider.notifier).checkAuth();
    }
    final user = ref.read(authProvider).user;
    if (user == null) {
      if (mounted) {
        setState(() => _error = 'Tu sesión expiró. Vuelve a iniciar sesión.');
      }
      return false;
    }
    if (user.role != 'client') {
      if (mounted) {
        setState(() {
          _error =
              'Esta cuenta no puede solicitar fletes. Usa una cuenta de cliente.';
        });
      }
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!await _ensureClientSession() ||
        !_routeReady ||
        !_cargoReady ||
        !_timingReady) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      DateTime? scheduledAt;
      if (!_isUrgent) {
        scheduledAt = DateTime(
          _scheduledDate!.year,
          _scheduledDate!.month,
          _scheduledDate!.day,
          _scheduledTime!.hour,
          _scheduledTime!.minute,
        );
      }
      final cargo = _cargoCtrl.text.trim();
      if (_quoteId == null) {
        await _estimatePrice();
        if (!mounted || _quoteId == null) {
          setState(() => _error =
              'No pudimos confirmar la tarifa. Reintenta el calculo.');
          return;
        }
      }
      await _freightService.createFreight(
        originAddress: _originCtrl.text.trim(),
        originLat: _originLatLng!.latitude,
        originLng: _originLatLng!.longitude,
        destinationAddress: _destCtrl.text.trim(),
        destinationLat: _destLatLng!.latitude,
        destinationLng: _destLatLng!.longitude,
        cargoDescription: cargo,
        cargoWeightKg: _cargoWeight!,
        cargoVolumeM3: _cargoVolume,
        serviceType: _serviceTypeApiValue,
        quoteId: _quoteId,
        requiresHelpers: _helpers,
        isUrgent: _isUrgent,
        scheduledAt: scheduledAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isUrgent
                ? 'Flete solicitado. Buscaremos un conductor.'
                : 'Flete programado correctamente.',
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/app/client/freights');
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = apiErrorMessage(
            error,
            fallback: 'No pudimos crear el flete. Intenta nuevamente.',
          );
          _quoteId = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleBack() async {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/app/client');
    }
  }

  void _showWeightHelp() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿No conoces el peso?',
                style: TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Para darte un precio automático necesitamos una estimación. Usa una aproximación: una lavadora pesa cerca de 70 kg y un sofá de tres cuerpos cerca de 45 kg.',
                style: TextStyle(color: AppTheme.slate600, height: 1.45),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: MuvvGradientButton(
                  label: 'Entendido',
                  compact: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCargoPhotosInfo() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Fotos de la carga',
                style: TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pronto podrás agregar fotos antes de confirmar la solicitud. Por ahora, describe los objetos y su peso para obtener una cotización precisa.',
                style: TextStyle(color: AppTheme.slate600, height: 1.45),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: MuvvGradientButton(
                  label: 'Entendido',
                  compact: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelpersSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ayuda para cargar o descargar',
                style: TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Elige cuántas personas necesitas. El total se actualizará con la cotización real.',
                style: TextStyle(
                  color: AppTheme.slate600,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              for (final value in [0, 1, 2]) ...[
                _HelperChoice(
                  value: value,
                  selected: _helpers == value,
                  onTap: () {
                    _setHelpers(value);
                    Navigator.of(context).pop();
                  },
                ),
                if (value != 2) const SizedBox(height: 9),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showPriceDetails() {
    final format = NumberFormat('#,##0', 'es_CL');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _PriceDetailsSheet(
        format: format,
        basePrice: _basePrice,
        helpersCost: _helpersCost,
        timeCharge: _timeCharge,
        urgencyCharge: _urgencyCharge,
        tolls: _tolls,
        total: _clientPays,
        distanceKm: _distanceKm,
        minimumApplied: _minimumApplied,
      ),
    );
  }

  String get _ctaLabel => switch (_currentStep) {
        0 || 1 => 'Continuar',
        2 => 'Calcular precio',
        _ when _estimating => 'Calculando precio',
        _ when !_priceReady => 'Reintentar cálculo',
        _ => 'Solicitar flete',
      };

  bool get _canUseCta => switch (_currentStep) {
        0 => _routeReady,
        1 => _cargoReady,
        2 => _timingReady,
        _ => !_loading,
      };

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat('#,##0', 'es_CL');
    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentStep > 0) {
          _goToStep(_currentStep - 1);
        }
      },
      child: WebPageScaffold(
        title: 'Solicitar flete',
        subtitle: 'Define ruta, carga y horario',
        leading: IconButton(
          tooltip: _currentStep == 0 ? 'Volver' : 'Paso anterior',
          onPressed: _handleBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        bottomNavigationBar: _FlowBottomBar(
          label: _ctaLabel,
          icon: _currentStep == 3
              ? Icons.local_shipping_outlined
              : Icons.arrow_forward_rounded,
          enabled: _canUseCta,
          loading: _loading || (_currentStep == 3 && _estimating),
          onPressed: _canUseCta ? _continue : null,
        ),
        child: WebPageBody(
          maxWidth: 620,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 122),
          children: [
            _FlowStepper(
              currentStep: _currentStep,
              routeDone: _routeReady,
              cargoDone: _cargoReady,
              timeDone: _timingReady,
              priceDone: _priceReady,
            ),
            const SizedBox(height: 26),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.03, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_currentStep),
                child: _buildCurrentStep(format),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 18),
              _InlineError(message: _error!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep(NumberFormat format) => switch (_currentStep) {
        0 => _buildRouteStep(),
        1 => _buildCargoStep(),
        2 => _buildTimingStep(),
        _ => _buildPriceStep(format),
      };

  Widget _buildRouteStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepIntro(
            title: '¿Desde dónde y hacia dónde?',
            subtitle: 'Ingresa el punto de retiro y destino.',
          ),
          const SizedBox(height: 20),
          MuvvSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _RouteChoice(
                  label: 'Origen',
                  value: _originCtrl.text.isEmpty
                      ? 'Selecciona el punto de retiro'
                      : _originCtrl.text,
                  icon: Icons.my_location_rounded,
                  color: AppTheme.success,
                  onTap: () => _openAddressSelector(origin: true),
                  mapTap: () => _openMapSelector(origin: true),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _requestLocation,
                    icon: const Icon(Icons.gps_fixed_rounded, size: 16),
                    label: const Text('Usar ubicación actual'),
                  ),
                ),
                const Divider(height: 20),
                _RouteChoice(
                  label: 'Destino',
                  value: _destCtrl.text.isEmpty
                      ? '¿A dónde llevamos tu carga?'
                      : _destCtrl.text,
                  icon: Icons.location_on_rounded,
                  color: AppTheme.primary,
                  onTap: () => _openAddressSelector(origin: false),
                  mapTap: () => _openMapSelector(origin: false),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _showMap
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _MapSection(
                      initialPosition: _selectingOrigin
                          ? (_originLatLng ?? _santiago)
                          : (_destLatLng ?? _originLatLng ?? _santiago),
                      selectingOrigin: _selectingOrigin,
                      markers: _markers,
                      polylines: _polylines,
                      onMapCreated: (controller) => _mapController = controller,
                      onTap: _onMapTap,
                      onToggle: (origin) =>
                          setState(() => _selectingOrigin = origin),
                      onClose: () => setState(() => _showMap = false),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );

  Widget _buildCargoStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepIntro(
            title: '¿Qué necesitas mover?',
            subtitle:
                'Cuéntanos sobre tu carga para recomendar el servicio adecuado.',
          ),
          const SizedBox(height: 24),
          const _CargoSectionTitle(
            title: 'Tipo de servicio',
            subtitle: 'Elige la opción que mejor describe tu carga.',
          ),
          const SizedBox(height: 12),
          _ServiceTypeGrid(
            selected: _serviceType,
            onSelected: _setServiceType,
          ),
          const SizedBox(height: 25),
          const _CargoSectionTitle(title: 'Descripción de la carga'),
          const SizedBox(height: 10),
          MuvvSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _cargoCtrl,
                  minLines: 4,
                  maxLines: 4,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {
                    _clearEstimate();
                    _error = null;
                  }),
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    hintText:
                        'Ej: una lavadora, una mesa de comedor, 4 cajas y una silla',
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const _CargoSectionTitle(title: 'Peso aproximado'),
          const SizedBox(height: 10),
          MuvvSurfaceCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              children: [
                TextFormField(
                  controller: _weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  onChanged: (_) => setState(() {
                    _clearEstimate();
                    _error = null;
                  }),
                  decoration: const InputDecoration(
                    hintText: 'Ej: 70',
                    prefixIcon: Icon(Icons.scale_outlined),
                    suffixText: 'kg',
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _showWeightHelp,
                    icon: const Icon(Icons.lightbulb_outline_rounded, size: 16),
                    label: const Text('No sé el peso'),
                  ),
                ),
              ],
            ),
           ),
           const SizedBox(height: 18),
          const _CargoSectionTitle(title: 'Volumen estimado (opcional)'),
          const SizedBox(height: 10),
          MuvvSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: TextFormField(
              controller: _volumeCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              onChanged: (_) => setState(() {
                _clearEstimate();
                _error = null;
              }),
              decoration: const InputDecoration(
                hintText: 'Ej: 2.5',
                prefixIcon: Icon(Icons.inventory_2_outlined),
                suffixText: 'm3',
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _CargoQuickAction(
                  icon: Icons.photo_camera_outlined,
                  title: 'Fotos de la carga',
                  detail: 'Pronto',
                  onTap: _showCargoPhotosInfo,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CargoQuickAction(
                  icon: Icons.people_outline_rounded,
                  title: 'Ayudante de carga',
                  detail: _helpersSummary,
                  selected: _helpers > 0,
                  onTap: _showHelpersSheet,
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildTimingStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepIntro(
            title: '¿Cuándo necesitas el flete?',
            subtitle: 'Elige si lo necesitas ahora o prefieres programarlo.',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _TimeChoice(
                  icon: Icons.flash_on_rounded,
                  title: 'Ahora',
                  subtitle: 'Buscaremos un conductor disponible.',
                  selected: _isUrgent,
                  urgent: true,
                  onTap: () => _selectTiming(urgent: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeChoice(
                  icon: Icons.calendar_month_rounded,
                  title: 'Programar',
                  subtitle: 'Elige fecha y hora.',
                  selected: !_isUrgent,
                  onTap: () => _selectTiming(urgent: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_isUrgent)
            MuvvSurfaceCard(
              padding: const EdgeInsets.all(16),
              borderColor: AppTheme.urgent.withValues(alpha: 0.35),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.urgent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: AppTheme.urgent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Modo urgente',
                          style: TextStyle(
                            color: AppTheme.midnight,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Priorizaremos la búsqueda de un conductor.',
                          style: TextStyle(
                            color: AppTheme.slate600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: true,
                    activeTrackColor: AppTheme.urgent,
                    onChanged: (_) => _selectTiming(urgent: false),
                  ),
                ],
              ),
            )
          else
            MuvvSurfaceCard(
              padding: const EdgeInsets.all(16),
              onTap: _pickDate,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fecha y hora',
                          style: TextStyle(
                            color: AppTheme.midnight,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _scheduledLabel,
                          style: TextStyle(
                            color: _scheduledDate == null
                                ? AppTheme.slate400
                                : AppTheme.slate600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.slate400,
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _buildPriceStep(NumberFormat format) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepIntro(
            title: 'Revisa tu flete',
            subtitle: 'Confirmarás el precio antes de buscar un conductor.',
          ),
          const SizedBox(height: 20),
          _ReviewCard(
            origin: _originCtrl.text,
            destination: _destCtrl.text,
            service: _serviceType,
            cargo: _cargoCtrl.text.trim(),
            weight: _cargoWeight,
            helpers: _helpers,
            isUrgent: _isUrgent,
            scheduledLabel: _scheduledLabel,
          ),
          const SizedBox(height: 16),
          MuvvSurfaceCard(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: AppTheme.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          _recommendedVehicleName == null
                              ? 'Asignacion inteligente'
                              : 'Vehiculo recomendado',
                        style: TextStyle(
                          color: AppTheme.midnight,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                          _recommendedVehicleName == null
                              ? 'Buscaremos un vehiculo compatible con tu carga.'
                              : '$_recommendedVehicleName. Ideal para transportar tu carga de forma segura.',
                        style: TextStyle(
                          color: AppTheme.slate600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_estimating)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 38),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    SizedBox(height: 14),
                    Text(
                      'Calculando tu precio...',
                      style: TextStyle(
                        color: AppTheme.midnight,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Estamos analizando la ruta y el vehiculo adecuado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.slate600, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (_requiresManualQuote)
            const _ManualQuoteRequired()
          else if (_clientPays != null)
            _EstimatePriceHero(
              amount: '\$${format.format(_clientPays)} CLP',
              distanceKm: _distanceKm,
              durationText: _durationText,
              minimumApplied: _minimumApplied,
              onDetails: _showPriceDetails,
            )
          else
            _PriceUnavailable(onRetry: _estimatePrice),
        ],
      );
}

class _FlowStepper extends StatelessWidget {
  final int currentStep;
  final bool routeDone;
  final bool cargoDone;
  final bool timeDone;
  final bool priceDone;

  const _FlowStepper({
    required this.currentStep,
    required this.routeDone,
    required this.cargoDone,
    required this.timeDone,
    required this.priceDone,
  });

  @override
  Widget build(BuildContext context) {
    final steps = [
      _FlowStep('Ruta', Icons.route_rounded, routeDone),
      _FlowStep('Carga', Icons.inventory_2_outlined, cargoDone),
      _FlowStep('Tiempo', Icons.schedule_rounded, timeDone),
      _FlowStep('Precio', Icons.payments_outlined, priceDone),
    ];
    return Row(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          Expanded(
            child: _FlowStepIndicator(
              step: steps[index],
              active: currentStep == index,
              reached: currentStep > index,
            ),
          ),
          if (index < steps.length - 1)
            Container(
              width: 15,
              height: 2,
              color: currentStep > index ? AppTheme.primary : AppTheme.slate200,
            ),
        ],
      ],
    );
  }
}

class _FlowStep {
  final String label;
  final IconData icon;
  final bool done;

  const _FlowStep(this.label, this.icon, this.done);
}

class _FlowStepIndicator extends StatelessWidget {
  final _FlowStep step;
  final bool active;
  final bool reached;

  const _FlowStepIndicator({
    required this.step,
    required this.active,
    required this.reached,
  });

  @override
  Widget build(BuildContext context) {
    final highlighted = active || reached || step.done;
    final color = highlighted ? AppTheme.primary : AppTheme.slate400;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: highlighted
                ? AppTheme.primary.withValues(alpha: 0.10)
                : AppTheme.slate100,
            shape: BoxShape.circle,
            border: Border.all(
              color: highlighted
                  ? AppTheme.primary.withValues(alpha: 0.35)
                  : AppTheme.slate200,
            ),
          ),
          child: Icon(
            (reached || step.done) ? Icons.check_rounded : step.icon,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StepIntro extends StatelessWidget {
  final String title;
  final String subtitle;

  const _StepIntro({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.midnight,
              fontSize: 25,
              height: 1.12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.slate600,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      );
}

class _RouteChoice extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback mapTap;

  const _RouteChoice({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.mapTap,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppTheme.slate400,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: value.startsWith('¿') ||
                                value.startsWith('Selecciona')
                            ? AppTheme.slate400
                            : AppTheme.midnight,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Elegir en el mapa',
            onPressed: mapTap,
            icon: const Icon(Icons.map_outlined, color: AppTheme.slate400),
          ),
          IconButton(
            tooltip: 'Buscar dirección',
            onPressed: onTap,
            icon: const Icon(Icons.chevron_right_rounded,
                color: AppTheme.primary),
          ),
        ],
      );
}

class _CargoSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _CargoSectionTitle({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.midnight,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                color: AppTheme.slate600,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      );
}

class _CargoQuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  const _CargoQuickAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            height: 88,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.08)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.slate200,
                width: selected ? 1.15 : 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: AppTheme.primary),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.midnight,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppTheme.primary : AppTheme.slate400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ServiceTypeGrid extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelected;

  const _ServiceTypeGrid({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const options = [
      _ServiceOption(
        'Paquetería',
        Icons.inventory_2_outlined,
        accent: Color(0xFF1687E8),
        background: Color(0xFFEAF5FF),
        selectedBackground: Color(0xFFD9EEFF),
      ),
      _ServiceOption(
        'Mudanza',
        Icons.local_shipping_outlined,
        accent: AppTheme.primary,
        background: Color(0xFFE9F0FF),
        selectedBackground: Color(0xFFDCE8FF),
      ),
      _ServiceOption(
        'Hogar u oficina',
        Icons.chair_outlined,
        accent: Color(0xFF0B9C73),
        background: Color(0xFFE9F8F0),
        selectedBackground: Color(0xFFD9F3E5),
      ),
      _ServiceOption(
        'Envío urgente',
        Icons.bolt_outlined,
        accent: Color(0xFFE7612D),
        background: Color(0xFFFFF0E9),
        selectedBackground: Color(0xFFFFE3D6),
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      primary: false,
      mainAxisSpacing: 11,
      crossAxisSpacing: 11,
      childAspectRatio: 1.55,
      children: [
        for (final option in options)
          _ServiceOptionTile(
            option: option,
            selected: selected == option.label,
            onTap: () => onSelected(option.label),
          ),
      ],
    );
  }
}

class _ServiceOption {
  final String label;
  final IconData icon;
  final Color accent;
  final Color background;
  final Color selectedBackground;

  const _ServiceOption(
    this.label,
    this.icon, {
    required this.accent,
    required this.background,
    required this.selectedBackground,
  });
}

class _ServiceOptionTile extends StatelessWidget {
  final _ServiceOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ServiceOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? option.selectedBackground : option.background,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? AppTheme.primary
                  : option.accent.withValues(alpha: 0.18),
              width: selected ? 1.7 : 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : option.accent.withValues(alpha: 0.045),
                blurRadius: selected ? 14 : 8,
                offset: Offset(0, selected ? 5 : 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: option.accent.withValues(
                        alpha: selected ? 0.19 : 0.13,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      option.icon,
                      size: 22,
                      color: option.accent,
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                option.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelperChoice extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _HelperChoice({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (value) {
      0 => 'Sin ayudante',
      1 => '1 ayudante',
      _ => '2 ayudantes',
    };
    final description = switch (value) {
      0 => 'Solo necesito transporte.',
      1 => 'Apoyo para cargar o descargar.',
      _ => 'Apoyo adicional para carga pesada.',
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.08)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.slate200,
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  value == 0
                      ? Icons.person_outline_rounded
                      : Icons.people_outline_rounded,
                  color: selected ? AppTheme.primary : AppTheme.slate600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? AppTheme.primary : AppTheme.midnight,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppTheme.slate600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool urgent;
  final VoidCallback onTap;

  const _TimeChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.urgent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = urgent ? AppTheme.urgent : AppTheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          height: 142,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.07) : Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected ? color : AppTheme.slate200,
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? color : AppTheme.slate600, size: 23),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  color: selected ? color : AppTheme.midnight,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.slate600, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String origin;
  final String destination;
  final String? service;
  final String cargo;
  final double? weight;
  final int helpers;
  final bool isUrgent;
  final String scheduledLabel;

  const _ReviewCard({
    required this.origin,
    required this.destination,
    required this.service,
    required this.cargo,
    required this.weight,
    required this.helpers,
    required this.isUrgent,
    required this.scheduledLabel,
  });

  @override
  Widget build(BuildContext context) => MuvvSurfaceCard(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen del servicio',
              style: TextStyle(
                color: AppTheme.midnight,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 16),
            MuvvRouteStops(
                origin: origin, destination: destination, compact: true),
            const Divider(height: 26),
            if (service != null)
              _ReviewLine(Icons.inventory_2_outlined, service!),
            _ReviewLine(
              Icons.description_outlined,
              cargo,
              subtitle:
                  weight == null ? null : '${weight!.toStringAsFixed(0)} kg',
            ),
            _ReviewLine(
              isUrgent ? Icons.flash_on_rounded : Icons.schedule_rounded,
              isUrgent ? 'Ahora · modo urgente' : scheduledLabel,
            ),
            if (helpers > 0)
              _ReviewLine(
                Icons.people_outline_rounded,
                helpers == 1 ? '1 ayudante' : '$helpers ayudantes',
              ),
          ],
        ),
      );
}

class _ReviewLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;

  const _ReviewLine(this.icon, this.label, {this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppTheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subtitle == null ? label : '$label · $subtitle',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.slate600,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
}

class _EstimatePriceHero extends StatelessWidget {
  final String amount;
  final double? distanceKm;
  final String? durationText;
  final bool minimumApplied;
  final VoidCallback onDetails;

  const _EstimatePriceHero({
    required this.amount,
    required this.distanceKm,
    required this.durationText,
    required this.minimumApplied,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF0F5FF), Color(0xFFF9FBFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Precio estimado por Muvv',
              style: TextStyle(
                color: AppTheme.slate600,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              amount,
              style: const TextStyle(
                color: AppTheme.midnight,
                fontSize: 31,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Considera la ruta y las opciones que seleccionaste.',
              style: TextStyle(color: AppTheme.slate600, fontSize: 13),
            ),
            if (distanceKm != null || durationText != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 13,
                runSpacing: 6,
                children: [
                  if (distanceKm != null)
                    _PriceMeta(Icons.route_rounded,
                        '${distanceKm!.toStringAsFixed(1)} km'),
                  if (durationText != null)
                    _PriceMeta(Icons.schedule_rounded, durationText!),
                ],
              ),
            ],
            if (minimumApplied) ...[
              const SizedBox(height: 10),
              const Text(
                'Se aplicó la tarifa mínima vigente.',
                style: TextStyle(color: AppTheme.slate600, fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onDetails,
              icon: const Icon(Icons.receipt_long_outlined, size: 17),
              label: const Text('Ver detalle del precio'),
            ),
          ],
        ),
      );
}

class _PriceMeta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PriceMeta(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.primary),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(color: AppTheme.slate600, fontSize: 12)),
        ],
      );
}

class _ManualQuoteRequired extends StatelessWidget {
  const _ManualQuoteRequired();

  @override
  Widget build(BuildContext context) => MuvvSurfaceCard(
        padding: const EdgeInsets.all(20),
        child: const Column(
          children: [
            Icon(Icons.request_quote_outlined,
                color: AppTheme.primary, size: 32),
            SizedBox(height: 12),
            Text(
              'Este flete necesita una cotizacion personalizada',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.midnight,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'La carga requiere una revision antes de definir una tarifa segura.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.slate600, fontSize: 13),
            ),
          ],
        ),
      );
}

class _PriceUnavailable extends StatelessWidget {
  final VoidCallback onRetry;

  const _PriceUnavailable({required this.onRetry});

  @override
  Widget build(BuildContext context) => MuvvSurfaceCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.price_check_outlined,
                color: AppTheme.slate400, size: 30),
            const SizedBox(height: 10),
            const Text(
              'No pudimos calcular el precio',
              style: TextStyle(
                  color: AppTheme.midnight, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Estamos teniendo problemas para obtener la tarifa. Intentalo nuevamente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.slate600, fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar cálculo'),
            ),
          ],
        ),
      );
}

class _PriceDetailsSheet extends StatelessWidget {
  final NumberFormat format;
  final double? basePrice;
  final double? helpersCost;
  final double? timeCharge;
  final double? urgencyCharge;
  final double? tolls;
  final double? total;
  final double? distanceKm;
  final bool minimumApplied;

  const _PriceDetailsSheet({
    required this.format,
    required this.basePrice,
    required this.helpersCost,
    required this.timeCharge,
    required this.urgencyCharge,
    required this.tolls,
    required this.total,
    required this.distanceKm,
    required this.minimumApplied,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Detalle del precio',
                style: TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              if (basePrice != null)
                _PriceDetailRow(
                    'Tarifa calculada', '\$${format.format(basePrice)} CLP'),
              if (timeCharge != null && timeCharge! > 0)
                _PriceDetailRow(
                    'Tiempo estimado', '\$${format.format(timeCharge)} CLP'),
              if (helpersCost != null && helpersCost! > 0)
                _PriceDetailRow(
                    'Ayudantes', '\$${format.format(helpersCost)} CLP'),
              if (urgencyCharge != null && urgencyCharge! > 0)
                _PriceDetailRow(
                    'Urgencia', '\$${format.format(urgencyCharge)} CLP'),
              if (tolls != null && tolls! > 0)
                _PriceDetailRow('Peajes', '\$${format.format(tolls)} CLP'),
              if (distanceKm != null)
                _PriceDetailRow(
                    'Distancia', '${distanceKm!.toStringAsFixed(1)} km'),
              if (minimumApplied)
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Text(
                    'El cálculo considera la tarifa mínima vigente.',
                    style: TextStyle(color: AppTheme.slate600, fontSize: 12),
                  ),
                ),
              const Divider(height: 25),
              _PriceDetailRow(
                'Total estimado',
                total == null ? '—' : '\$${format.format(total)} CLP',
                prominent: true,
              ),
            ],
          ),
        ),
      );
}

class _PriceDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool prominent;

  const _PriceDetailRow(this.label, this.value, {this.prominent = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: prominent ? AppTheme.midnight : AppTheme.slate600,
                  fontWeight: prominent ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: AppTheme.midnight,
                fontWeight: prominent ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.error, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _FlowBottomBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final bool loading;
  final VoidCallback? onPressed;

  const _FlowBottomBar({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: SizedBox(
          height: 78,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                top: BorderSide(color: AppTheme.slate200, width: 0.7),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                height: 54,
                child: MuvvGradientButton(
                  label: label,
                  icon: icon,
                  isLoading: loading,
                  onPressed: enabled && !loading ? onPressed : null,
                ),
              ),
            ),
          ),
        ),
      );
}

class _MapSection extends StatelessWidget {
  final LatLng initialPosition;
  final bool selectingOrigin;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<LatLng> onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onClose;

  const _MapSection({
    required this.initialPosition,
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
        height: 255,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: initialPosition, zoom: 13),
              onMapCreated: onMapCreated,
              onTap: onTap,
              markers: markers,
              polylines: polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  Expanded(
                    child: _MapModeButton(
                      label: 'Marcar origen',
                      selected: selectingOrigin,
                      color: AppTheme.success,
                      onTap: () => onToggle(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MapModeButton(
                      label: 'Marcar destino',
                      selected: !selectingOrigin,
                      color: AppTheme.primary,
                      onTap: () => onToggle(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: IconButton(
                      tooltip: 'Cerrar mapa',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MapModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _MapModeButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4)
              ],
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.midnight,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
}

class _SelectedAddress {
  final String address;
  final LatLng position;

  const _SelectedAddress({required this.address, required this.position});
}

class _AddressSearchSheet extends StatefulWidget {
  final String title;
  final LatLng? initialPosition;

  const _AddressSearchSheet({
    required this.title,
    required this.initialPosition,
  });

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  final _controller = TextEditingController();
  final _placesService = PlacesService();
  final _sessionToken = const Uuid().v4();
  Timer? _debounce;
  int _request = 0;
  bool _loading = false;
  List<PlaceSuggestion> _suggestions = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final request = ++_request;
    if (query.length < 3) {
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final suggestions = await _placesService.autocomplete(
          query,
          sessionToken: _sessionToken,
          latitude: widget.initialPosition?.latitude,
          longitude: widget.initialPosition?.longitude,
        );
        if (!mounted || request != _request) return;
        setState(() => _suggestions = suggestions);
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() => _suggestions = const []);
      } finally {
        if (mounted && request == _request) {
          setState(() => _loading = false);
        }
      }
    });
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    setState(() => _loading = true);
    try {
      final place = await _placesService.getAddress(
        suggestion.placeId,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        _SelectedAddress(
          address: place.address,
          position: LatLng(place.latitude, place.longitude),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos cargar esa dirección.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        heightFactor: 0.86,
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.slate200,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 17),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: AppTheme.midnight,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    onChanged: _onChanged,
                    decoration: const InputDecoration(
                      hintText: 'Busca una dirección',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primary),
                          )
                        : _suggestions.isEmpty
                            ? Center(
                                child: Text(
                                  _controller.text.trim().length < 3
                                      ? 'Escribe al menos 3 letras para buscar.'
                                      : 'No encontramos direcciones. Prueba con otra búsqueda.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppTheme.slate600,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _suggestions.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final suggestion = _suggestions[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 5,
                                    ),
                                    leading: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.location_on_outlined,
                                        color: AppTheme.primary,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      suggestion.label,
                                      style: const TextStyle(
                                        color: AppTheme.midnight,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      suggestion.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.slate600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    onTap: () => _select(suggestion),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
