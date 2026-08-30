import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/chat_message_model.dart';
import '../services/chat_service.dart';
import '../services/chat_websocket_service.dart';

final freightChatRepositoryProvider = Provider<FreightChatRepository>(
  (ref) => FreightChatService(),
);

final chatWebSocketServiceProvider = Provider<ChatLiveConnector>(
  (ref) => ChatWebSocketService(),
);

class FreightChatState {
  final FreightChatSummary? summary;
  final List<FreightChatMessage> messages;
  final bool isLoading;
  final bool isLoadingOlder;
  final bool isSending;
  final bool isConnected;
  final bool hasOlderMessages;
  final String? error;
  final String? failedMessage;

  const FreightChatState({
    this.summary,
    this.messages = const [],
    this.isLoading = false,
    this.isLoadingOlder = false,
    this.isSending = false,
    this.isConnected = false,
    this.hasOlderMessages = false,
    this.error,
    this.failedMessage,
  });

  bool get isWritable => summary?.isWritable == true;

  FreightChatState copyWith({
    FreightChatSummary? summary,
    List<FreightChatMessage>? messages,
    bool? isLoading,
    bool? isLoadingOlder,
    bool? isSending,
    bool? isConnected,
    bool? hasOlderMessages,
    String? error,
    String? failedMessage,
    bool clearError = false,
    bool clearFailedMessage = false,
  }) =>
      FreightChatState(
        summary: summary ?? this.summary,
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
        isSending: isSending ?? this.isSending,
        isConnected: isConnected ?? this.isConnected,
        hasOlderMessages: hasOlderMessages ?? this.hasOlderMessages,
        error: clearError ? null : error ?? this.error,
        failedMessage:
            clearFailedMessage ? null : failedMessage ?? this.failedMessage,
      );
}

class FreightChatNotifier extends StateNotifier<FreightChatState> {
  static const _pageSize = 80;

