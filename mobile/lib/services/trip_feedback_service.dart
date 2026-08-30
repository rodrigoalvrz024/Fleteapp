import 'api_service.dart';
import '../core/constants/api_constants.dart';

class TripFeedbackQuestion {
  final String key;
  final String label;

  const TripFeedbackQuestion({required this.key, required this.label});

  factory TripFeedbackQuestion.fromJson(Map<String, dynamic> json) =>
      TripFeedbackQuestion(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
      );
}

class TripFeedbackForm {
  final String recipientRole;
  final List<TripFeedbackQuestion> questions;
  final bool submitted;

  const TripFeedbackForm({
    required this.recipientRole,
    required this.questions,
    required this.submitted,
  });

  factory TripFeedbackForm.fromJson(Map<String, dynamic> json) {
    final values = json['questions'] as List? ?? const [];
    return TripFeedbackForm(
      recipientRole: json['recipient_role']?.toString() ?? '',
      questions: values
          .map((value) => TripFeedbackQuestion.fromJson(
                Map<String, dynamic>.from(value as Map),
              ))
          .where((question) => question.key.isNotEmpty)
          .toList(),
      submitted: json['feedback'] != null,
    );
  }
}

class TripFeedbackService {
  final _api = ApiService();

  Future<TripFeedbackForm> formForFreight(int freightId) async {
    final res = await _api.get('${ApiConstants.feedback}/freights/$freightId');
    return TripFeedbackForm.fromJson(
        Map<String, dynamic>.from(res.data as Map));
  }

  Future<void> submit({
    required int freightId,
    required int overallScore,
    required Map<String, int> answers,
    String? comment,
  }) async {
    await _api.post('${ApiConstants.feedback}/freights/$freightId', {
      'overall_score': overallScore,
      'answers': answers,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    });
  }
}
