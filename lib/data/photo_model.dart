class PhotoModel {
  final String filePath;
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime takenAt;

  PhotoModel({
    required this.filePath,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.takenAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'filePath': filePath,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'takenAt': takenAt.toIso8601String(),
    };
  }

  factory PhotoModel.fromMap(Map<String, dynamic> map) {
    return PhotoModel(
      filePath: map['filePath'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      address: map['address'] as String?,
      takenAt: DateTime.parse(map['takenAt'] as String),
    );
  }
}