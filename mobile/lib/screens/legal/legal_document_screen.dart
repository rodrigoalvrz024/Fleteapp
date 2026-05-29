import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../shared/web_layout.dart';

enum LegalDocumentType { terms, privacy }

class LegalDocumentScreen extends StatelessWidget {
  final LegalDocumentType type;

  const LegalDocumentScreen({super.key, required this.type});

  bool get _isTerms => type == LegalDocumentType.terms;

  @override
  Widget build(BuildContext context) {
    final sections = _isTerms ? _termsSections : _privacySections;

    return WebPageScaffold(
      title: _isTerms ? 'Terminos y condiciones' : 'Politica de privacidad',
      subtitle: 'Version 2026-05-26',
      child: WebPageBody(
        maxWidth: 880,
        children: [
          _Header(
            title:
                _isTerms ? 'Terminos de uso FleteApp' : 'Privacidad FleteApp',
            subtitle: _isTerms
                ? 'Estos terminos regulan el uso de la plataforma.'
                : 'Este documento explica como cuidamos tus datos.',
          ),
          const SizedBox(height: 14),
          for (final section in sections) ...[
            _Section(title: section.title, body: section.body),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Header({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Column(
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
                height: 1.45,
                color: AppTheme.slate400,
              ),
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.midnight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
}

class _LegalSection {
  final String title;
  final String body;

  const _LegalSection(this.title, this.body);
}

const _termsSections = [
  _LegalSection(
    'Uso de la plataforma',
    'FleteApp conecta clientes que solicitan fletes con conductores independientes. La plataforma permite crear solicitudes, aceptar servicios, coordinar traslados y revisar el estado de cada flete.',
  ),
  _LegalSection(
    'Cuentas de usuario',
    'Cada persona debe entregar informacion verdadera, mantener segura su contrasena y usar una cuenta propia. FleteApp puede suspender cuentas cuando exista fraude, uso indebido o riesgo para otros usuarios.',
  ),
  _LegalSection(
    'Conductores y documentos',
    'Los conductores deben mantener licencia vigente, permiso de circulacion, revision tecnica, SOAP y datos del vehiculo actualizados. La aprobacion puede ser rechazada o suspendida si la informacion no es verificable.',
  ),
  _LegalSection(
    'Servicios y pagos',
    'Los precios, comisiones, pagos al conductor y cargos al cliente se informan antes o durante la solicitud segun corresponda. Los valores pueden cambiar por distancia, urgencia, ayudantes u otros factores operativos.',
  ),
  _LegalSection(
    'Seguridad y responsabilidad',
    'Usuarios y conductores deben actuar de buena fe, cuidar la carga y respetar la normativa aplicable. FleteApp puede investigar incidentes y limitar el acceso para proteger la operacion.',
  ),
];

const _privacySections = [
  _LegalSection(
    'Datos que tratamos',
    'Podemos tratar datos de identificacion, contacto, ubicacion operativa, solicitudes de flete, pagos, calificaciones y documentos necesarios para validar conductores y vehiculos.',
  ),
  _LegalSection(
    'Finalidades',
    'Usamos los datos para crear cuentas, autenticar usuarios, coordinar fletes, calcular rutas y precios, validar conductores, prevenir fraude, entregar soporte y cumplir obligaciones legales.',
  ),
  _LegalSection(
    'Documentos de conductor',
    'La licencia, permiso de circulacion, revision tecnica y SOAP se usan para revisar la aptitud del conductor y del vehiculo. No pediremos reconocimiento facial ni verificacion biometrica en esta etapa.',
  ),
  _LegalSection(
    'Conservacion y seguridad',
    'Guardamos la informacion mientras sea necesaria para operar la cuenta, cumplir obligaciones, resolver disputas o prevenir fraude. Aplicamos controles de acceso y almacenamiento seguro para reducir riesgos.',
  ),
  _LegalSection(
    'Derechos de las personas',
    'Puedes solicitar acceso, rectificacion, eliminacion, bloqueo u oposicion cuando corresponda. Para ejercer derechos o pedir soporte, contacta al equipo de FleteApp desde los canales oficiales.',
  ),
];
