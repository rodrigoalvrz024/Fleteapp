import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../services/chat_service.dart';

class FreightChatAccessButton extends StatefulWidget {
  final int freightId;
  final String label;

  const FreightChatAccessButton({
    super.key,
    required this.freightId,
    required this.label,
  });

  @override
  State<FreightChatAccessButton> createState() =>
      _FreightChatAccessButtonState();
}

class _FreightChatAccessButtonState extends State<FreightChatAccessButton> {
  final _service = FreightChatService();
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final summary = await _service.getSummary(widget.freightId);
      if (mounted) setState(() => _unreadCount = summary.unreadCount);
    } catch (_) {
      // The chat screen will surface an actionable error if access is no longer valid.
    }
  }

  Future<void> _openChat() async {
    await context.push('/app/chat/${widget.freightId}');
    if (mounted) _loadUnreadCount();
  }

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          OutlinedButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: Text(widget.label),
          ),
          if (_unreadCount > 0)
            Positioned(
              top: -6,
              right: -5,
              child: Semantics(
                label: '$_unreadCount mensajes sin leer',
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    _unreadCount > 99 ? '99+' : '$_unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}
