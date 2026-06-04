import '../core/constants/api_constants.dart';
import 'api_service.dart';

class RatingService {
  final _api = ApiService();

  Future<void> createRating({
    required int freightId,
    required double score,
    String? comment,
  }) async {
    await _api.post(ApiConstants.ratings, {
      'freight_id': freightId,
      'score': score,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    });
  }
}
