import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/driver_onboarding_provider.dart';
import '../../models/driver_model.dart';
import '../../core/theme/app_theme.dart';

class DriverOnboardingScreen extends ConsumerStatefulWidget {
  const DriverOnboardingScreen({super.key});
  @override
  ConsumerState<DriverOnboardingScreen> createState() =>
      _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState
    extends ConsumerState<DriverOnboardingScreen> {

  int _step = 0; // 0=foto, 1=licencia, 2=padrón, 3=vehículo

  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(onboardingProvider.notifier).load());
  }

  Future<File?> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    return picked != null ? File(picked.path) : null;
  }

  void _showPickerSheet(BuildContext ctx,
      Future<void> Function(File) onPicked) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20,
            MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.slate200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SheetOption(
              icon: Icons.camera_alt_outlined,
              label: 'Tomar foto',
              onTap: () async {
                Navigator.pop(ctx);
                final f = await _pickImage(ImageSource.camera);
                if (f != null) await onPicked(f);
              },
            ),
            const SizedBox(height: 8),
            _SheetOption(
              icon: Icons.photo_library_outlined,
              label: 'Elegir de galería',
              onTap: () async {
                Navigator.pop(ctx);
                final f = await _pickImage(ImageSource.gallery);
                if (f != null) await onPicked(f);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state  = ref.watch(onboardingProvider);
    final driver = state.driver;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator(
                color: AppTheme.primary))
            : _buildContent(context, driver),
      ),
    );
  }

  Widget _buildContent(BuildContext ctx, DriverModel? driver) {
    if (driver == null) {
      return const Center(
          child: Text('Cargando...'));
    }

    // Si ya envió y está en revisión/aprobado/rechazado
    if (!driver.isPending && !driver.onboardingComplete) {
      return _StatusScreen(driver: driver);
    }

    // Onboarding por pasos
    return Column(
      children: [
        // Barra de progreso
        _ProgressBar(step: _step, total: 4),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _stepContent(ctx, driver),
          ),
        ),
      ],
    );
  }

  Widget _stepContent(BuildContext ctx, DriverModel driver) {
    switch (_step) {
      case 0:
        return _PhotoStep(
          imageUrl: driver.profileImageUrl,
          onPick: () => _showPickerSheet(ctx, (f) async {
            await ref
                .read(onboardingProvider.notifier)
                .uploadProfileImage(f);
            if (mounted) setState(() => _step = 1);
          }),
        );
      case 1:
        return _DocumentStep(
          title:    'Licencia de conducir',
          subtitle: 'Sube una foto clara de tu licencia vigente',
          icon:     Icons.badge_outlined,
          imageUrl: driver.licenseImageUrl,
          onPick:   () => _showPickerSheet(ctx, (f) async {
            await ref
                .read(onboardingProvider.notifier)
                .uploadLicense(f);
            if (mounted) setState(() => _step = 2);
          }),
        );
      case 2:
        return _DocumentStep(
          title:    'Padrón del vehículo',
          subtitle: 'Fotografía del documento de circulación',
          icon:     Icons.article_outlined,
          imageUrl: driver.vehicleDocUrl,
          onPick:   () => _showPickerSheet(ctx, (f) async {
            await ref
                .read(onboardingProvider.notifier)
                .uploadVehicleDoc(f);
            if (mounted) setState(() => _step = 3);
          }),
        );
      case 3:
        return _VehicleStep(
          vehicles: driver.vehicles,
          onAdd:    (v) async {
            await ref
                .read(onboardingProvider.notifier)
                .addVehicle(v);
          },
          onSubmit: () async {
            await ref
                .read(onboardingProvider.notifier)
                .submitForReview();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Status screen ───────────────────────────────────────────

class _StatusScreen extends StatelessWidget {
  final DriverModel driver;
  const _StatusScreen({required this.driver});

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    late final String title, subtitle;

    if (driver.isUnderReview) {
      icon     = Icons.hourglass_top_rounded;
      color    = AppTheme.warning;
      title    = 'En revisión';
      subtitle = 'Estamos verificando tus documentos.\n'
          'Te notificaremos cuando esté listo.';
    } else if (driver.isApproved) {
      icon     = Icons.check_circle_rounded;
      color    = AppTheme.success;
      title    = 'Cuenta aprobada';
      subtitle = 'Ya puedes recibir fletes. Activa el modo en línea.';
    } else {
      icon     = Icons.cancel_rounded;
      color    = AppTheme.error;
      title    = 'Cuenta rechazada';
      subtitle = driver.rejectionReason ??
          'Contáctate con soporte para más información.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.midnight,
                )),
            const SizedBox(height: 10),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.slate400,
                  height: 1.6,
                )),
            if (driver.isRejected) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Reintentar con nuevos documentos'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Progress bar ────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final int step, total;
  const _ProgressBar({required this.step, required this.total});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Completa tu perfil',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.midnight,
                )),
            Text('${step + 1} de $total',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.slate400,
                )),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (step + 1) / total,
            backgroundColor: AppTheme.slate200,
            color: AppTheme.primary,
            minHeight: 4,
          ),
        ),
      ],
    ),
  );
}

