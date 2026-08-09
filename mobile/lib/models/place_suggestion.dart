class PlaceSuggestion {
  final String placeId;
  final String label;
  final String address;
  final String fullAddress;

  const PlaceSuggestion({
    required this.placeId,
    required this.label,
    required this.address,
    required this.fullAddress,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) => PlaceSuggestion(
        placeId: json['place_id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
        fullAddress: json['full_address']?.toString() ?? '',
      );
}

class PlaceAddress {
  final String address;
  final double latitude;
  final double longitude;

  const PlaceAddress({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory PlaceAddress.fromJson(Map<String, dynamic> json) => PlaceAddress(
        address: json['address']?.toString() ?? '',
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lng'] as num).toDouble(),
      );
}
