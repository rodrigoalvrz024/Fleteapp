import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/driver_provider.dart';

/// Removes this offer's route, never a newer screen above it.
class DriverOfferGuard extends ConsumerStatefulWidget {
  final int freightId;
  final Widget child;

  const DriverOfferGuard({
    super.key,
    required this.freightId,
    required this.child,
  });

  @override
  ConsumerState<DriverOfferGuard> createState() => _DriverOfferGuardState();
}

class _DriverOfferGuardState extends ConsumerState<DriverOfferGuard> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(driverProvider.select(
      (state) =>
          state.isOnline && state.incomingFreight?.id == widget.freightId,
    ));
    if (!available && !_closing) {
      _closing = true;
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || route == null || !route.isActive) return;
        final navigator = Navigator.of(context);
        if (route.isCurrent) {
          navigator.pop();
        } else {
          navigator.removeRoute(route);
        }
      });
    }
    return IgnorePointer(ignoring: !available, child: widget.child);
  }
}
