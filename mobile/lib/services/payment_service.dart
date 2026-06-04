import '../core/constants/api_constants.dart';
import 'api_service.dart';

class PaymentStart {
  final String token;
  final String redirectUrl;

  const PaymentStart({required this.token, required this.redirectUrl});
}

class PaymentService {
  final _api = ApiService();

  Future<PaymentStart> initiateWebpay(int freightId) async {
    final res = await _api.post('${ApiConstants.payments}/initiate', {
      'freight_id': freightId,
      'method': 'webpay',
    });
    return PaymentStart(
      token: res.data['token'] as String,
      redirectUrl: res.data['redirect_url'] as String,
    );
  }
}
