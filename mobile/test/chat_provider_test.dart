import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muvv_app/models/user_model.dart';
import 'package:muvv_app/providers/auth_provider.dart';
import 'package:muvv_app/models/chat_message_model.dart';
import 'package:muvv_app/providers/chat_provider.dart';
import 'package:muvv_app/services/chat_service.dart';
import 'package:muvv_app/services/chat_websocket_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('Chat reconnect recovery', () {
    late _FakeChatRepository repository;
    late _LiveConnector live;
    late FreightChatNotifier notifier;

    setUp(() {
      repository = _FakeChatRepository();
      live = _LiveConnector();
      notifier = FreightChatNotifier(
          freightId: 14, repository: repository, webSocketService: live);
    });
    tearDown(() => notifier.dispose());

    for (final messageDuringSync in [false, true]) {
      testWidgets(
          'read notifications settle without a loop (new message=$messageDuringSync)',
          (tester) async {
        await notifier.load();
        final pending = Completer<List<FreightChatMessage>>();
        repository.nextPage = pending.future;
        repository.onMarkRead = () => live.channels.last.emit({
              'type': 'read',
              'reader_user_id': 11,
              'read_at': '2026-09-15T12:00:00Z',
            });
        live.channels.last.emit({'type': 'ready'});
        await tester.pump();
        if (messageDuringSync) {
          repository._messages.add(_message(2));
          live.channels.last.emit(_messageEvent(2));
          await tester.pump();
        }
        pending.complete(List.of(repository._messages));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        final calls = repository.listCalls.length;
        expect(repository.markCalls,
            2); // Initial load and completed recovery only.
        expect(calls, 3); // Initial load, recovery, receipt reconciliation.
        await tester.pump(const Duration(seconds: 30));
        expect(repository.listCalls, hasLength(calls));
        expect(repository.markCalls, 2);
      });
    }

    testWidgets(
        'changing account disposes old history and ignores its pending response',
        (tester) async {
      final auth = _SessionAuth()..setUser(11);
      final container = ProviderContainer(overrides: [
        authProvider.overrideWith((ref) => auth),
        freightChatRepositoryProvider.overrideWithValue(repository),
        chatWebSocketServiceProvider.overrideWithValue(live),
      ]);
      addTearDown(container.dispose);
      final subscription =
          container.listen(freightChatProvider(14), (_, __) {});
      addTearDown(subscription.close);
      final first = container.read(freightChatProvider(14).notifier);
      await first.load();
      final pending = Completer<List<FreightChatMessage>>();
      repository.nextPage = pending.future;
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      auth.setUser(33);
      await tester.pump(const Duration(milliseconds: 1));
      final second = container.read(freightChatProvider(14).notifier);
      expect(identical(first, second), isFalse);
      pending.complete([_message(999)]);
      await tester.pump();
      expect(container.read(freightChatProvider(14)).messages, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('stalled old subscription cleanup cannot block reconnect',
        (tester) async {
      await notifier.load();
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      final cleanup = Completer<void>();
      live.channels.last.events.onCancel = () => cleanup.future;
      live.channels.last.events
          .addError(StateError('Synthetic network failure'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(live.channels, hasLength(2));
      cleanup.completeError(StateError('Synthetic late cleanup failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('read receipt preceding a missing page is retained',
        (tester) async {
      await notifier.load();
      final pending = Completer<List<FreightChatMessage>>();
      repository.nextPage = pending.future;
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      live.channels.last.emit({
        'type': 'read',
        'reader_user_id': 11,
        'read_at': '2026-09-15T12:00:00Z'
      });
      await tester.pump();
      repository._messages
        ..clear()
        ..addAll([
          _message(1),
          _message(2).copyWith(readAt: DateTime.utc(2026, 9, 15, 12)),
          _message(3)
        ]);
      pending.complete([
        _message(1),
        _message(2),
        _message(
            3), // Created before the receipt, but committed after its UPDATE.
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(notifier.state.messages[1].readAt, DateTime.utc(2026, 9, 15, 12));
      expect(notifier.state.messages[2].readAt, isNull);
    });

    testWidgets('ready recovers more than one page and ignores duplicate ready',
        (tester) async {
      await notifier.load();
      for (var id = 2; id <= 170; id++) {
        repository._messages.add(_message(id));
      }
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      expect(notifier.state.messages.map((m) => m.id),
          List.generate(170, (i) => i + 1));
      expect(repository.listCalls, [null, null, 91, 11]);
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      expect(repository.listCalls, hasLength(4));
    });

    testWidgets('disconnect reconnect recovers text and private image metadata',
        (tester) async {
      await notifier.load();
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      unawaited(live.channels.last.events.close());
      await tester.pump();
      expect(notifier.state.isConnected, isFalse);
      await repository.sendMessage(14, 'During outage');
      await repository.sendImage(14, [1, 2], 'synthetic.jpg');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(live.channels, hasLength(2));
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      expect(notifier.state.messages, hasLength(3));
      expect(notifier.state.messages.last.isImage, isTrue);
      expect(notifier.state.messages[1].messageText, 'During outage');
    });

    testWidgets('late history merges live events without losing read receipt',
        (tester) async {
      await notifier.load();
      final pending = Completer<List<FreightChatMessage>>();
      repository.nextPage = pending.future;
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      live.channels.last.emit(_messageEvent(2));
      live.channels.last.emit({
        'type': 'read',
        'reader_user_id': 11,
        'read_at': '2026-09-15T12:00:00Z'
      });
      await tester.pump();
      repository._messages
          .add(_message(2).copyWith(readAt: DateTime.utc(2026, 9, 15, 12)));
      pending.complete([_message(1), _message(2)]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(notifier.state.messages.map((m) => m.id), [1, 2]);
      expect(notifier.state.messages.last.readAt, isNotNull);
    });

    testWidgets('old connection response cannot modify reconnected history',
        (tester) async {
      await notifier.load();
      final pending = Completer<List<FreightChatMessage>>();
      repository.nextPage = pending.future;
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      unawaited(live.channels.last.events.close());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      pending.complete([_message(999)]);
      await tester.pump();
      expect(notifier.state.messages.map((m) => m.id), [1]);
    });

    testWidgets('temporary history error retries without another websocket',
        (tester) async {
      await notifier.load();
      repository.failNextList = true;
      repository._messages.add(_message(2));
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      expect(notifier.state.messages, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(notifier.state.messages, hasLength(2));
      expect(live.channels, hasLength(1));
    });

    testWidgets('manual reload denial clears state and rejects a pending send',
        (tester) async {
      await notifier.load();
      final pending = Completer<FreightChatMessage>();
      repository.nextSend = pending.future;
      final sending = notifier.send('Pending');
      final options = RequestOptions(path: '/synthetic');
      repository.listError = DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 403));
      await notifier.load();
      pending.complete(_message(999));
      await sending;
      expect(notifier.state.messages, isEmpty);
      expect(notifier.state.isWritable, isFalse);
      await tester.pump(const Duration(seconds: 30));
      expect(live.channels, hasLength(1));
    });

    testWidgets('permission denial clears private data and stops retrying',
        (tester) async {
      await notifier.load();
      final send = Completer<FreightChatMessage>();
      repository.nextSend = send.future;
      final sending = notifier.send('Pending before denial');
      final options = RequestOptions(path: '/synthetic');
      repository.listError = DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 403));
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      expect(notifier.state.messages, isEmpty);
      expect(notifier.state.isWritable, isFalse);
      expect(notifier.state.isConnected, isFalse);
      send.complete(_message(99));
      await sending;
      expect(notifier.state.messages, isEmpty);
      await tester.pump(const Duration(seconds: 30));
      expect(repository.listCalls, hasLength(2));
      expect(live.channels, hasLength(1));
    });

    testWidgets('late response after disposal is ignored', (tester) async {
      final disposable = FreightChatNotifier(
          freightId: 14, repository: repository, webSocketService: live);
      await disposable.load();
      final pending = Completer<List<FreightChatMessage>>();
      repository.nextPage = pending.future;
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      disposable.dispose();
      pending.complete([_message(2)]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'live completed status is not overwritten by older REST summary',
        (tester) async {
      await notifier.load();
      final pending = Completer<List<FreightChatMessage>>();
      repository.nextPage = pending.future;
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      live.channels.last.emit(
          {'type': 'status', 'status': 'completed', 'is_writable': false});
      await tester.pump();
      pending.complete([_message(1)]);
      await tester.pump();
      expect(notifier.state.summary?.status, 'completed');
      expect(notifier.state.isWritable, isFalse);
    });

    testWidgets('manual reload invalidates an old recovery response',
        (tester) async {
      await notifier.load();
      final pending = Completer<List<FreightChatMessage>>();
      repository.nextPage = pending.future;
      live.channels.last.emit({'type': 'ready'});
      await tester.pump();
      await notifier.load();
      pending.complete([_message(999)]);
      await tester.pump();
      expect(notifier.state.messages.map((m) => m.id), [1]);
    });
  });

  group('FreightChatNotifier', () {
    late _FakeChatRepository repository;
    late FreightChatNotifier notifier;

    setUp(() {
      repository = _FakeChatRepository();
      notifier = FreightChatNotifier(
        freightId: 14,
        repository: repository,
        webSocketService: _UnavailableLiveConnector(),
      );
    });

    tearDown(() => notifier.dispose());

    test('loads persisted history and sends a text message', () async {
      await notifier.load();

      expect(notifier.state.summary?.peerName, 'Conductor Demo');
      expect(notifier.state.messages, hasLength(1));
      expect(notifier.state.isWritable, isTrue);

      await notifier.send('Voy llegando');

      expect(notifier.state.messages, hasLength(2));
      expect(notifier.state.messages.last.messageText, 'Voy llegando');
      expect(notifier.state.failedMessage, isNull);
    });

    test('keeps a failed message available for retry', () async {
      await notifier.load();
      repository.failNextSend = true;

      await notifier.send('Estoy afuera');

      expect(notifier.state.failedMessage, 'Estoy afuera');
      expect(notifier.state.isSending, isFalse);

      await notifier.retryFailed();

      expect(notifier.state.failedMessage, isNull);
      expect(notifier.state.messages.last.messageText, 'Estoy afuera');
    });

    test('adds an uploaded image to the persisted conversation', () async {
      await notifier.load();

      final sent = await notifier.sendImage(
        [0xFF, 0xD8, 0xFF, 0x00],
        'retiro.jpg',
        caption: 'Esta es la entrada',
      );

      expect(sent, isTrue);
      expect(notifier.state.messages.last.messageType, 'image');
      expect(notifier.state.messages.last.messageText, 'Esta es la entrada');
    });
  });
}

class _FakeChatRepository implements FreightChatRepository {
  int markCalls = 0;
  void Function()? onMarkRead;
  final List<int?> listCalls = [];
  Future<List<FreightChatMessage>>? nextPage;
  Future<FreightChatMessage>? nextSend;
  bool failNextList = false;
  Object? listError;
  bool failNextSend = false;
  int _nextId = 2;
  final List<FreightChatMessage> _messages = [
    FreightChatMessage(
      id: 1,
      freightId: 14,
      senderUserId: 22,
      receiverUserId: 11,
      messageText: 'Hola, voy en camino',
      messageType: 'text',
      createdAt: DateTime.utc(2026, 8, 13, 12),
    ),
  ];

  @override
  Future<FreightChatSummary> getSummary(int freightId) async =>
      const FreightChatSummary(
        freightId: 14,
        isWritable: true,
        status: 'accepted',
        unreadCount: 1,
        maxMessageLength: 1000,
        peerName: 'Conductor Demo',
        peerRole: 'driver',
      );

  @override
  Future<List<FreightChatMessage>> listMessages(
    int freightId, {
    int? beforeId,
    int? limit,
  }) async {
    listCalls.add(beforeId);
    if (listError != null) throw listError!;
    if (failNextList) {
      failNextList = false;
      throw StateError('temporary outage');
    }
    final pending = nextPage;
    nextPage = null;
    if (pending != null) return pending;
    final messages = beforeId == null
        ? _messages
        : _messages.where((message) => message.id < beforeId).toList();
    final size = limit ?? messages.length;
    return List.unmodifiable(
        messages.skip(messages.length > size ? messages.length - size : 0));
  }

  @override
  Future<void> markRead(int freightId) async {
    markCalls += 1;
    onMarkRead?.call();
  }

  @override
  Future<FreightChatMessage> sendMessage(int freightId, String message) async {
    final pending = nextSend;
    nextSend = null;
    if (pending != null) return pending;
    if (failNextSend) {
      failNextSend = false;
      throw StateError('offline');
    }
    final created = FreightChatMessage(
      id: _nextId++,
      freightId: freightId,
      senderUserId: 11,
      receiverUserId: 22,
      messageText: message,
      messageType: 'text',
      createdAt: DateTime.now().toUtc(),
    );
    _messages.add(created);
    return created;
  }

  @override
  Future<FreightChatMessage> sendImage(
    int freightId,
    List<int> bytes,
    String filename, {
    String caption = '',
  }) async {
    final created = FreightChatMessage(
      id: _nextId++,
      freightId: freightId,
      senderUserId: 11,
      receiverUserId: 22,
      messageText: caption,
      messageType: 'image',
      attachmentViewPath: '/freights/chat/images/test-token',
      attachmentContentType: 'image/jpeg',
      attachmentSizeBytes: bytes.length,
      createdAt: DateTime.now().toUtc(),
    );
    _messages.add(created);
    return created;
  }
}

class _UnavailableLiveConnector implements ChatLiveConnector {
  @override
  Future<WebSocketChannel> connect(int freightId) =>
      Future.error(StateError('No websocket in unit test'));
}

FreightChatMessage _message(int id) => FreightChatMessage(
    id: id,
    freightId: 14,
    senderUserId: 22,
    receiverUserId: 11,
    messageText: 'Synthetic $id',
    messageType: 'text',
    createdAt: DateTime.utc(2026, 9, 15));

Map<String, dynamic> _messageEvent(int id) => {
      'type': 'message',
      'message': {
        'id': id,
        'freight_id': 14,
        'sender_user_id': 22,
        'receiver_user_id': 11,
        'message_text': 'Synthetic $id',
        'message_type': 'text',
        'created_at': '2026-09-15T00:00:00Z',
      }
    };

class _LiveConnector implements ChatLiveConnector {
  final channels = <_TestChannel>[];
  @override
  Future<WebSocketChannel> connect(int freightId) async {
    final channel = _TestChannel();
    channels.add(channel);
    return channel;
  }
}

class _TestChannel implements WebSocketChannel {
  final events = StreamController<dynamic>();
  @override
  final sink = _TestSink();
  @override
  Stream<dynamic> get stream => events.stream;
  void emit(Map<String, dynamic> event) => events.add(jsonEncode(event));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSink implements WebSocketSink {
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SessionAuth extends AuthNotifier {
  void setUser(int id) {
    state = AuthState(
        user: UserModel.fromJson({
      'id': id,
      'email': 'synthetic@example.com',
      'full_name': 'Synthetic',
      'phone': '',
      'role': 'client',
      'is_active': true,
    }));
  }
}
