import 'dart:io';
import 'dart:typed_data';

import 'package:geocoding/geocoding.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import '../core/map_thumbnail.dart';

import '../data/photo_repository.dart';
import '../data/photo_model.dart';
import '../state/camera_provider.dart';
import '../state/location_provider.dart';
import '../core/watermark_composer.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Arrancamos cámara y GPS apenas se construye la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CameraProvider>().initializeCamera();
      context.read<LocationProvider>().startTracking();
    });
  }

  Future<void> _takePhoto() async {
    final cameraProvider = context.read<CameraProvider>();
    final locationProvider = context.read<LocationProvider>();
    final photoRepository = context.read<PhotoRepository>();

    if (!cameraProvider.isInitialized) {
      _showMessage('La cámara todavía no está lista.');
      return;
    }
    final position = locationProvider.currentPosition;
    if (position == null) {
      _showMessage('Todavía no tenemos tu ubicación. Espera un momento.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final rawBytes = await cameraProvider.takePhotoBytes();
      final takenAt = DateTime.now();

      // Geocodificación inversa: coordenadas -> dirección legible.
      String cityLine = 'Ubicación desconocida';
      String addressLine = '';
      try {
      final geocoding = Geocoding();
      final placemarks = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        cityLine = [
          p.locality,
          p.administrativeArea,
          p.country,
        ].where((s) => s != null && s.isNotEmpty).join(', ');
        final street = p.street ?? '';
        final addressParts = <String>[];
        if (street.isNotEmpty) addressParts.add(street);

        // Solo agregamos subLocality/postalCode si su texto NO está ya
        // contenido dentro de "street" (para no repetir el barrio o el
        // código postal cuando el geocodificador del dispositivo ya los
        // incluyó en la dirección completa).
        final subLocality = p.subLocality;
        if (subLocality != null && subLocality.isNotEmpty && !street.contains(subLocality)) {
          addressParts.add(subLocality);
        }
        final postalCode = p.postalCode;
        if (postalCode != null && postalCode.isNotEmpty && !street.contains(postalCode)) {
          addressParts.add(postalCode);
        }

        addressLine = addressParts.join(', ');
      }
      } catch (_) {
        // Si falla la geocodificación (sin internet, por ejemplo),
        // seguimos solo con coordenadas, sin bloquear la captura.
      }

      Uint8List? mapThumbnail;      
      try {
        mapThumbnail = await fetchMapThumbnail(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } catch (_) {
        // Sin internet o el servicio de tiles falló: seguimos sin mapa real,
        // watermark_composer usará el pin simple de respaldo.
      }

      final watermarkedBytes = composeWatermark(
        originalPhotoBytes: _toUint8List(rawBytes),
        latitude: position.latitude,
        longitude: position.longitude,
        cityLine: cityLine,
        addressLine: addressLine,
        takenAt: takenAt,
        mapThumbnailBytes: mapThumbnail,
      );

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'geosnap_${takenAt.millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(watermarkedBytes);

      await Gal.putImageBytes(
        watermarkedBytes,
        name: 'geosnap_${takenAt.millisecondsSinceEpoch}', // sin ".jpg": gal la agrega solo
      );

      await photoRepository.insertPhoto(
        PhotoModel(
          filePath: file.path,
          latitude: position.latitude,
          longitude: position.longitude,
          address: '$cityLine — $addressLine',
          takenAt: takenAt,
        ),
      );

      _showMessage('Foto guardada en la app y en la galería.');
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('ERROR AL CAPTURAR FOTO: $e');
      // ignore: avoid_print
      print(stackTrace);
      _showMessage('Error al capturar la foto: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GeoSnap')),
      body: Consumer2<CameraProvider, LocationProvider>(
        builder: (context, cameraProvider, locationProvider, _) {
          if (cameraProvider.errorMessage != null) {
            return Center(child: Text(cameraProvider.errorMessage!));
          }
          if (!cameraProvider.isInitialized ||
              cameraProvider.controller == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            children: [
              Positioned.fill(child: CameraPreview(cameraProvider.controller!)),
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black54,
                  child: Text(
                    locationProvider.currentPosition != null
                        ? 'Lat: ${locationProvider.currentPosition!.latitude.toStringAsFixed(6)}\n'
                              'Lon: ${locationProvider.currentPosition!.longitude.toStringAsFixed(6)}'
                        : (locationProvider.errorMessage ??
                              'Buscando ubicación...'),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isSaving ? null : _takePhoto,
        child: _isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.camera_alt),
      ),
    );
  }
}

Uint8List _toUint8List(List<int> bytes) => Uint8List.fromList(bytes);
