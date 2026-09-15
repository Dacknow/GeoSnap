import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Maneja el ciclo de vida del CameraController y expone el estado
/// de inicialización a la UI.
class CameraProvider extends ChangeNotifier {
  CameraController? _controller;
  bool _isInitialized = false;
  String? _errorMessage;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;

  Future<void> initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _errorMessage = 'No se encontró ninguna cámara disponible.';
        notifyListeners();
        return;
      }

      _controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error al inicializar la cámara: $e';
      notifyListeners();
    }
  }

  /// Captura la foto y devuelve los bytes crudos (sin marca de agua todavía).
  Future<List<int>> takePhotoBytes() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw StateError('La cámara no está inicializada.');
    }
    final XFile file = await _controller!.takePicture();
    return await file.readAsBytes();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}