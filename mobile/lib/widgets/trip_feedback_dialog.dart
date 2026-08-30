import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../services/trip_feedback_service.dart';

Future<bool> showTripFeedbackDialog(BuildContext context, int freightId) async {
  final service = TripFeedbackService();
  final form = await service.formForFreight(freightId);
  if (!context.mounted) return false;
  if (form.submitted) return false;

  final answers = {for (final question in form.questions) question.key: 5};
  var overallScore = 5;
  final comment = TextEditingController();
  try {
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            form.recipientRole == 'driver'
                ? 'Evalua el servicio'
                : 'Evalua a tu cliente',
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tus respuestas ayudan a que Muvv sea mas seguro y confiable.',
                    style: TextStyle(color: AppTheme.slate600, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  ...form.questions.map(
                    (question) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<int>(
                        initialValue: answers[question.key],
                        decoration: InputDecoration(labelText: question.label),
                        items: const [
                          DropdownMenuItem(
                              value: 1, child: Text('1 - Muy malo')),
                          DropdownMenuItem(value: 2, child: Text('2 - Malo')),
                          DropdownMenuItem(
                              value: 3, child: Text('3 - Regular')),
                          DropdownMenuItem(value: 4, child: Text('4 - Bueno')),
                          DropdownMenuItem(
                              value: 5, child: Text('5 - Excelente')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => answers[question.key] = value);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Evaluacion general',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final value = index + 1;
                      return IconButton(
                        tooltip: '$value estrellas',
                        onPressed: () =>
                            setDialogState(() => overallScore = value),
                        icon: Icon(
                          value <= overallScore
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: AppTheme.accent,
                        ),
                      );
                    }),
                  ),
                  TextField(
                    controller: comment,
                    maxLength: 600,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Comentario opcional',
                      hintText: 'Comparte algun detalle util',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (send != true) return false;
    await service.submit(
      freightId: freightId,
      overallScore: overallScore,
      answers: answers,
      comment: comment.text,
    );
    return true;
  } finally {
    comment.dispose();
  }
}
