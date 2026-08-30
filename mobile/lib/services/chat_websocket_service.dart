import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants/api_constants.dart';
import 'api_service.dart';

abstract class ChatLiveConnector {
  Future<WebSocketChannel> connect(int freightId);
}

class ChatWebSocketService implements ChatLiveConnector {
  final ApiService _api;

  ChatWebSocketService({ApiService? api}) : _api = api ?? ApiService();

  @override
  Future<WebSocketChannel> connect(int freightId) async {
    final token = await _api.getToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sesion no disponible');
    }
    final apiUri = Uri.parse(ApiConstants.baseUrl);
    final socketUri = apiUri.replace(
      scheme: apiUri.scheme == 'https' ? 'wss' : 'ws',
      path:
          '${apiUri.path.replaceFirst(RegExp(r'/$'), '')}/freights/$freightId/chat/live',
      query: null,
      fragment: null,
    );
    final channel = WebSocketChannel.connect(socketUri);
    // The JWT stays out of the URL, browser history, proxy logs and analytics.
    channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
    return channel;
  }
}
