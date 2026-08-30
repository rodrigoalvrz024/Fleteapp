import 'package:flutter_test/flutter_test.dart';
import 'package:muvv_app/models/chat_message_model.dart';
import 'package:muvv_app/providers/chat_provider.dart';
import 'package:muvv_app/services/chat_service.dart';
import 'package:muvv_app/services/chat_websocket_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
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
    final messages = beforeId == null
        ? _messages
        : _messages.where((message) => message.id < beforeId).toList();
    return List.unmodifiable(messages);
  }

  @override
  Future<void> markRead(int freightId) async {}

  @override
  Future<FreightChatMessage> sendMessage(int freightId, String message) async {
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
