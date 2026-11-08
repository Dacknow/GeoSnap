import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/photo_model.dart';
import '../data/photo_repository.dart';

class PhotoDetailScreen extends StatelessWidget {
  final PhotoModel photo;

  const PhotoDetailScreen({super.key, required this.photo});

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text(
          'Se borrará de la app. La copia guardada en la galería del '
          'teléfono no se elimina.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Obtenemos el repositorio ANTES de los await para no usar el
    // context después de una pausa asíncrona.
    final repository = context.read<PhotoRepository>();

    if (photo.id != null) {
      await repository.deletePhoto(photo.id!); // el "!" afirma que no es null
    }
    final file = File(photo.filePath);
    if (await file.exists()) {
      await file.delete();
    }

    if (context.mounted) {
      Navigator.of(context).pop(true); // avisa a la galería que recargue
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Eliminar',
            onPressed: () => _confirmAndDelete(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            // InteractiveViewer permite hacer zoom con dos dedos y arrastrar.
            child: InteractiveViewer(
              child: Center(
                child: Image.file(
                  File(photo.filePath),
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 64),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photo.address != null) Text(photo.address!),
                const SizedBox(height: 4),
                Text(
                  'Lat ${photo.latitude.toStringAsFixed(6)}  '
                  'Long ${photo.longitude.toStringAsFixed(6)}',
                ),
                const SizedBox(height: 4),
                Text(_formatDate(photo.takenAt)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}