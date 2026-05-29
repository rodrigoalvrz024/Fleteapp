import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../models/driver_model.dart';
import '../../providers/driver_onboarding_provider.dart';

class DriverOnboardingScreen extends ConsumerStatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  ConsumerState<DriverOnboardingScreen> createState() =>
      _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState
    extends ConsumerState<DriverOnboardingScreen> {
  static const _totalSteps = 5;
  int _step = 0;
  bool _forceEdit = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(onboardingProvider.notifier).load());
  }

  Future<XFile?> _pickImage(ImageSource source) async {
    return ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
  }

  void _showPickerSheet(
    BuildContext context,
    Future<void> Function(XFile) onPicked,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 16),
            _SheetOption(
              icon: Icons.camera_alt_outlined,
              label: 'Tomar foto',
              onTap: () async {
                Navigator.pop(context);
                final file = await _pickImage(ImageSource.camera);
                if (file != null) await onPicked(file);
              },
            ),
            const SizedBox(height: 8),
            _SheetOption(
              icon: Icons.photo_library_outlined,
              label: 'Elegir de galeria',
              onTap: () async {
                Navigator.pop(context);
                final file = await _pickImage(ImageSource.gallery);
                if (file != null) await onPicked(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final driver = state.driver;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: state.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary))
            : _buildContent(context, state, driver),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    OnboardingState state,
    DriverModel? driver,
  ) {
    if (driver == null) {
      return _DriverRegistrationStep(
        error: state.error,
        onSubmit: (rut, licenseNumber, licenseExpiry) =>
            ref.read(onboardingProvider.notifier).registerDriver(
                  rut: rut,
                  licenseNumber: licenseNumber,
                  licenseExpiry: licenseExpiry,
                ),
      );
    }

    if (!_forceEdit &&
        (driver.isUnderReview || driver.isApproved || driver.isRejected)) {
      return _StatusScreen(
        driver: driver,
        onRetry: driver.isRejected
            ? () => setState(() {
                  _forceEdit = true;
                  _step = _firstMissingStep(driver);
                })
            : null,
      );
    }

    return Column(
      children: [
        _ProgressBar(step: _step, total: _totalSteps),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.error != null) ...[
                  _ErrorBanner(message: state.error!),
                  const SizedBox(height: 14),
                ],
                _StepIntro(step: _step),
                const SizedBox(height: 18),
                _stepContent(context, driver),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _firstMissingStep(DriverModel driver) {
    if (driver.licenseImageUrl == null) return 0;
    if (driver.circulationPermitUrl == null && driver.vehicleDocUrl == null) {
      return 1;
    }
    if (driver.technicalReviewUrl == null) return 2;
    if (driver.soapUrl == null) return 3;
    return 4;
  }

  Widget _stepContent(BuildContext context, DriverModel driver) {
    switch (_step) {
      case 0:
        return _DocumentStep(
          title: 'Licencia de conducir',
          subtitle: 'Sube una foto clara de tu licencia vigente.',
          icon: Icons.badge_outlined,
          imageUrl: driver.licenseImageUrl,
          onPick: () => _showPickerSheet(context, (file) async {
            await ref.read(onboardingProvider.notifier).uploadLicense(file);
            if (mounted) setState(() => _step = 1);
          }),
          onNext: driver.licenseImageUrl != null
              ? () => setState(() => _step = 1)
              : null,
        );
      case 1:
        return _DocumentStep(
          title: 'Permiso de circulacion',
          subtitle: 'Sube el permiso vigente del vehiculo que usaras.',
          icon: Icons.article_outlined,
          imageUrl: driver.circulationPermitUrl ?? driver.vehicleDocUrl,
          onPick: () => _showPickerSheet(context, (file) async {
            await ref
                .read(onboardingProvider.notifier)
                .uploadCirculationPermit(file);
            if (mounted) setState(() => _step = 2);
          }),
          onBack: () => setState(() => _step = 0),
          onNext: (driver.circulationPermitUrl != null ||
                  driver.vehicleDocUrl != null)
              ? () => setState(() => _step = 2)
              : null,
        );
      case 2:
        return _DocumentStep(
          title: 'Revision tecnica',
          subtitle: 'Sube la revision tecnica vigente del vehiculo.',
          icon: Icons.fact_check_outlined,
          imageUrl: driver.technicalReviewUrl,
          onPick: () => _showPickerSheet(context, (file) async {
            await ref
                .read(onboardingProvider.notifier)
                .uploadTechnicalReview(file);
            if (mounted) setState(() => _step = 3);
          }),
          onBack: () => setState(() => _step = 1),
          onNext: driver.technicalReviewUrl != null
              ? () => setState(() => _step = 3)
              : null,
        );
      case 3:
        return _DocumentStep(
          title: 'SOAP',
          subtitle: 'Sube el seguro obligatorio vigente.',
          icon: Icons.verified_user_outlined,
          imageUrl: driver.soapUrl,
          onPick: () => _showPickerSheet(context, (file) async {
            await ref.read(onboardingProvider.notifier).uploadSoap(file);
            if (mounted) setState(() => _step = 4);
          }),
          onBack: () => setState(() => _step = 2),
          onNext:
              driver.soapUrl != null ? () => setState(() => _step = 4) : null,
        );
      case 4:
        return _VehicleStep(
          vehicles: driver.vehicles,
          onBack: () => setState(() => _step = 3),
          onAdd: (vehicle) =>
              ref.read(onboardingProvider.notifier).addVehicle(vehicle),
          onSubmit: () =>
              ref.read(onboardingProvider.notifier).submitForReview(),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _DriverRegistrationStep extends StatefulWidget {
  final String? error;
  final Future<void> Function(String rut, String licenseNumber, DateTime expiry)
      onSubmit;

  const _DriverRegistrationStep({
    required this.error,
    required this.onSubmit,
  });

  @override
  State<_DriverRegistrationStep> createState() =>
      _DriverRegistrationStepState();
}

class _DriverRegistrationStepState extends State<_DriverRegistrationStep> {
  final _formKey = GlobalKey<FormState>();
  final _rutCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  DateTime? _expiry;

  @override
  void dispose() {
    _rutCtrl.dispose();
    _licenseCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year + 2, now.month, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 12),
    );
    if (selected == null) return;
    setState(() {
      _expiry = selected;
      _expiryCtrl.text =
          '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.onSubmit(
      _rutCtrl.text.trim(),
      _licenseCtrl.text.trim(),
      _expiry!,
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 16),
          const Text(
            'Validacion de conductor',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.midnight,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Necesitamos estos datos para revisar tu licencia y los documentos del vehiculo. No pediremos biometria ni reconocimiento facial.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.slate400,
            ),
          ),
          const SizedBox(height: 20),
          if (widget.error != null) ...[
            _ErrorBanner(message: widget.error!),
            const SizedBox(height: 14),
          ],
          Form(
            key: _formKey,
            child: Column(
              children: [
                _TextInput(
                  controller: _rutCtrl,
                  label: 'RUT',
                  hint: '12345678-9',
                  validator: (value) => (value?.trim().length ?? 0) >= 8
                      ? null
                      : 'Ingresa tu RUT',
                ),
                const SizedBox(height: 12),
                _TextInput(
                  controller: _licenseCtrl,
                  label: 'Numero de licencia',
                  hint: 'B-123456',
                  validator: (value) => (value?.trim().length ?? 0) >= 4
                      ? null
                      : 'Ingresa tu numero de licencia',
                ),
                const SizedBox(height: 12),
                _TextInput(
                  controller: _expiryCtrl,
                  label: 'Vencimiento de licencia',
                  hint: 'DD/MM/AAAA',
                  readOnly: true,
                  onTap: _pickExpiry,
                  validator: (_) =>
                      _expiry != null ? null : 'Selecciona una fecha vigente',
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Crear perfil de conductor',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _StatusScreen extends StatelessWidget {
  final DriverModel driver;
  final VoidCallback? onRetry;

  const _StatusScreen({required this.driver, this.onRetry});

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    late final String title;
    late final String subtitle;

    if (driver.isUnderReview) {
      icon = Icons.hourglass_top_rounded;
      color = AppTheme.warning;
      title = 'En revision';
      subtitle =
          'Estamos revisando tus documentos. Te avisaremos cuando tu cuenta quede lista.';
    } else if (driver.isApproved) {
      icon = Icons.check_circle_rounded;
      color = AppTheme.success;
      title = 'Cuenta aprobada';
      subtitle =
          'Ya puedes recibir fletes. Activa tu disponibilidad cuando quieras trabajar.';
    } else {
      icon = Icons.cancel_rounded;
      color = AppTheme.error;
      title = 'Revision pendiente';
      subtitle = driver.rejectionReason ??
          'Necesitamos que actualices tus documentos para volver a revisar tu cuenta.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: color),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.midnight,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.slate400,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),
            if (driver.isApproved)
              ElevatedButton(
                onPressed: () => context.go('/app/driver'),
                child: const Text('Ir al panel'),
              )
            else if (onRetry != null)
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Actualizar documentos'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int step;
  final int total;

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
                const Text(
                  'Documentos de conductor',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.midnight,
                  ),
                ),
                Text(
                  '${step + 1} de $total',
                  style:
                      const TextStyle(fontSize: 13, color: AppTheme.slate400),
                ),
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

class _StepIntro extends StatelessWidget {
  final int step;

  const _StepIntro({required this.step});

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Licencia',
      'Permiso',
      'Revision',
      'SOAP',
      'Vehiculo',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(labels.length, (index) {
        final active = index == step;
        final completed = index < step;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.primary.withValues(alpha: 0.10)
                : completed
                    ? AppTheme.success.withValues(alpha: 0.10)
                    : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? AppTheme.primary
                  : completed
                      ? AppTheme.success
                      : AppTheme.slate200,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                completed ? Icons.check_rounded : Icons.circle,
                size: completed ? 14 : 8,
                color: completed
                    ? AppTheme.success
                    : active
                        ? AppTheme.primary
                        : AppTheme.slate400,
              ),
              const SizedBox(width: 6),
              Text(
                labels[index],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? AppTheme.primary
                      : completed
                          ? AppTheme.success
                          : AppTheme.slate400,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _DocumentStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? imageUrl;
  final VoidCallback onPick;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  const _DocumentStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.imageUrl,
    required this.onPick,
    this.onBack,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.midnight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.slate400,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onPick,
            child: Container(
              width: double.infinity,
              height: 190,
              decoration: BoxDecoration(
                color: imageUrl != null
                    ? AppTheme.success.withValues(alpha: 0.04)
                    : AppTheme.primary.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: imageUrl != null
                      ? AppTheme.success.withValues(alpha: 0.4)
                      : AppTheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: imageUrl != null
                  ? _UploadedDocumentPreview(
                      imageUrl: _isPreviewableUrl(imageUrl!) ? imageUrl : null,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 42, color: AppTheme.primary),
                        const SizedBox(height: 10),
                        const Text(
                          'Toca para subir',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'JPG o PNG desde camara o galeria',
                          style:
                              TextStyle(fontSize: 12, color: AppTheme.slate400),
                        ),
                      ],
                    ),
            ),
          ),
          if (imageUrl != null) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 16, color: AppTheme.success),
                SizedBox(width: 6),
                Text(
                  'Documento cargado',
                  style: TextStyle(
                    color: AppTheme.success,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              if (onBack != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onBack,
                    child: const Text('Atras'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: ElevatedButton(
                  onPressed: onNext,
                  child: const Text('Continuar'),
                ),
              ),
            ],
          ),
        ],
      );
}

bool _isPreviewableUrl(String value) =>
    value.startsWith('http://') || value.startsWith('https://');

class _UploadedDocumentPreview extends StatelessWidget {
  final String? imageUrl;

  const _UploadedDocumentPreview({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Image.network(imageUrl!, fit: BoxFit.cover),
      );
    }

    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified_rounded, size: 44, color: AppTheme.success),
        SizedBox(height: 10),
        Text(
          'Documento almacenado de forma privada',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.success,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _VehicleStep extends StatefulWidget {
  final List<VehicleModel> vehicles;
  final VoidCallback onBack;
  final Future<void> Function(VehicleModel) onAdd;
  final Future<void> Function() onSubmit;

  const _VehicleStep({
    required this.vehicles,
    required this.onBack,
    required this.onAdd,
    required this.onSubmit,
  });

  @override
  State<_VehicleStep> createState() => _VehicleStepState();
}

class _VehicleStepState extends State<_VehicleStep> {
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _plateCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tu vehiculo',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.midnight,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Agrega los datos del vehiculo que usaras para trabajar.',
            style:
                TextStyle(fontSize: 14, color: AppTheme.slate400, height: 1.5),
          ),
          const SizedBox(height: 20),
          ...widget.vehicles.map((vehicle) => _VehicleCard(vehicle: vehicle)),
          if (!_adding && widget.vehicles.isEmpty) _buildForm(context),
          if (!_adding && widget.vehicles.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => setState(() => _adding = true),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Agregar otro vehiculo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 46),
                side:
                    BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          if (_adding) _buildForm(context),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onBack,
                  child: const Text('Atras'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.vehicles.isEmpty ? null : widget.onSubmit,
                  child: const Text('Enviar a revision'),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildForm(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Column(
          children: [
            _TextInput(controller: _brandCtrl, label: 'Marca', hint: 'Toyota'),
            const SizedBox(height: 10),
            _TextInput(controller: _modelCtrl, label: 'Modelo', hint: 'Hilux'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TextInput(
                    controller: _yearCtrl,
                    label: 'Ano',
                    hint: '2020',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TextInput(
                    controller: _plateCtrl,
                    label: 'Patente',
                    hint: 'ABCD12',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _TextInput(controller: _colorCtrl, label: 'Color', hint: 'Blanco'),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _addVehicle,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text('Agregar vehiculo'),
            ),
          ],
        ),
      );

  Future<void> _addVehicle() async {
    if (_brandCtrl.text.trim().isEmpty ||
        _modelCtrl.text.trim().isEmpty ||
        _plateCtrl.text.trim().isEmpty) {
      return;
    }
    final vehicle = VehicleModel(
      brand: _brandCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      year: int.tryParse(_yearCtrl.text) ?? DateTime.now().year,
      plate: _plateCtrl.text.trim().toUpperCase(),
      color: _colorCtrl.text.trim(),
    );
    await widget.onAdd(vehicle);
    _brandCtrl.clear();
    _modelCtrl.clear();
    _yearCtrl.clear();
    _plateCtrl.clear();
    _colorCtrl.clear();
    if (mounted) setState(() => _adding = false);
  }
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
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.local_shipping_outlined,
                size: 20,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${vehicle.brand} ${vehicle.model} ${vehicle.year}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.midnight,
                    ),
                  ),
                  Text(
                    '${vehicle.plate} - ${vehicle.color}',
                    style:
                        const TextStyle(fontSize: 12, color: AppTheme.slate400),
                  ),
                ],
              ),
            ),
            const Icon(Icons.check_circle_rounded,
                size: 18, color: AppTheme.success),
          ],
        ),
      );
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;

  const _TextInput({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.readOnly = false,
    this.onTap,
    this.validator,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        validator: validator,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.slate200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.slate200),
          ),
        ),
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
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.midnight),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.midnight,
                ),
              ),
            ],
          ),
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.18)),
        ),
        child: Text(
          message,
          style: const TextStyle(color: AppTheme.error, fontSize: 13),
        ),
      );
}
