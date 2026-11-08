import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:geocoding/geocoding.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/map_thumbnail.dart';
import '../core/watermark_composer.dart';
import '../data/photo_model.dart';
import '../data/photo_repository.dart';
import '../state/camera_provider.dart';
import '../state/location_provider.dart';
import 'gallery_screen.dart';

// Colores de la interfaz, tomados del logo: negro azulado del espacio
// para la cabecera/footer y el amarillo de la cámara como único acento.
const _kChrome = Color(0xFF070B16);
const _kAccent = Color(0xFFFFC400);

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  bool _isSaving = false;
  String?
  _lastPhotoPath; // ruta de la última foto, para la miniatura del footer

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CameraProvider>().initializeCamera();
      context.read<LocationProvider>().startTracking();
      _loadLastPhoto();
    });
  }

  Future<void> _loadLastPhoto() async {
    final repository = context.read<PhotoRepository>();
    final photos = await repository.getAllPhotos();
    if (!mounted) return;
    setState(() {
      _lastPhotoPath = photos.isNotEmpty ? photos.first.filePath : null;
    });
  }

  Future<void> _openGallery() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const GalleryScreen()));
    if (!mounted) return;
    _loadLastPhoto(); // por si se eliminó alguna foto en la galería
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

          // Evitamos duplicados: solo agregamos barrio y código postal
          // si el texto de "street" no los incluye ya.
          final street = p.street ?? '';
          final addressParts = <String>[];
          if (street.isNotEmpty) addressParts.add(street);
          final subLocality = p.subLocality;
          if (subLocality != null &&
              subLocality.isNotEmpty &&
              !street.contains(subLocality)) {
            addressParts.add(subLocality);
          }
          final postalCode = p.postalCode;
          if (postalCode != null &&
              postalCode.isNotEmpty &&
              !street.contains(postalCode)) {
            addressParts.add(postalCode);
          }
          addressLine = addressParts.join(', ');
        }
      } catch (_) {
        // Sin internet o sin servicio de geocodificación: seguimos sin dirección.
      }

      Uint8List? mapThumbnail;
      try {
        mapThumbnail = await fetchMapThumbnail(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } catch (_) {
        // Sin mapa: el compositor usa el pin simple de respaldo.
      }

      final logoData = await rootBundle.load('assets/images/logo.png');
      final watermarkedBytes = composeWatermark(
        originalPhotoBytes: _toUint8List(rawBytes),
        latitude: position.latitude,
        longitude: position.longitude,
        cityLine: cityLine,
        addressLine: addressLine,
        takenAt: takenAt,
        appLogoBytes: logoData.buffer.asUint8List(
          logoData.offsetInBytes,
          logoData.lengthInBytes,
        ),
        mapThumbnailBytes: mapThumbnail,
      );

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'geosnap_${takenAt.millisecondsSinceEpoch}.jpg';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(watermarkedBytes);

      // Sin ".jpg": gal agrega la extensión por su cuenta.
      await Gal.putImageBytes(
        watermarkedBytes,
        name: 'geosnap_${takenAt.millisecondsSinceEpoch}',
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
      _loadLastPhoto(); // actualiza la miniatura del footer
    } catch (e, stackTrace) {
      debugPrint('ERROR AL CAPTURAR FOTO: $e');
      debugPrint('$stackTrace');
      _showMessage('Error al capturar la foto: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSoon() => _showMessage('Próximamente');

  @override
  Widget build(BuildContext context) {
    // Estructura: cabecera fija arriba, vista de cámara en el centro
    // (ocupa el espacio sobrante) y footer fijo abajo.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light, // íconos claros sobre fondo oscuro
      child: Scaffold(
        backgroundColor: _kChrome,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildPreview()),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/logo.png',
                width: 44,
                height: 44,
                cacheWidth: 132,
                // Si el logo aún no está en assets, mostramos un ícono.
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.photo_camera, color: _kAccent, size: 40),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'GeoSnap',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            _ReservedSlot(
              icon: Icons.tune,
              tooltip: 'Ajustes',
              onTap: _showSoon,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Consumer2<CameraProvider, LocationProvider>(
      builder: (context, cameraProvider, locationProvider, _) {
        if (cameraProvider.errorMessage != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                cameraProvider.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        }
        final controller = cameraProvider.controller;
        if (!cameraProvider.isInitialized || controller == null) {
          return const Center(
            child: CircularProgressIndicator(color: _kAccent),
          );
        }

        final position = locationProvider.currentPosition;
        final coordsText = position != null
            ? 'Lat: ${position.latitude.toStringAsFixed(6)}\n'
                  'Lon: ${position.longitude.toStringAsFixed(6)}'
            : (locationProvider.errorMessage ?? 'Buscando ubicación...');

        // CameraPreview ya trae su propia relación de aspecto; el Center
        // le deja ocupar el mayor tamaño que quepa sin deformarse.
        return Center(
          child: Stack(
            children: [
              CameraPreview(controller),
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    coordsText,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 150,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        // Los dos extremos miden lo mismo (60), así el botón de captura
        // queda exactamente centrado.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _GalleryButton(photoPath: _lastPhotoPath, onTap: _openGallery),
          _CaptureButton(isSaving: _isSaving, onTap: _takePhoto),
          _ReservedSlot(
            icon: Icons.grid_view,
            tooltip: 'Plantillas',
            onTap: _showSoon,
            size: 60,
          ),
        ],
      ),
    );
  }
}

Uint8List _toUint8List(List<int> bytes) => Uint8List.fromList(bytes);

/// Botón de captura: anillo blanco con el centro amarillo del logo.
class _CaptureButton extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onTap;

  const _CaptureButton({required this.isSaving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSaving ? null : onTap,
      child: Container(
        width: 84,
        height: 84,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSaving ? Colors.white24 : _kAccent,
          ),
          child: isSaving
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _kAccent,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// Miniatura de la última foto; al tocarla abre la galería.
class _GalleryButton extends StatelessWidget {
  final String? photoPath;
  final VoidCallback onTap;

  const _GalleryButton({required this.photoPath, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Galería',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white54, width: 2),
          ),
          child: photoPath != null
              ? Image.file(
                  File(photoPath!),
                  fit: BoxFit.cover,
                  cacheWidth: 200,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.photo_library_outlined,
                    color: Colors.white70,
                  ),
                )
              : const Icon(Icons.photo_library_outlined, color: Colors.white70),
        ),
      ),
    );
  }
}

/// Espacio reservado para una función futura. Se ve atenuado y por ahora
/// solo avisa "Próximamente". Para activarlo, cambia el ícono y el onTap.
class _ReservedSlot extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  const _ReservedSlot({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1.5),
          ),
          child: Icon(icon, color: Colors.white38, size: size * 0.5),
        ),
      ),
    );
  }
}
