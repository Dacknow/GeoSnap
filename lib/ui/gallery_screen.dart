import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/photo_model.dart';
import '../data/photo_repository.dart';
import 'photo_detail_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  // Un Future representa un valor que llegará más adelante (aquí, la
  // lista de fotos leída de la base de datos). FutureBuilder lo usa
  // para mostrar "cargando", "error" o "datos" según su estado.
  late Future<List<PhotoModel>> _photosFuture;

  @override
  void initState() {
    super.initState();
    _photosFuture = context.read<PhotoRepository>().getAllPhotos();
  }

  void _reload() {
    setState(() {
      _photosFuture = context.read<PhotoRepository>().getAllPhotos();
    });
  }

  Future<void> _openDetail(PhotoModel photo) async {
    // push<bool> espera a que la pantalla de detalle se cierre y
    // devuelve lo que ella entregue con pop(true). Si devolvió true,
    // significa que se eliminó una foto y hay que recargar la lista.
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PhotoDetailScreen(photo: photo)),
    );
    if (deleted == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Galería')),
      body: FutureBuilder<List<PhotoModel>>(
        future: _photosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar: ${snapshot.error}'));
          }

          final photos = snapshot.data ?? [];
          if (photos.isEmpty) {
            return const Center(
              child: Text('Aún no hay fotos.\nToma la primera desde la cámara.',
                  textAlign: TextAlign.center),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final photo = photos[index];
              return GestureDetector(
                onTap: () => _openDetail(photo),
                child: Image.file(
                  File(photo.filePath),
                  fit: BoxFit.cover,
                  // cacheWidth decodifica la imagen a un tamaño pequeño en
                  // vez del original (varios MP), así la cuadrícula es fluida.
                  cacheWidth: 400,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}