import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/camera_provider.dart';
import 'state/location_provider.dart';
import 'data/photo_repository.dart';
import 'ui/capture_screen.dart';

void main() {
  runApp(const GeoSnapApp());
}

class GeoSnapApp extends StatelessWidget {
  const GeoSnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CameraProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        Provider(create: (_) => PhotoRepository()),
      ],
      child: MaterialApp(
        title: 'GeoSnap',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const CaptureScreen(),
      ),
    );
  }
}