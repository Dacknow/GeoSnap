import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Expone la posición GPS actual como estado reactivo.
/// La UI escucha este provider y se actualiza sola cuando la posición cambia.
class LocationProvider extends ChangeNotifier {
  Position? _currentPosition;
  String? _errorMessage;
  bool _isLoading = false;

  Position? get currentPosition => _currentPosition;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;

  /// Pide permisos y arranca el stream de posición en tiempo real.
  Future<void> startTracking() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _errorMessage = 'El GPS del dispositivo está desactivado.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _errorMessage = 'Permiso de ubicación denegado.';
        _isLoading = false;
        notifyListeners();
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _errorMessage = 'Permiso de ubicación denegado permanentemente. Actívalo en Ajustes.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Stream reactivo: cada vez que el GPS reporta una nueva posición,
    // este callback se dispara y notificamos a la UI.
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // metros mínimos entre actualizaciones
      ),
    ).listen((Position position) {
      _currentPosition = position;
      _isLoading = false;
      notifyListeners();
    });
  }
}