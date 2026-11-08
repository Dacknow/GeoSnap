class PhotoModel {
  final int? id; // null mientras la foto aún no se ha guardado en la BD
  final String filePath;
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime takenAt;

  PhotoModel({
    this.id,
    required this.filePath,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.takenAt,
  });

  Map<String, dynamic> toMap() {
    return {
      // "if" dentro de un mapa literal: solo incluye la clave 'id' si no es
      // null. Al insertar, dejamos que SQLite genere el id (AUTOINCREMENT).
      if (id != null) 'id': id,
      'filePath': filePath,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'takenAt': takenAt.toIso8601String(),
    };
  }

  factory PhotoModel.fromMap(Map<String, dynamic> map) {
    return PhotoModel(
      id: map['id'] as int?,
      filePath: map['filePath'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      address: map['address'] as String?,
      takenAt: DateTime.parse(map['takenAt'] as String),
    );
  }
}