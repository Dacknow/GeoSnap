import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'photo_model.dart';

/// Repositorio orientado a objetos: encapsula todo el acceso a la
/// base de datos local. La UI y los providers nunca hablan con
/// sqflite directamente, solo con esta clase.
class PhotoRepository {
  static const _dbName = 'geosnap.db';
  static const _tableName = 'photos';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filePath TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            address TEXT,
            takenAt TEXT NOT NULL
          )
        ''');
      },
    );
  }

  /// Guarda una nueva foto y devuelve su id autogenerado.
  Future<int> insertPhoto(PhotoModel photo) async {
    final db = await _database;
    return db.insert(_tableName, photo.toMap());
  }

  /// Devuelve todas las fotos guardadas, más recientes primero.
  Future<List<PhotoModel>> getAllPhotos() async {
    final db = await _database;
    final maps = await db.query(_tableName, orderBy: 'takenAt DESC');
    return maps.map((map) => PhotoModel.fromMap(map)).toList();
  }

  /// Elimina el registro de una foto (no borra el archivo físico).
  Future<void> deletePhoto(int id) async {
    final db = await _database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }
}