// ── Step: foto de perfil ────────────────────────────────────

class _PhotoStep extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback onPick;
  const _PhotoStep({this.imageUrl, required this.onPick});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 20),
      const Text('Foto de perfil',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.midnight,
          )),
      const SizedBox(height: 8),
      const Text(
        'Sube una foto clara de tu rostro.\nSin lentes ni accesorios.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: AppTheme.slate400,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 32),
      GestureDetector(
        onTap: onPick,
        child: Container(
          width: 140, height: 140,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: imageUrl != null
                  ? AppTheme.success
                  : AppTheme.primary.withValues(alpha: 0.3),
              width: imageUrl != null ? 2 : 1,
            ),
          ),
          child: imageUrl != null
              ? ClipOval(
                  child: Image.network(imageUrl!,
                      fit: BoxFit.cover))
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.camera_alt_rounded,
                        size: 36, color: AppTheme.primary),
                    const SizedBox(height: 6),
                    Text('Subir foto',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                        )),
                  ],
                ),
        ),
      ),
      if (imageUrl != null) ...[
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 16, color: AppTheme.success),
            const SizedBox(width: 6),
            const Text('Foto cargada',
                style: TextStyle(
                  color: AppTheme.success,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      ],
    ],
  );
}

// ── Step: documento ─────────────────────────────────────────

class _DocumentStep extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final String? imageUrl;
  final VoidCallback onPick;
  const _DocumentStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.imageUrl,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Text(title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.midnight,
          )),
      const SizedBox(height: 8),
      Text(subtitle,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.slate400,
            height: 1.5,
          )),
      const SizedBox(height: 24),
      GestureDetector(
        onTap: onPick,
        child: Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            color: imageUrl != null
                ? AppTheme.success.withValues(alpha: 0.04)
                : AppTheme.primary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: imageUrl != null
                  ? AppTheme.success.withValues(alpha: 0.4)
                  : AppTheme.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(imageUrl!,
                      fit: BoxFit.cover))
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 40,
                        color: AppTheme.primary),
                    const SizedBox(height: 10),
                    const Text('Toca para subir',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w500,
                        )),
                    const SizedBox(height: 4),
                    const Text('JPG, PNG o PDF',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.slate400,
                        )),
                  ],
                ),
        ),
      ),
      if (imageUrl != null) ...[
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.check_circle_rounded,
              size: 16, color: AppTheme.success),
          const SizedBox(width: 6),
          Text('$title cargada',
              style: const TextStyle(
                color: AppTheme.success,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              )),
        ]),
      ],
    ],
  );
}

// ── Step: vehículo ──────────────────────────────────────────

class _VehicleStep extends StatefulWidget {
  final List<VehicleModel> vehicles;
  final Future<void> Function(VehicleModel) onAdd;
  final Future<void> Function() onSubmit;
  const _VehicleStep({
    required this.vehicles,
    required this.onAdd,
    required this.onSubmit,
  });
  @override
  State<_VehicleStep> createState() => _VehicleStepState();
}

