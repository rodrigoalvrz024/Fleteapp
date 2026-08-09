import '../models/place_suggestion.dart';
import 'api_service.dart';

class PlacesService {
  final ApiService _api = ApiService();

  Future<List<PlaceSuggestion>> autocomplete(
    String query, {
    required String sessionToken,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _api.get('/places/autocomplete', params: {
      'q': query,
      'session_token': sessionToken,
      if (latitude != null) 'lat': latitude,
      if (longitude != null) 'lng': longitude,
    });
    final data = response.data;
    final rawSuggestions = data is Map ? data['suggestions'] : null;
    if (rawSuggestions is! List) return const [];
    return rawSuggestions
        .whereType<Map>()
        .map((item) => PlaceSuggestion.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<PlaceAddress> getAddress(
    String placeId, {
    required String sessionToken,
  }) async {
    final response = await _api.get(
      '/places/$placeId',
      params: {'session_token': sessionToken},
    );
    return PlaceAddress.fromJson(Map<String, dynamic>.from(response.data as Map));
  }
}