  final int freightId;
  final FreightChatRepository _repository;
  final ChatLiveConnector _webSocketService;
  StreamSubscription<dynamic>? _socketSubscription;
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  FreightChatNotifier({
    required this.freightId,
    required FreightChatRepository repository,
    required ChatLiveConnector webSocketService,
  })  : _repository = repository,
        _webSocketService = webSocketService,
        super(const FreightChatState());

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final values = await Future.wait([
        _repository.getSummary(freightId),
        _repository.listMessages(freightId, limit: _pageSize),
      ]);
      if (!mounted) return;
      final summary = values[0] as FreightChatSummary;
      final messages = values[1] as List<FreightChatMessage>;
      state = state.copyWith(
        summary: summary,
        messages: _mergeMessages(const [], messages),
        isLoading: false,
        hasOlderMessages: messages.length >= _pageSize,
        clearError: true,
      );
      unawaited(markRead());
      await _connect();
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'No pudimos cargar la conversacion. Revisa tu conexion.',
      );
    }
  }

  Future<void> loadOlder() async {
    if (state.isLoadingOlder ||
        !state.hasOlderMessages ||
        state.messages.isEmpty) {
      return;
    }
    state = state.copyWith(isLoadingOlder: true);
    try {
      final older = await _repository.listMessages(
        freightId,
        beforeId: state.messages.first.id,
        limit: _pageSize,
      );
      if (!mounted) return;
      state = state.copyWith(
        messages: _mergeMessages(older, state.messages),
        isLoadingOlder: false,
        hasOlderMessages: older.length >= _pageSize,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoadingOlder: false);
    }
  }

  Future<void> send(String rawMessage) async {
    final message = rawMessage.trim();
    if (message.isEmpty || state.isSending || !state.isWritable) return;
    state = state.copyWith(
      isSending: true,
      clearFailedMessage: true,
    );
    try {
      final created = await _repository.sendMessage(freightId, message);
      if (!mounted) return;
      state = state.copyWith(
        messages: _mergeMessages(state.messages, [created]),
        isSending: false,
      );
    } catch (_) {
      if (mounted) {
        state = state.copyWith(isSending: false, failedMessage: message);
      }
    }
  }

  Future<void> retryFailed() async {
    final message = state.failedMessage;
    if (message != null) await send(message);
  }

  Future<bool> sendImage(
    List<int> bytes,
    String filename, {
    String caption = '',
  }) async {
    if (bytes.isEmpty || state.isSending || !state.isWritable) return false;
    state = state.copyWith(isSending: true, clearFailedMessage: true);
    try {
      final created = await _repository.sendImage(
        freightId,
        bytes,
        filename,
        caption: caption,
      );
      if (!mounted) return false;
      state = state.copyWith(
        messages: _mergeMessages(state.messages, [created]),
        isSending: false,
      );
      return true;
    } catch (_) {
      if (mounted) state = state.copyWith(isSending: false);
      return false;
    }
  }

  Future<void> markRead() async {
    try {
      await _repository.markRead(freightId);
      if (mounted && state.summary != null && state.summary!.unreadCount > 0) {
        state = state.copyWith(
          summary: FreightChatSummary(
            freightId: state.summary!.freightId,
            isWritable: state.summary!.isWritable,
            status: state.summary!.status,
            unreadCount: 0,
            maxMessageLength: state.summary!.maxMessageLength,
            peerName: state.summary!.peerName,
            peerRole: state.summary!.peerRole,
            peerAvatarUrl: state.summary!.peerAvatarUrl,
          ),
        );
      }
    } catch (_) {
      // Reading is an enhancement; a transient failure must not block the chat.
    }
  }

  Future<void> _connect() async {
    _reconnectTimer?.cancel();
    await _socketSubscription?.cancel();
    await _channel?.sink.close();
    if (mounted) state = state.copyWith(isConnected: false);
    try {
      final channel = await _webSocketService.connect(freightId);
      if (!mounted) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _socketSubscription = channel.stream.listen(
        _handleSocketEvent,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleSocketEvent(dynamic rawEvent) {
    try {
      final rawText =
          rawEvent is String ? rawEvent : utf8.decode(rawEvent as List<int>);
      final event = Map<String, dynamic>.from(jsonDecode(rawText) as Map);
      switch (event['type']) {
        case 'ready':
          _reconnectAttempt = 0;
          if (mounted) state = state.copyWith(isConnected: true);
          break;
        case 'message':
          final rawMessage = event['message'];
          if (rawMessage is Map && mounted) {
            state = state.copyWith(
              messages: _mergeMessages(
                state.messages,
                [
                  FreightChatMessage.fromJson(
                      Map<String, dynamic>.from(rawMessage))
                ],
              ),
            );
            unawaited(markRead());
          }
          break;
        case 'read':
          final readerId = (event['reader_user_id'] as num?)?.toInt();
          final rawReadAt = event['read_at'];
          final readAt = rawReadAt == null
              ? DateTime.now()
              : DateTime.tryParse(rawReadAt.toString()) ?? DateTime.now();
          if (readerId != null && mounted) {
            state = state.copyWith(
              messages: state.messages
                  .map(
                    (message) => message.receiverUserId == readerId &&
                            message.readAt == null
                        ? message.copyWith(readAt: readAt)
                        : message,
                  )
                  .toList(growable: false),
            );
          }
          break;
        case 'status':
          final summary = state.summary;
          if (summary != null && mounted) {
            state = state.copyWith(
              summary: FreightChatSummary(
                freightId: summary.freightId,
                isWritable: event['is_writable'] == true,
                status: event['status']?.toString() ?? summary.status,
                unreadCount: summary.unreadCount,
                maxMessageLength: summary.maxMessageLength,
                peerName: summary.peerName,
                peerRole: summary.peerRole,
                peerAvatarUrl: summary.peerAvatarUrl,
              ),
            );
          }
          break;
      }
    } catch (_) {
      // Persisted REST data remains authoritative if an event is malformed.
    }
  }

  void _scheduleReconnect() {
    if (!mounted || _reconnectTimer?.isActive == true) return;
    state = state.copyWith(isConnected: false);
    const delays = [1, 2, 4, 8, 15];
    final delay = delays[_reconnectAttempt.clamp(0, delays.length - 1).toInt()];
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _connect();
    });
  }

  List<FreightChatMessage> _mergeMessages(
    List<FreightChatMessage> current,
    List<FreightChatMessage> incoming,
  ) {
    final byId = <int, FreightChatMessage>{
      for (final message in current) message.id: message,
      for (final message in incoming) message.id: message,
    };
    final messages = byId.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return List.unmodifiable(messages);
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _socketSubscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}

final freightChatProvider = StateNotifierProvider.autoDispose
    .family<FreightChatNotifier, FreightChatState, int>((ref, freightId) {
  return FreightChatNotifier(
    freightId: freightId,
    repository: ref.watch(freightChatRepositoryProvider),
    webSocketService: ref.watch(chatWebSocketServiceProvider),
  );
});
