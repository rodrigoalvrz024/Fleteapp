class PayoutModel {
  final int id;
  final int paymentId;
  final int freightId;
  final int driverId;
  final String driverName;
  final double amount;
  final String status;
  final DateTime? scheduledFor;
  final DateTime? paidAt;
  final String? transferReference;
  final String? note;
  final DateTime createdAt;

  const PayoutModel({
    required this.id,
    required this.paymentId,
    required this.freightId,
    required this.driverId,
    required this.driverName,
    required this.amount,
    required this.status,
    this.scheduledFor,
    this.paidAt,
    this.transferReference,
    this.note,
    required this.createdAt,
  });

  factory PayoutModel.fromJson(Map<String, dynamic> json) => PayoutModel(
        id: json['id'],
        paymentId: json['payment_id'],
        freightId: json['freight_id'],
        driverId: json['driver_id'],
        driverName: json['driver_name'] ?? '',
        amount: (json['amount'] as num).toDouble(),
        status: json['status'] ?? 'pending',
        scheduledFor: json['scheduled_for'] != null
            ? DateTime.tryParse(json['scheduled_for'])
            : null,
        paidAt:
            json['paid_at'] != null ? DateTime.tryParse(json['paid_at']) : null,
        transferReference: json['transfer_reference'],
        note: json['note'],
        createdAt: DateTime.parse(json['created_at']),
      );

  String get statusLabel => switch (status) {
        'pending' => 'Pendiente',
        'scheduled' => 'Programada',
        'paid' => 'Pagada',
        'failed' => 'Fallida',
        _ => status,
      };
}
