import '../core/constants/api_constants.dart';

class FreightChatMessage {
  final int id;
  final int freightId;
  final int senderUserId;
  final int receiverUserId;
  final String messageText;
  final String messageType;
  final String? attachmentViewPath;
  final String? attachmentContentType;
  final int? attachmentSizeBytes;
  final DateTime createdAt;
  final DateTime? readAt;

  const FreightChatMessage({
    required this.id,
    required this.freightId,
    required this.senderUserId,
    required this.receiverUserId,
    required this.messageText,
    required this.messageType,
    this.attachmentViewPath,
    this.attachmentContentType,
    this.attachmentSizeBytes,
    required this.createdAt,
    this.readAt,
  });

  factory FreightChatMessage.fromJson(Map<String, dynamic> json) =>
      FreightChatMessage(
        id: (json['id'] as num).toInt(),
        freightId: (json['freight_id'] as num).toInt(),
        senderUserId: (json['sender_user_id'] as num).toInt(),
        receiverUserId: (json['receiver_user_id'] as num).toInt(),
        messageText: json['message_text']?.toString() ?? '',
        messageType: json['message_type']?.toString() ?? 'text',
        attachmentViewPath: json['attachment_view_path']?.toString(),
        attachmentContentType: json['attachment_content_type']?.toString(),
        attachmentSizeBytes: (json['attachment_size_bytes'] as num?)?.toInt(),
        createdAt: DateTime.parse(json['created_at'].toString()),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'].toString()),
      );

  bool get isImage => messageType == 'image' && attachmentViewPath != null;

  String? get attachmentUrl {
    final path = attachmentViewPath;
    if (path == null || path.isEmpty) return null;
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) return uri.toString();
    return Uri.parse(ApiConstants.baseUrl).resolve(path).toString();
  }

  FreightChatMessage copyWith({DateTime? readAt}) => FreightChatMessage(
        id: id,
        freightId: freightId,
        senderUserId: senderUserId,
        receiverUserId: receiverUserId,
        messageText: messageText,
        messageType: messageType,
        attachmentViewPath: attachmentViewPath,
        attachmentContentType: attachmentContentType,
        attachmentSizeBytes: attachmentSizeBytes,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
      );
}

class FreightChatSummary {
  final int freightId;
  final bool isWritable;
  final String status;
  final int unreadCount;
  final int maxMessageLength;
  final String peerName;
  final String peerRole;
  final String? peerAvatarUrl;

  const FreightChatSummary({
    required this.freightId,
    required this.isWritable,
    required this.status,
    required this.unreadCount,
    required this.maxMessageLength,
    required this.peerName,
    required this.peerRole,
    this.peerAvatarUrl,
  });

  factory FreightChatSummary.fromJson(Map<String, dynamic> json) {
    final peer = json['peer'] is Map
        ? Map<String, dynamic>.from(json['peer'] as Map)
        : const <String, dynamic>{};
    return FreightChatSummary(
      freightId: (json['freight_id'] as num).toInt(),
      isWritable: json['is_writable'] == true,
      status: json['status']?.toString() ?? '',
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      maxMessageLength: (json['max_message_length'] as num?)?.toInt() ?? 1000,
      peerName: peer['full_name']?.toString() ?? 'Contacto Muvv',
      peerRole: peer['role']?.toString() ?? 'client',
      peerAvatarUrl: peer['avatar_url']?.toString(),
    );
  }
}
