import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/payout_model.dart';
import '../../services/payout_service.dart';
import '../shared/web_layout.dart';
import 'widgets/driver_app_bar_actions.dart';

class DriverPayoutsScreen extends StatefulWidget {
  const DriverPayoutsScreen({super.key});

  @override
  State<DriverPayoutsScreen> createState() => _DriverPayoutsScreenState();
}

class _DriverPayoutsScreenState extends State<DriverPayoutsScreen> {
  final _service = PayoutService();
  final _money = NumberFormat('#,##0', 'es_CL');
  final _date = DateFormat('d MMM yyyy, HH:mm', 'es_CL');
  List<PayoutModel> _payouts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final payouts = await _service.listMine();
      if (mounted) setState(() => _payouts = payouts);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _payouts
        .where((item) => item.status != 'paid')
        .fold<double>(0, (sum, item) => sum + item.amount);
    final paid = _payouts
        .where((item) => item.status == 'paid')
        .fold<double>(0, (sum, item) => sum + item.amount);

    return WebPageScaffold(
      title: 'Mis liquidaciones',
      subtitle: 'Pagos correspondientes a tus fletes cobrados',
      actions: const [DriverAppBarActions()],
      child: WebPageBody(
        onRefresh: _load,
        children: [
          Row(
            children: [
              Expanded(
                child: _Summary(
                  label: 'Por recibir',
                  value: '\$${_money.format(pending)}',
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Summary(
                  label: 'Pagado',
                  value: '\$${_money.format(paid)}',
                  color: AppTheme.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const WebLoadingState()
          else if (_payouts.isEmpty)
            const WebEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Sin liquidaciones todavía',
              description:
                  'Aparecerán aquí después de que un cliente pague un flete completado.',
            )
          else
            for (final payout in _payouts) ...[
              _PayoutCard(payout: payout, money: _money, date: _date),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Summary({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration(radius: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.slate600)),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _PayoutCard extends StatelessWidget {
  final PayoutModel payout;
  final NumberFormat money;
  final DateFormat date;

  const _PayoutCard({
    required this.payout,
    required this.money,
    required this.date,
  });

  Color get color => switch (payout.status) {
        'paid' => AppTheme.success,
        'failed' => AppTheme.error,
        'scheduled' => AppTheme.primary,
        _ => AppTheme.warning,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration(radius: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '\$${money.format(payout.amount)} CLP',
                    style: const TextStyle(
                      color: AppTheme.midnight,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    payout.statusLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Flete #${payout.freightId} · Creada ${date.format(payout.createdAt)}',
              style: const TextStyle(color: AppTheme.slate600, fontSize: 12),
            ),
            if (payout.scheduledFor != null) ...[
              const SizedBox(height: 6),
              Text(
                'Programada para ${date.format(payout.scheduledFor!)}',
                style: const TextStyle(color: AppTheme.slate600, fontSize: 12),
              ),
            ],
            if (payout.transferReference != null) ...[
              const SizedBox(height: 6),
              Text(
                'Referencia: ${payout.transferReference}',
                style: const TextStyle(color: AppTheme.slate600, fontSize: 12),
              ),
            ],
            if (payout.note != null && payout.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                payout.note!,
                style: const TextStyle(color: AppTheme.slate600, fontSize: 12),
              ),
            ],
          ],
        ),
      );
}