class _VehicleStepState extends State<_VehicleStep> {
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl  = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _adding     = false;

  @override
  void dispose() {
    _brandCtrl.dispose(); _modelCtrl.dispose();
    _yearCtrl.dispose();  _plateCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      const Text('Tu vehículo',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.midnight,
          )),
      const SizedBox(height: 8),
      const Text('Agrega los datos del vehículo con el que trabajarás.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.slate400,
            height: 1.5,
          )),
      const SizedBox(height: 20),

      // Vehículos agregados
      ...widget.vehicles.map((v) => _VehicleCard(vehicle: v)),

      // Formulario nuevo vehículo
      if (!_adding && widget.vehicles.isEmpty)
        _buildForm(context),

      if (!_adding && widget.vehicles.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => setState(() => _adding = true),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Agregar otro vehículo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            minimumSize: const Size(double.infinity, 46),
            side: BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),

      if (_adding) _buildForm(context),

      const SizedBox(height: 24),

      if (widget.vehicles.isNotEmpty)
        ElevatedButton(
          onPressed: widget.onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: const Text('Enviar para revisión',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              )),
        ),
    ],
  );

  Widget _buildForm(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: AppTheme.slate200, width: 0.5),
    ),
    child: Column(children: [
      _Field(ctrl: _brandCtrl, label: 'Marca',
          hint: 'Toyota'),
      const SizedBox(height: 10),
      _Field(ctrl: _modelCtrl, label: 'Modelo',
          hint: 'Hilux'),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _Field(ctrl: _yearCtrl,
              label: 'Año', hint: '2020',
              keyboard: TextInputType.number),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Field(ctrl: _plateCtrl,
              label: 'Patente', hint: 'ABCD12'),
        ),
      ]),
      const SizedBox(height: 10),
      _Field(ctrl: _colorCtrl, label: 'Color',
          hint: 'Blanco'),
      const SizedBox(height: 14),
      ElevatedButton(
        onPressed: () async {
          if (_brandCtrl.text.isEmpty ||
              _modelCtrl.text.isEmpty ||
              _plateCtrl.text.isEmpty) return;
          final v = VehicleModel(
            brand: _brandCtrl.text,
            model: _modelCtrl.text,
            year:  int.tryParse(_yearCtrl.text) ??
                DateTime.now().year,
            plate: _plateCtrl.text.toUpperCase(),
            color: _colorCtrl.text,
          );
          await widget.onAdd(v);
          _brandCtrl.clear(); _modelCtrl.clear();
          _yearCtrl.clear();  _plateCtrl.clear();
          _colorCtrl.clear();
          if (mounted) setState(() => _adding = false);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.success,
          minimumSize: const Size(double.infinity, 46),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: const Text('Agregar vehículo'),
      ),
    ]),
  );
}

class _VehicleCard extends StatelessWidget {
  final VehicleModel vehicle;
  const _VehicleCard({required this.vehicle});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.success.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: AppTheme.success.withValues(alpha: 0.25),
        width: 0.8,
      ),
    ),
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.local_shipping_outlined,
            size: 20, color: AppTheme.success),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${vehicle.brand} ${vehicle.model} ${vehicle.year}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.midnight,
                )),
            Text('${vehicle.plate} · ${vehicle.color}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.slate400,
                )),
          ],
        ),
      ),
      const Icon(Icons.check_circle_rounded,
          size: 18, color: AppTheme.success),
    ]),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final TextInputType? keyboard;
  const _Field({
    required this.ctrl,
    required this.label,
    required this.hint,
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate400,
            letterSpacing: 0.4,
          )),
      const SizedBox(height: 4),
      TextField(
        controller:   ctrl,
        keyboardType: keyboard,
        style: const TextStyle(
            fontSize: 14, color: AppTheme.midnight),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              fontSize: 14, color: AppTheme.slate400),
          filled: true,
          fillColor: const Color(0xFFF4F6F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
        ),
      ),
    ],
  );
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.slate100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: AppTheme.midnight),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.midnight,
            )),
      ]),
    ),
  );
}