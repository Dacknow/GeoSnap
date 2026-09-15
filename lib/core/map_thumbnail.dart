import 'dart:typed_data';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Descarga un mosaico de tiles de OpenStreetMap alrededor de las
/// coordenadas dadas y devuelve una miniatura cuadrada centrada
/// exactamente en el punto, con un pin rojo y la atribución de OSM.
///
/// A diferencia de composeWatermark, esta función SÍ hace una llamada
/// de red, por eso vive separada del compositor puro de la marca de agua.
Future<Uint8List> fetchMapThumbnail({
  required double latitude,
  required double longitude,
  int zoom = 17,
  int outputSize = 300,
}) async {
  const tileSize = 256;
  final n = math.pow(2, zoom).toDouble();

  final xFloat = (longitude + 180.0) / 360.0 * n;
  final latRad = latitude * math.pi / 180.0;
  final yFloat =
      (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
          2.0 *
          n;

  final centerTileX = xFloat.floor();
  final centerTileY = yFloat.floor();

  final mosaic = img.Image(width: tileSize * 3, height: tileSize * 3);

  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      final tx = centerTileX + dx;
      final ty = centerTileY + dy;
      final url = 'https://tile.openstreetmap.org/$zoom/$tx/$ty.png';
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'GeoSnapApp/1.0 (proyecto academico)'},
        );
        if (response.statusCode == 200) {
          final tile = img.decodePng(response.bodyBytes);
          if (tile != null) {
            img.compositeImage(
              mosaic,
              tile,
              dstX: (dx + 1) * tileSize,
              dstY: (dy + 1) * tileSize,
            );
          }
        }
      } catch (_) {
        // Si un tile puntual falla, seguimos con los demás.
      }
    }
  }

  final pointX = ((xFloat - centerTileX) + 1) * tileSize;
  final pointY = ((yFloat - centerTileY) + 1) * tileSize;

  final half = outputSize ~/ 2;
  var cropX = (pointX - half).round().clamp(0, mosaic.width - outputSize);
  var cropY = (pointY - half).round().clamp(0, mosaic.height - outputSize);

  final cropped = img.copyCrop(
    mosaic,
    x: cropX,
    y: cropY,
    width: outputSize,
    height: outputSize,
  );

  final pinX = (pointX - cropX).round();
  final pinY = (pointY - cropY).round();
  _drawPin(cropped, pinX, pinY, outputSize * 0.09, img.ColorRgb8(210, 45, 45));

  img.fillRect(
    cropped,
    x1: 0,
    y1: cropped.height - 16,
    x2: cropped.width,
    y2: cropped.height,
    color: img.ColorRgba8(255, 255, 255, 200),
  );
  img.drawString(
    cropped,
    '© OpenStreetMap',
    font: img.arial14,
    x: 4,
    y: cropped.height - 15,
    color: img.ColorRgb8(30, 30, 30),
  );

  return Uint8List.fromList(img.encodePng(cropped));
}

void _drawPin(img.Image image, int centerX, int centerY, double radius, img.Color color) {
  final r = radius.round();
  final headCenterY = centerY - (r * 0.6).round();
  img.fillPolygon(
    image,
    vertices: [
      img.Point((centerX - r * 0.55).toDouble(), (headCenterY + r * 0.2).toDouble()),
      img.Point((centerX + r * 0.55).toDouble(), (headCenterY + r * 0.2).toDouble()),
      img.Point(centerX.toDouble(), (centerY + r * 0.8).toDouble()),
    ],
    color: color,
  );
  img.fillCircle(image, x: centerX, y: headCenterY, radius: r, color: color);
  img.fillCircle(
    image,
    x: centerX,
    y: headCenterY,
    radius: (r * 0.4).round(),
    color: img.ColorRgb8(255, 255, 255),
  );
}