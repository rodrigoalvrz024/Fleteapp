import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/chat_message_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/analytics_service.dart';
import '../../utils/api_error_message.dart';
import '../../utils/image_file_picker.dart';
import '../../widgets/muvv_mobile_ui.dart';

class FreightChatScreen extends ConsumerStatefulWidget {
  final int freightId;

  const FreightChatScreen({super.key, required this.freightId});

  @override
  ConsumerState<FreightChatScreen> createState() => _FreightChatScreenState();
}

class _FreightChatScreenState extends ConsumerState<FreightChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _analytics = AnalyticsService();
  bool _hasDraft = false;
  bool _showNewMessages = false;
  bool _trackedChatOpen = false;
  static const _maxChatImageBytes = 5 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onDraftChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(freightChatProvider(widget.freightId).notifier).load();
    });
  }

  @override
  void dispose() {
    _messageController
      ..removeListener(_onDraftChanged)
      ..dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    final hasDraft = _messageController.text.trim().isNotEmpty;
    if (hasDraft != _hasDraft && mounted) setState(() => _hasDraft = hasDraft);
  }

  void _onScroll() {
    if (_isNearBottom && _showNewMessages && mounted) {
      setState(() => _showNewMessages = false);
    }
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 120;
  }

  void _handleStateChange(FreightChatState? previous, FreightChatState next) {
    if (!_trackedChatOpen &&
        previous?.summary == null &&
        next.summary != null) {
      _trackedChatOpen = true;
      _track('chat_opened');
    }
    final previousCount = previous?.messages.length ?? 0;
    if (next.messages.length <= previousCount) return;
    if (_isNearBottom || previousCount == 0) {
      _scrollToEnd();
    } else if (mounted) {
      setState(() => _showNewMessages = true);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      if (mounted) setState(() => _showNewMessages = false);
    });
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final notifier = ref.read(freightChatProvider(widget.freightId).notifier);
    await notifier.send(text);
    if (!mounted) return;
    final failed =
        ref.read(freightChatProvider(widget.freightId)).failedMessage;
    if (failed != text) {
      _messageController.clear();
      _track('chat_message_sent');
    } else {
      _track('chat_message_failed');
    }
  }

  void _fillQuickMessage(String message) {
    _messageController
      ..text = message
      ..selection = TextSelection.collapsed(offset: message.length);
  }

  Future<void> _retryFailed() async {
    final notifier = ref.read(freightChatProvider(widget.freightId).notifier);
    await notifier.retryFailed();
    if (!mounted) return;
    if (ref.read(freightChatProvider(widget.freightId)).failedMessage == null) {
      _messageController.clear();
      _track('chat_message_sent');
    } else {
      _track('chat_message_failed');
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.error : AppTheme.success,
      ),
    );
  }

  Future<void> _pickAndSendImage() async {
    if (ref.read(freightChatProvider(widget.freightId)).isSending) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    PickedImageFile? picked;
    try {
      picked = await pickImageFile(source);
    } catch (error) {
      _showMessage(
        apiErrorMessage(error,
            fallback: 'No pudimos abrir la camara o galeria.'),
        error: true,
      );
      return;
    }
    if (picked == null) return;
    if (picked.bytes.length > _maxChatImageBytes) {
      _showMessage(
        'La foto supera el maximo de 5 MB. Prueba con una imagen mas liviana.',
        error: true,
      );
      return;
    }

    final sent = await ref
        .read(freightChatProvider(widget.freightId).notifier)
        .sendImage(
          picked.bytes,
          picked.name,
          caption: _messageController.text.trim(),
        );
    if (!mounted) return;
    if (sent) {
      _messageController.clear();
      _track('chat_image_sent');
      return;
    }
    _track('chat_image_failed');
    _showMessage(
      'No pudimos enviar la foto. Revisa tu conexion e intenta nuevamente.',
      error: true,
    );
  }

  void _track(String eventType) {
    final role = ref.read(authProvider).user?.role ?? 'unknown';
    unawaited(
      _analytics.trackEvent(
        eventType: eventType,
        entityType: 'freight',
        entityId: widget.freightId.toString(),
        metadata: {'role': role, 'surface': 'freight_chat'},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = ref.watch(authProvider).user?.role == 'driver';
    final currentUserId = ref.watch(authProvider).user?.id;
    final provider = freightChatProvider(widget.freightId);
    final state = ref.watch(provider);
    ref.listen<FreightChatState>(provider, _handleStateChange);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: _ChatHeader(summary: state.summary, isDriver: isDriver),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: _ConnectionStatus(connected: state.isConnected),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? _ChatError(
                  onRetry: () => ref.read(provider.notifier).load(),
                )
              : _ChatBody(
                  state: state,
                  currentUserId: currentUserId,
                  isDriver: isDriver,
                  hasDraft: _hasDraft,
                  controller: _messageController,
                  scrollController: _scrollController,
                  showNewMessages: _showNewMessages,
                  onScrollToEnd: _scrollToEnd,
                  onLoadOlder: () => ref.read(provider.notifier).loadOlder(),
                  onQuickMessage: _fillQuickMessage,
                  onSend: _send,
                  onPickImage: _pickAndSendImage,
                  onRetryFailed: _retryFailed,
                ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final FreightChatSummary? summary;
  final bool isDriver;

  const _ChatHeader({required this.summary, required this.isDriver});

  @override
  Widget build(BuildContext context) {
    final name = summary?.peerName ?? 'Chat de flete';
    return Row(
      children: [
        _PeerAvatar(name: name, imageUrl: summary?.peerAvatarUrl, radius: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.midnight,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              Text(
                isDriver ? 'Tu cliente' : 'Tu conductor',
                style: const TextStyle(
                  color: AppTheme.slate400,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;

  const _PeerAvatar({
    required this.name,
    required this.imageUrl,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'M' : name.trim()[0].toUpperCase();
    final hasImage = imageUrl != null && imageUrl!.startsWith('http');
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.10),
      foregroundImage: hasImage ? NetworkImage(imageUrl!) : null,
      child: Text(
        initial,
        style: TextStyle(
          color: AppTheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: radius * 0.78,
        ),
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  final bool connected;

  const _ConnectionStatus({required this.connected});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: connected ? 'Chat conectado' : 'Reconectando chat',
        child: Semantics(
          label: connected ? 'Chat conectado' : 'Reconectando chat',
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: connected ? AppTheme.success : AppTheme.slate400,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}

class _ChatBody extends StatelessWidget {
  final FreightChatState state;
  final int? currentUserId;
  final bool isDriver;
  final bool hasDraft;
  final TextEditingController controller;
  final ScrollController scrollController;
  final bool showNewMessages;
  final VoidCallback onScrollToEnd;
  final VoidCallback onLoadOlder;
  final ValueChanged<String> onQuickMessage;
  final Future<void> Function() onSend;
  final Future<void> Function() onPickImage;
  final Future<void> Function() onRetryFailed;

  const _ChatBody({
    required this.state,
    required this.currentUserId,
    required this.isDriver,
    required this.hasDraft,
    required this.controller,
    required this.scrollController,
    required this.showNewMessages,
    required this.onScrollToEnd,
    required this.onLoadOlder,
    required this.onQuickMessage,
    required this.onSend,
    required this.onPickImage,
    required this.onRetryFailed,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: _ChatContextCard(summary: state.summary!),
          ),
          Expanded(
            child: Stack(
              children: [
                state.messages.isEmpty
                    ? const _EmptyChat()
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                        itemCount: state.messages.length + 1,
                        itemBuilder: (_, index) {
                          if (index == 0) {
                            return state.hasOlderMessages
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Center(
                                      child: TextButton.icon(
                                        onPressed: state.isLoadingOlder
                                            ? null
                                            : onLoadOlder,
                                        icon: state.isLoadingOlder
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(
                                                Icons.expand_less_rounded),
                                        label: const Text(
                                            'Ver mensajes anteriores'),
                                      ),
                                    ),
                                  )
                                : const SizedBox(height: 4);
                          }
                          final messageIndex = index - 1;
                          final message = state.messages[messageIndex];
                          final previous = messageIndex == 0
                              ? null
                              : state.messages[messageIndex - 1];
                          return Column(
                            children: [
                              if (previous == null ||
                                  !_sameDay(
                                      previous.createdAt, message.createdAt))
                                _ChatDateDivider(date: message.createdAt),
                              _MessageBubble(
                                message: message,
                                isMine: message.senderUserId == currentUserId,
                              ),
                            ],
                          );
                        },
                      ),
                if (showNewMessages)
                  Positioned(
                    right: 20,
                    bottom: 14,
                    child: FilledButton.icon(
                      onPressed: onScrollToEnd,
                      icon: const Icon(Icons.south_rounded, size: 17),
                      label: const Text('Nuevo mensaje'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (state.failedMessage != null)
            _FailedMessageBanner(
              onRetry: onRetryFailed,
              disabled: state.isSending,
            ),
          if (state.isWritable) ...[
            _QuickMessages(isDriver: isDriver, onPressed: onQuickMessage),
            _MessageComposer(
              controller: controller,
              sending: state.isSending,
              enabled: hasDraft,
              maxLength: state.summary!.maxMessageLength,
              onSend: onSend,
              onPickImage: onPickImage,
            ),
          ] else
            _ArchivedChatNotice(status: state.summary!.status),
        ],
      );
}

bool _sameDay(DateTime left, DateTime right) {
  final localLeft = left.toLocal();
  final localRight = right.toLocal();
  return localLeft.year == localRight.year &&
      localLeft.month == localRight.month &&
      localLeft.day == localRight.day;
}

class _ChatContextCard extends StatelessWidget {
  final FreightChatSummary summary;

  const _ChatContextCard({required this.summary});

  @override
  Widget build(BuildContext context) => MuvvSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.forum_outlined,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                _statusDescription(summary.status),
                style: const TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            MuvvStatusPill.fromFreight(summary.status),
          ],
        ),
      );
}

String _statusDescription(String status) {
  switch (status) {
    case 'accepted':
      return 'Coordina el retiro de forma segura';
    case 'in_progress':
      return 'Coordina la entrega de forma segura';
    case 'completed':
      return 'Este flete ya finalizo';
    case 'cancelled':
      return 'Este flete fue cancelado';
    default:
      return 'Coordinacion segura del flete';
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppTheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Coordinen este flete aqui',
                style: TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Comparte solo indicaciones necesarias para el retiro y la entrega.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.slate600, height: 1.35),
              ),
            ],
          ),
        ),
      );
}

class _ChatError extends StatelessWidget {
  final VoidCallback onRetry;

  const _ChatError({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: MuvvSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded,
                    color: AppTheme.slate400, size: 30),
                const SizedBox(height: 12),
                const Text(
                  'No pudimos cargar la conversacion',
                  style: TextStyle(
                    color: AppTheme.midnight,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Revisa tu conexion y vuelve a intentarlo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.slate600),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                    onPressed: onRetry, child: const Text('Reintentar')),
              ],
            ),
          ),
        ),
      );
}

class _ChatDateDivider extends StatelessWidget {
  final DateTime date;

  const _ChatDateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final local = date.toLocal();
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final label = _sameDay(local, today)
        ? 'Hoy'
        : _sameDay(local, yesterday)
            ? 'Ayer'
            : DateFormat("d 'de' MMM", 'es_CL').format(local);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.slate100,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.slate600,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final FreightChatMessage message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final time =
        DateFormat('HH:mm', 'es_CL').format(message.createdAt.toLocal());
    final imageUrl = message.attachmentUrl;
    final hasImage = message.isImage && imageUrl != null;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 9),
        padding: hasImage
            ? const EdgeInsets.fromLTRB(4, 4, 4, 8)
            : const EdgeInsets.fromLTRB(13, 10, 12, 8),
        decoration: BoxDecoration(
          color: isMine ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          border: isMine ? null : Border.all(color: AppTheme.slate200),
          boxShadow: [
            BoxShadow(
              color: AppTheme.midnight.withValues(alpha: 0.035),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hasImage)
              _ChatImagePreview(imageUrl: imageUrl, sentByMe: isMine),
            if (message.messageText.trim().isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message.messageText,
                  style: TextStyle(
                    color: isMine ? Colors.white : AppTheme.midnight,
                    fontSize: 14,
                    height: 1.32,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              isMine ? '$time ${message.readAt != null ? '✓✓' : '✓'}' : time,
              style: TextStyle(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.72)
                    : AppTheme.slate400,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatImagePreview extends StatelessWidget {
  final String imageUrl;
  final bool sentByMe;

  const _ChatImagePreview({
    required this.imageUrl,
    required this.sentByMe,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Abrir foto adjunta',
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => _showImageViewer(context, imageUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 230),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 170,
                    color: sentByMe
                        ? Colors.white.withValues(alpha: 0.15)
                        : AppTheme.slate100,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  height: 170,
                  color: sentByMe
                      ? Colors.white.withValues(alpha: 0.15)
                      : AppTheme.slate100,
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_not_supported_outlined,
                          color: AppTheme.slate400),
                      SizedBox(height: 6),
                      Text(
                        'No pudimos cargar la foto',
                        style:
                            TextStyle(color: AppTheme.slate600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

void _showImageViewer(BuildContext context, String imageUrl) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton.filledTonal(
                tooltip: 'Cerrar foto',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuickMessages extends StatelessWidget {
  final bool isDriver;
  final ValueChanged<String> onPressed;

  const _QuickMessages({required this.isDriver, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final messages = isDriver
        ? const [
            'Voy en camino',
            'Ya llegue',
            'Estoy afuera',
            'Llego en unos minutos'
          ]
        : const [
            'Estoy listo',
            'Ya bajo',
            'Entra por el porton',
            'Te espero afuera'
          ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        scrollDirection: Axis.horizontal,
        itemCount: messages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => ActionChip(
          label: Text(messages[index]),
          onPressed: () => onPressed(messages[index]),
          backgroundColor: AppTheme.primary.withValues(alpha: 0.07),
          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.16)),
          labelStyle: const TextStyle(
            color: AppTheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FailedMessageBanner extends StatelessWidget {
  final Future<void> Function() onRetry;
  final bool disabled;

  const _FailedMessageBanner({required this.onRetry, required this.disabled});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 2),
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.error, size: 17),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'No se pudo enviar el mensaje',
                style: TextStyle(
                    color: AppTheme.midnight,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: disabled ? null : onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
}

class _MessageComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final int maxLength;
  final Future<void> Function() onSend;
  final Future<void> Function() onPickImage;

  const _MessageComposer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.maxLength,
    required this.onSend,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppTheme.slate200)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Enviar foto',
                onPressed: sending ? null : onPickImage,
                style: IconButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  minimumSize: const Size(46, 46),
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  maxLength: maxLength,
                  decoration: const InputDecoration(
                    hintText: 'Escribe un mensaje...',
                    counterText: '',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              IconButton.filled(
                tooltip: 'Enviar mensaje',
                onPressed: enabled && !sending ? onSend : null,
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.slate200,
                  disabledForegroundColor: AppTheme.slate400,
                  minimumSize: const Size(48, 48),
                ),
                icon: sending
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ],
          ),
        ),
      );
}

class _ArchivedChatNotice extends StatelessWidget {
  final String status;

  const _ArchivedChatNotice({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = status == 'cancelled'
        ? 'Este flete fue cancelado. El chat esta disponible solo para consulta.'
        : 'Este flete ha finalizado. El chat esta disponible solo para consulta.';
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 15, 20, 18),
        color: AppTheme.slate100,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded,
                size: 16, color: AppTheme.slate600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.slate600, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
