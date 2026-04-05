import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class StatusTrackerWidget extends StatelessWidget {
  final String currentStatus;

  const StatusTrackerWidget({super.key, required this.currentStatus});

  static const _steps = [
    {'status': 'pending', 'label': 'Solicitado', 'icon': Icons.receipt_long},
    {
      'status': 'accepted',
      'label': 'Aceptado',
      'icon': Icons.thumb_up_outlined
    },
    {
      'status': 'in_progress',
      'label': 'En camino',
      'icon': Icons.local_shipping
    },
    {
      'status': 'completed',
      'label': 'Entregado',
      'icon': Icons.check_circle_outline
    },
  ];

  int get _currentIndex {
    for (int i = 0; i < _steps.length; i++) {
      if (_steps[i]['status'] == currentStatus) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (currentStatus == 'cancelled') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.cancel, color: AppTheme.error),
          SizedBox(width: 10),
          Text('Flete cancelado',
              style: TextStyle(
                  color: AppTheme.error, fontWeight: FontWeight.bold)),
        ]),
      );
    }

    final idx = _currentIndex;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Estado del flete',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.primary)),
          const SizedBox(height: 16),
          Row(
            children: List.generate(_steps.length, (i) {
              final done = i <= idx;
              final active = i == idx;
              return Expanded(
                child: Row(children: [
                  Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: active ? 40 : 32,
                      height: active ? 40 : 32,
                      decoration: BoxDecoration(
                        color:
                            done ? AppTheme.primary : const Color(0xFFE0E0E0),
                        shape: BoxShape.circle,
                        boxShadow: active
                            ? [
                                const BoxShadow(
                                    color: Colors.blue,
                                    blurRadius: 8,
                                    spreadRadius: 1)
                              ]
                            : [],
                      ),
                      child: Icon(_steps[i]['icon'] as IconData,
                          color: done ? Colors.white : Colors.grey,
                          size: active ? 22 : 16),
                    ),
                    const SizedBox(height: 6),
                    Text(_steps[i]['label'] as String,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.normal,
                            color: done ? AppTheme.primary : Colors.grey),
                        textAlign: TextAlign.center),
                  ]),
                  if (i < _steps.length - 1)
                    Expanded(
                        child: Container(
                            height: 2,
                            color: i < idx
                                ? AppTheme.primary
                                : const Color(0xFFE0E0E0))),
                ]),
              );
            }),
          ),
        ],
      ),
    );
  }
}
