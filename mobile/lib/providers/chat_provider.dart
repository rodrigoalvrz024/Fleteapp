import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/chat_message_model.dart';
import '../services/chat_service.dart';
import '../services/chat_websocket_service.dart';
import 'auth_provider.dart';

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
  Timer? _historyRetryTimer;
  int _reconnectAttempt = 0;
  int _historyRetryAttempt = 0;
  int _connectionGeneration = 0;
  int? _readyGeneration;
  int? _syncingGeneration;
  int _statusRevision = 0;
  int? _historyBoundary;
  bool _accessDenied = false;
  int _readRevision = 0;
  int? _markReadGeneration;

  FreightChatNotifier({
    required this.freightId,
    required FreightChatRepository repository,
    required ChatLiveConnector webSocketService,
  })  : _repository = repository,
        _webSocketService = webSocketService,
        super(const FreightChatState());

  Future<void> load() async {
    if (!mounted || _accessDenied || state.isLoading) return;
    final generation = ++_connectionGeneration;
    _reconnectTimer?.cancel();
    _historyRetryTimer?.cancel();
    _historyBoundary = null;
    if (_socketSubscription != null) {
      unawaited(_cancelSubscription(_socketSubscription!));
    }
    if (_channel != null) unawaited(_closeChannel(_channel!));
    _socketSubscription = null;
    _channel = null;
    state =
        state.copyWith(isLoading: true, isConnected: false, clearError: true);
    try {
      final values = await Future.wait([
        _repository.getSummary(freightId),
        _repository.listMessages(freightId, limit: _pageSize),
      ]);
      if (!_isCurrent(generation)) return;
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
    } catch (error) {
      if (!_isCurrent(generation)) return;
      if (_handleAccessError(error)) return;
      state = state.copyWith(
        isLoading: false,
        error: 'No pudimos cargar la conversacion. Revisa tu conexion.',
      );
    }
  }

  Future<void> loadOlder() async {
    if (!mounted ||
        _accessDenied ||
        state.isLoadingOlder ||
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
      if (!mounted || _accessDenied) return;
      state = state.copyWith(
        messages: _mergeMessages(older, state.messages),
        isLoadingOlder: false,
        hasOlderMessages: older.length >= _pageSize,
      );
    } catch (_) {
      if (mounted && !_accessDenied) {
        state = state.copyWith(isLoadingOlder: false);
      }
    }
  }

  Future<void> send(String rawMessage) async {
    final message = rawMessage.trim();
    if (!mounted ||
        _accessDenied ||
        message.isEmpty ||
        state.isSending ||
        !state.isWritable) {
      return;
    }
    state = state.copyWith(
      isSending: true,
      clearFailedMessage: true,
    );
    try {
      final created = await _repository.sendMessage(freightId, message);
      if (!mounted || _accessDenied) return;
      state = state.copyWith(
        messages: _mergeMessages(state.messages, [created]),
        isSending: false,
      );
    } catch (_) {
      if (mounted && !_accessDenied) {
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
    if (!mounted ||
        _accessDenied ||
        bytes.isEmpty ||
        state.isSending ||
        !state.isWritable) {
      return false;
    }
    state = state.copyWith(isSending: true, clearFailedMessage: true);
    try {
      final created = await _repository.sendImage(
        freightId,
        bytes,
        filename,
        caption: caption,
      );
      if (!mounted || _accessDenied) return false;
      state = state.copyWith(
        messages: _mergeMessages(state.messages, [created]),
        isSending: false,
      );
      return true;
    } catch (_) {
      if (mounted && !_accessDenied) state = state.copyWith(isSending: false);
      return false;
    }
  }

  Future<void> markRead() async {
    if (!mounted || _accessDenied) return;
    try {
      await _repository.markRead(freightId);
      if (mounted &&
          !_accessDenied &&
          state.summary != null &&
          state.summary!.unreadCount > 0) {
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
    final generation = ++_connectionGeneration;
    _reconnectTimer?.cancel();
    _historyRetryTimer?.cancel();
    _historyRetryAttempt = 0;
    final subscription = _socketSubscription;
    final previous = _channel;
    _socketSubscription = null;
    _channel = null;
    if (mounted) state = state.copyWith(isConnected: false);
    try {
      if (subscription != null) unawaited(_cancelSubscription(subscription));
      if (previous != null) unawaited(_closeChannel(previous));
      if (!_isCurrent(generation)) return;
      final channel = await _webSocketService.connect(freightId);
      if (!_isCurrent(generation)) {
        unawaited(_closeChannel(channel));
        return;
      }
      _channel = channel;
      _socketSubscription = channel.stream.listen(
        (event) {
          if (_isCurrent(generation)) _handleSocketEvent(event, generation);
        },
        onError: (_) {
          if (_isCurrent(generation)) _scheduleReconnect();
        },
        onDone: () {
          if (_isCurrent(generation)) _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (_) {
      if (_isCurrent(generation)) _scheduleReconnect();
    }
  }

  bool _isCurrent(int generation) =>
      mounted && !_accessDenied && generation == _connectionGeneration;

  bool _handleAccessError(Object error) {
    if (!mounted ||
        error is! DioException ||
        (error.response?.statusCode != 401 &&
            error.response?.statusCode != 403)) {
      return false;
    }
    _accessDenied = true;
    _connectionGeneration += 1;
    _historyRetryTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_channel != null) unawaited(_closeChannel(_channel!));
    state = const FreightChatState(
        error: 'Ya no tienes acceso a esta conversacion.');
    return true;
  }

  Future<void> _closeChannel(WebSocketChannel channel) async {
    try {
      await channel.sink.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Transport cleanup must not block the replacement connection.
    }
  }

  Future<void> _cancelSubscription(
      StreamSubscription<dynamic> subscription) async {
    try {
      await subscription.cancel().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Old callbacks are already invalidated by the connection generation.
    }
  }

  Future<void> _syncHistory(int generation) async {
    if (!_isCurrent(generation) || _syncingGeneration == generation) return;
    _syncingGeneration = generation;
    // Keep the oldest displayed boundary until every intervening page is read.
    final boundary = _historyBoundary ??=
        state.messages.isEmpty ? 0 : state.messages.first.id;
    final statusRevision = _statusRevision;
    final readRevision = _readRevision;
    int? beforeId;
    try {
      final summary = await _repository.getSummary(freightId);
      if (!_isCurrent(generation)) return;
      if (summary.freightId != freightId) {
        throw StateError('Unexpected freight');
      }
      while (_isCurrent(generation)) {
        final page = await _repository.listMessages(
          freightId,
          beforeId: beforeId,
          limit: _pageSize,
        );
        if (!_isCurrent(generation)) return;
        if (page.length > _pageSize ||
            page.any((message) =>
                message.freightId != freightId ||
                message.id <= 0 ||
                (beforeId != null && message.id >= beforeId))) {
          throw StateError('Invalid history page');
        }
        final ordered = _mergeMessages(const [], page);
        state =
            state.copyWith(messages: _mergeMessages(state.messages, ordered));
        if (ordered.isEmpty ||
            ordered.first.id <= boundary ||
            page.length < _pageSize) {
          break;
        }
        beforeId = ordered.first.id;
      }
      if (!_isCurrent(generation)) return;
      if (_statusRevision == statusRevision) {
        state = state.copyWith(summary: summary);
      }
      if (_readRevision != readRevision) {
        // A read event can race a DB snapshot; reload instead of inferring by date.
        _historyRetryTimer?.cancel();
        _historyRetryTimer = Timer(Duration.zero, () {
          if (_isCurrent(generation)) unawaited(_syncHistory(generation));
        });
        return;
      }
      _historyRetryAttempt = 0;
      _historyBoundary = null;
      if (_markReadGeneration == generation) {
        _markReadGeneration = null;
        unawaited(markRead());
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        if (_handleAccessError(error)) return;
        const delays = [1, 2, 4, 8, 15];
        final delay =
            delays[_historyRetryAttempt.clamp(0, delays.length - 1).toInt()];
        _historyRetryAttempt += 1;
        _historyRetryTimer?.cancel();
        _historyRetryTimer = Timer(Duration(seconds: delay), () {
          if (_isCurrent(generation)) unawaited(_syncHistory(generation));
        });
      }
    } finally {
      if (_syncingGeneration == generation) _syncingGeneration = null;
    }
  }

  void _handleSocketEvent(dynamic rawEvent, int generation) {
    try {
      final rawText =
          rawEvent is String ? rawEvent : utf8.decode(rawEvent as List<int>);
      final event = Map<String, dynamic>.from(jsonDecode(rawText) as Map);
      switch (event['type']) {
        case 'ready':
          if (_readyGeneration == generation) break;
          _readyGeneration = generation;
          _markReadGeneration = generation;
          _reconnectAttempt = 0;
          if (mounted) state = state.copyWith(isConnected: true);
          unawaited(_syncHistory(generation));
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
            if (_historyBoundary == null) {
              unawaited(markRead());
            } else {
              _markReadGeneration = generation;
            }
          }
          break;
        case 'read':
          final readerId = (event['reader_user_id'] as num?)?.toInt();
          final rawReadAt = event['read_at'];
          final readAt = DateTime.tryParse(rawReadAt?.toString() ?? '');
          if (readerId != null && readAt != null && mounted) {
            _readRevision += 1;
            unawaited(_syncHistory(generation));
          }
          break;
        case 'status':
          _statusRevision += 1;
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
    _connectionGeneration += 1;
    _historyRetryTimer?.cancel();
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
    };
    for (final message in incoming) {
      final previous = byId[message.id];
      byId[message.id] = message.readAt == null && previous?.readAt != null
          ? message.copyWith(readAt: previous!.readAt)
          : message;
    }
    final messages = byId.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return List.unmodifiable(messages);
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _historyRetryTimer?.cancel();
    _connectionGeneration += 1;
    if (_socketSubscription != null) {
      unawaited(_cancelSubscription(_socketSubscription!));
    }
    if (_channel != null) unawaited(_closeChannel(_channel!));
    super.dispose();
  }
}

final freightChatProvider = StateNotifierProvider.autoDispose
    .family<FreightChatNotifier, FreightChatState, int>((ref, freightId) {
  ref.watch(authProvider.select((auth) => auth.user?.id));
  return FreightChatNotifier(
    freightId: freightId,
    repository: ref.watch(freightChatRepositoryProvider),
    webSocketService: ref.watch(chatWebSocketServiceProvider),
  );
});
