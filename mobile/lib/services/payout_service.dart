import '../models/payout_model.dart';
import 'api_service.dart';

class PayoutService {
  final _api = ApiService();

  Future<List<PayoutModel>> listMine() async {
    final res = await _api.get('/payouts/me');
    return (res.data as List)
        .map((item) => PayoutModel.fromJson(item))
        .toList();
  }
}
