// Este archivo compone la marca de agua sobre una fotografía.
// Es la "función pura" de nuestra arquitectura: no toca la red,
// no toca el disco, no depende de Flutter. Solo recibe datos y
// devuelve bytes de una nueva imagen.

import 'dart:typed_data'; // Uint8List: un arreglo eficiente de bytes (0-255).

import 'package:image/image.dart' as img;

// "as img" le da un alias (apodo) a todo el paquete. Así, en vez de
// escribir Image, Color, etc. (que podrían chocar con nombres de
// Flutter), escribimos img.Image, img.Color, etc.

/// En Dart, los parámetros dentro de `{ }` son "nombrados": quien llama
/// a la función debe escribir explícitamente `latitude: 3.4`, no solo
/// pasar el número en orden. `required` significa que ese parámetro
/// nombrado es obligatorio (sin `required`, sería opcional).
/// Los parámetros con un valor por defecto (como `appName = 'GeoSnap'`)
/// son opcionales: si no los pasas, Dart usa ese valor automáticamente.
Uint8List composeWatermark({
  required Uint8List originalPhotoBytes,
  required double latitude,
  required double longitude,
  required String cityLine,
  required String addressLine,
  required DateTime takenAt,
  required Uint8List appLogoBytes,
  Uint8List? mapThumbnailBytes, // El "?" indica que puede ser null (opcional).
  String appName = 'GeoSnap',
}) {
  // decodeImage() lee los bytes crudos (JPEG/PNG) y los convierte en
  // una estructura de píxeles que sí podemos manipular. Puede fallar
  // (devolver null) si los bytes no son una imagen válida.
  final original = img.decodeImage(originalPhotoBytes);
  if (original == null) {
    throw ArgumentError('No se pudo decodificar la imagen recibida.');
  }
  final appLogo = img.decodeImage(appLogoBytes);
  if (appLogo == null) {
    throw ArgumentError('No se pudo decodificar el logo de la aplicación.');
  }

  // Image.from() crea una COPIA. Es importante no modificar "original"
  // directamente: en programación funcional evitamos mutar datos que
  // no nos pertenecen, y aquí "original" representa la entrada intacta.
  final photo = img.Image.from(original);
  final w = photo.width;
  final h = photo.height;

  // Todas las medidas se calculan como PORCENTAJE del ancho de la foto
  // (no en píxeles fijos), para que el diseño se vea proporcional sin
  // importar si la foto es de un celular viejo (1080px) o uno nuevo (4000px).
  final margin = (w * 0.03).round();
  final padding = (w * 0.02).round();
  final gap = (w * 0.015).round();

  // --- PASO 1: pre-renderizamos cada línea de texto por separado ---
  // Esto nos permite MEDIR la altura y el ancho reales de cada línea
  // antes de decidir el tamaño de la caja. Así la caja se ajusta al
  // contenido, en vez de usar una altura fija adivinada.

  // Usamos arial48 para la ciudad y arial24 para el resto, en vez de
  // agrandar arial14 artificialmente. Estas fuentes bitmap ya vienen
  // con más "resolución" nativa, así que se ven nítidas incluso con
  // un escalado mínimo (a diferencia de estirar la fuente chica).

  const citySale = 0.60; // arial48 es grande; lo reducimos un poco.
  const secondaryScale =
      0.80; // arial24 es grande para la caja de texto, lo reducimos un poco.

  final estimatedFinalWidth =
      (w - margin * 2 - gap - padding * 2 - (w * 0.15).round());
  final maxRawCityWidth = (estimatedFinalWidth / citySale).floor();
  final maxRawSecondaryWidth = (estimatedFinalWidth / secondaryScale).floor();

  final truncatedCityLine = _truncateToWidth(
    cityLine,
    maxRawCityWidth,
    img.arial48,
  );
  final cityImg = _renderBoldScaledText(
    truncatedCityLine,
    img.arial48,
    img.ColorRgb8(255, 255, 255),
    citySale,
  );

  final addressLines = _wrapTwoLines(
    addressLine,
    maxRawSecondaryWidth,
    img.arial24,
  );
  final addressImgs = addressLines
      .map(
        (line) => _renderBoldScaledText(
          line,
          img.arial24,
          img.ColorRgb8(230, 230, 230),
          secondaryScale,
        ),
      )
      .toList();

  final coordsImg = _renderCoordsLine(
    latitude: latitude,
    longitude: longitude,
    font: img.arial24,
    color: img.ColorRgb8(230, 230, 230),
    preferredScale: secondaryScale,
    maxWidth: estimatedFinalWidth, // nunca se sale del ancho disponible
  );

  final dateImg = _renderBoldScaledText(
    _formatDate(takenAt),
    img.arial24,
    img.ColorRgb8(230, 230, 230),
    secondaryScale,
  );
  final tzImg = _renderBoldScaledText(
    _formatTimezone(takenAt),
    img.arial24,
    img.ColorRgb8(230, 230, 230),
    secondaryScale,
  );

  final lineGap = (cityImg.height * 0.18).round();

  // fold() recorre una lista acumulando un resultado, empezando en 0.
  // Aquí sumamos la altura de cada línea de dirección más su espacio.
  // Es el equivalente funcional de: sum = 0; for (l in lista) sum += ...
  final addressBlockHeight = addressImgs.fold<int>(
    0,
    (sum, lineImg) => sum + lineImg.height + lineGap,
  );

  final textBlockHeight =
      cityImg.height +
      lineGap +
      addressBlockHeight +
      coordsImg.height +
      lineGap +
      dateImg.height;

  final boxHeight = textBlockHeight + padding * 2;
  final boxBottom = h - margin;
  final boxTop = boxBottom - boxHeight;

  // --- PASO 2: miniatura del mapa, misma altura que la caja de texto ---
  final mapBoxLeft = margin;
  final mapBoxSize = boxHeight;
  final mapRadius =
      mapBoxSize *
      0.05; // esquinas redondeadas del mapa (5% del tamaño del cuadro)

  if (mapThumbnailBytes != null) {
    final mapImg = img.decodeImage(mapThumbnailBytes);
    if (mapImg != null) {
      final resizedMap = img.copyResize(
        mapImg,
        width: mapBoxSize,
        height: mapBoxSize,
      );
      _compositeRounded(photo, resizedMap, mapBoxLeft, boxTop, mapRadius);
    }
  } else {
    // Si no hay mapa (por ejemplo, sin internet), dibujamos un
    // respaldo simple: un cuadro gris con un pin.
    img.fillRect(
      photo,
      x1: mapBoxLeft,
      y1: boxTop,
      x2: mapBoxLeft + mapBoxSize,
      y2: boxTop + mapBoxSize,
      color: img.ColorRgba8(205, 205, 205, 255),
      radius: mapRadius,
    );
    _drawSimplePin(
      photo,
      mapBoxLeft + mapBoxSize ~/ 2,
      boxTop + mapBoxSize ~/ 2,
      mapBoxSize * 0.22,
      img.ColorRgb8(210, 45, 45),
    );
    // El operador ~/ es división ENTERA (descarta el residuo), a
    // diferencia de / que siempre devuelve un double en Dart.
  }

  // --- PASO 3: caja de texto semitransparente ---
  final textBoxLeft = mapBoxLeft + mapBoxSize + gap;
  final textBoxRight = w - margin;

  img.fillRect(
    photo,
    x1: textBoxLeft,
    y1: boxTop,
    x2: textBoxRight,
    y2: boxBottom,
    color: img.ColorRgba8(25, 25, 25, 190), // alpha 190/255 ≈ 74% opaco.
    radius: w * 0.01,
  );

  // --- PASO 4: etiqueta con el nombre de la app ---
  final labelHeight = (h * 0.032).round();
  final labelWidth = (w * 0.24).round();
  final labelLeft = textBoxRight - labelWidth;
  final labelTop = (boxTop - labelHeight).clamp(0, h - labelHeight);

  _fillTopRoundedRect(
    photo,
    x1: labelLeft,
    y1: labelTop,
    x2: labelLeft + labelWidth,
    y2: labelTop + labelHeight,
    color: img.ColorRgba8(25, 25, 25, 190),
    radius: h * 0.01,
  );

  final logoSize = (labelHeight * 0.82).round();
  final resizedLogo = img.copyResize(
    appLogo,
    width: logoSize,
    height: logoSize,
  );
  img.compositeImage(
    photo,
    resizedLogo,
    dstX: labelLeft + (labelHeight * 0.12).round(),
    dstY: labelTop + (labelHeight - logoSize) ~/ 2,
  );
  img.drawString(
    photo,
    appName,
    font: img.arial14,
    x: labelLeft + (labelHeight * 1.05).round(),
    y: labelTop + (labelHeight * 0.2).round(),
    color: img.ColorRgb8(255, 255, 255),
  );

  // --- PASO 5: colocar el texto ya renderizado dentro de la caja ---
  final textLeft = textBoxLeft + padding;
  var lineY = boxTop + padding;
  // "var" infiere el tipo automáticamente (aquí, int) y SÍ permite
  // reasignar el valor después (a diferencia de "final", que es de
  // una sola asignación).

  img.compositeImage(photo, cityImg, dstX: textLeft, dstY: lineY);
  lineY += cityImg.height + lineGap;

  for (final lineImg in addressImgs) {
    img.compositeImage(photo, lineImg, dstX: textLeft, dstY: lineY);
    lineY += lineImg.height + lineGap;
  }

  img.compositeImage(photo, coordsImg, dstX: textLeft, dstY: lineY);
  lineY += coordsImg.height + lineGap;

  // Fecha a la izquierda...
  img.compositeImage(photo, dateImg, dstX: textLeft, dstY: lineY);
  // ...y zona horaria pegada al borde derecho REAL de la caja, usando
  // el ancho EXACTO de su propio render (tzImg.width ya no es una
  // estimación, por eso ahora sí queda alineada sin pisar la fecha).
  img.compositeImage(
    photo,
    tzImg,
    dstX: textBoxRight - padding - tzImg.width,
    dstY: lineY,
  );

  // encodeJpg vuelve a comprimir la imagen ya editada a bytes JPEG.
  return Uint8List.fromList(img.encodeJpg(photo, quality: 97));
}

/// Mide el ancho EXACTO (en píxeles) que ocupará un texto con una
/// fuente dada, sumando el "avance" (xAdvance) de cada carácter.
/// Esto reemplaza cualquier aproximación y es la clave para que el
/// texto quede bien alineado y no se corte de más ni de menos.
int _measureTextWidth(String text, img.BitmapFont font) {
  var width = 0;
  // text.codeUnits convierte el String en una lista de códigos
  // numéricos (uno por carácter), que es como la fuente bitmap
  // identifica cada glifo.
  for (final code in text.codeUnits) {
    final glyph = font.characters[code];
    if (glyph != null) {
      width += glyph.xAdvance;
    }
  }
  return width;
}

/// Compone [src] sobre [dst], pero solo copia los píxeles que caen
/// DENTRO de un rectángulo de esquinas redondeadas. Los píxeles de
/// las 4 esquinas se dejan tal cual estaban en dst (o sea, se ve la
/// foto original ahí), logrando el efecto de esquinas redondeadas
/// sin depender de una función de "máscara" de terceros.
void _compositeRounded(
  img.Image dst,
  img.Image src,
  int dstX,
  int dstY,
  double radius,
) {
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      if (_insideRoundedRect(
        x.toDouble(),
        y.toDouble(),
        src.width.toDouble(),
        src.height.toDouble(),
        radius,
      )) {
        dst.setPixel(dstX + x, dstY + y, src.getPixel(x, y));
      }
    }
  }
}

/// Prueba geométrica: ¿el punto (x,y) cae dentro de un rectángulo de
/// ancho w, alto h, con esquinas redondeadas de radio r?
bool _insideRoundedRect(double x, double y, double w, double h, double r) {
  if (x >= r && x <= w - r) return true; // franja central horizontal
  if (y >= r && y <= h - r) return true; // franja central vertical
  // Si no está en ninguna franja, solo puede estar en una esquina:
  // comprobamos si cae dentro del círculo de esa esquina (distancia <= r).
  final cx = x < r ? r : w - r;
  final cy = y < r ? r : h - r;
  final dx = x - cx;
  final dy = y - cy;
  return (dx * dx + dy * dy) <= r * r;
}

/// Renderiza un texto en "negrita" (dibujándolo 4 veces con
/// desplazamientos de 1px) sobre un lienzo del tamaño EXACTO que
/// necesita (medido con _measureTextWidth, no adivinado), y luego lo
/// agranda con interpolación 'nearest' (sin difuminar) para que se
/// vea nítido en vez de borroso.
img.Image _renderBoldScaledText(
  String text,
  img.BitmapFont font,
  img.Color color,
  double scale,
) {
  final textWidth = _measureTextWidth(text, font);
  final tempWidth = textWidth + 4; // pequeño margen por el efecto negrita
  final tempHeight = font.lineHeight + 4;

  // numChannels: 4 significa RGBA (con canal de transparencia), necesario
  // para poder pegar este texto sobre la foto sin traer un fondo sólido.
  final temp = img.Image(width: tempWidth, height: tempHeight, numChannels: 4);
  img.fill(temp, color: img.ColorRgba8(0, 0, 0, 0)); // fondo 100% transparente

  const boldOffsets = [
    [0, 0],
    [1, 0],
    [0, 1],
    [1, 1],
  ];
  for (final offset in boldOffsets) {
    img.drawString(
      temp,
      text,
      font: font,
      x: offset[0],
      y: offset[1],
      color: color,
    );
  }

  final scaledWidth = (tempWidth * scale).round();
  final scaledHeight = (tempHeight * scale).round();
  return img.copyResize(
    temp,
    width: scaledWidth,
    height: scaledHeight,
    interpolation: img.Interpolation.cubic,
  );
}

/// Renderiza la línea de coordenadas con el símbolo "°" dibujado como
/// un pequeño anillo (no como texto), ya que las fuentes bitmap arial
/// de este paquete no incluyen ese carácter. Además, si el texto
/// completo no cabe en [maxWidth] a la escala preferida, reduce la
/// escala automáticamente para que SIEMPRE quede completo (nunca se
/// corta el último decimal).
img.Image _renderCoordsLine({
  required double latitude,
  required double longitude,
  required img.BitmapFont font,
  required img.Color color,
  required double preferredScale,
  required int maxWidth,
}) {
  final latStr = 'Lat ${latitude.toStringAsFixed(6)}';
  const sepStr = ' Long ';
  final lonStr = longitude.toStringAsFixed(6);

  final latWidth = _measureTextWidth(latStr, font);
  final sepWidth = _measureTextWidth(sepStr, font);
  final lonWidth = _measureTextWidth(lonStr, font);

  final degreeDiameter = (font.lineHeight * 0.22).round();
  final degreeGap = (font.lineHeight * 0.08).round();

  final totalWidth =
      latWidth +
      degreeGap +
      degreeDiameter +
      sepWidth +
      lonWidth +
      degreeGap +
      degreeDiameter +
      8;
  final tempHeight = font.lineHeight + 4;

  final temp = img.Image(width: totalWidth, height: tempHeight, numChannels: 4);
  img.fill(temp, color: img.ColorRgba8(0, 0, 0, 0));

  const boldOffsets = [
    [0, 0],
    [1, 0],
    [0, 1],
    [1, 1],
  ];
  var x = 0;
  final degreeY = (font.lineHeight * 0.12).round();
  final outerR = degreeDiameter ~/ 2;
  final innerR = (outerR * 0.5).round();

  for (final o in boldOffsets) {
    img.drawString(
      temp,
      latStr,
      font: font,
      x: x + o[0],
      y: o[1],
      color: color,
    );
  }
  x += latWidth + degreeGap;

  // "°" simulado: círculo relleno con un círculo transparente encima,
  // formando un anillo (ya que fillCircle solo dibuja discos sólidos).
  img.fillCircle(
    temp,
    x: x + outerR,
    y: degreeY + outerR,
    radius: outerR,
    color: color,
  );
  img.fillCircle(
    temp,
    x: x + outerR,
    y: degreeY + outerR,
    radius: innerR,
    color: img.ColorRgba8(0, 0, 0, 0),
  );
  x += degreeDiameter + degreeGap;

  for (final o in boldOffsets) {
    img.drawString(
      temp,
      sepStr,
      font: font,
      x: x + o[0],
      y: o[1],
      color: color,
    );
  }
  x += sepWidth;

  for (final o in boldOffsets) {
    img.drawString(
      temp,
      lonStr,
      font: font,
      x: x + o[0],
      y: o[1],
      color: color,
    );
  }
  x += lonWidth + degreeGap;

  img.fillCircle(
    temp,
    x: x + outerR,
    y: degreeY + outerR,
    radius: outerR,
    color: color,
  );
  img.fillCircle(
    temp,
    x: x + outerR,
    y: degreeY + outerR,
    radius: innerR,
    color: img.ColorRgba8(0, 0, 0, 0),
  );

  // Si a la escala preferida el texto no cabe en maxWidth, la reducimos
  // justo lo necesario para que quepa completo.
  var scale = preferredScale;
  if (totalWidth * scale > maxWidth) {
    scale = maxWidth / totalWidth;
  }

  final scaledWidth = (totalWidth * scale).round();
  final scaledHeight = (tempHeight * scale).round();
  return img.copyResize(
    temp,
    width: scaledWidth,
    height: scaledHeight,
    interpolation: img.Interpolation.cubic,
  );
}

void _drawSimplePin(
  img.Image image,
  int centerX,
  int centerY,
  double radius,
  img.Color color,
) {
  final r = radius.round();
  final headCenterY = centerY - (r * 0.3).round();
  img.fillPolygon(
    image,
    vertices: [
      img.Point(
        (centerX - r * 0.55).toDouble(),
        (headCenterY + r * 0.2).toDouble(),
      ),
      img.Point(
        (centerX + r * 0.55).toDouble(),
        (headCenterY + r * 0.2).toDouble(),
      ),
      img.Point(centerX.toDouble(), (centerY + r * 1.4).toDouble()),
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

/// Rellena un rectángulo con las esquinas SUPERIORES redondeadas y las
/// esquinas INFERIORES en ángulo recto (como una "pestaña" o "tab").
/// Hace mezcla alfa manual (leyendo el píxel de fondo y mezclándolo con
/// el color nuevo) para que funcione igual de bien con transparencia
/// que img.fillRect, pero con radios distintos por esquina.
void _fillTopRoundedRect(
  img.Image image, {
  required int x1,
  required int y1,
  required int x2,
  required int y2,
  required img.Color color,
  required double radius,
}) {
  final w = x2 - x1;
  final h = y2 - y1;
  final r = radius;
  final alpha = color.a / 255.0; // 0.0 = transparente, 1.0 = opaco

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var inside = true;

      // Solo evaluamos "¿es esquina redondeada?" en la franja superior
      // (y < r) y en las columnas de los extremos (x < r o x > w - r).
      // El resto del rectángulo (incluidas las esquinas de ABAJO)
      // siempre se considera "dentro", o sea, en ángulo recto.
      if (y < r && (x < r || x > w - r)) {
        final cx = x < r ? r : w - r;
        const cy = 0.0;
        final dx = x - cx;
        final dy = y - (cy + r);
        inside = (dx * dx + dy * dy) <= r * r;
      }

      if (inside) {
        final px = x1 + x;
        final py = y1 + y;
        // Si por algún cálculo de layout la posición cae fuera de la
        // imagen, simplemente la saltamos en vez de crashear.
        if (px < 0 || py < 0 || px >= image.width || py >= image.height) {
          continue;
        }
        final bg = image.getPixel(px, py);
        // Mezcla alfa manual: resultado = fondo*(1-alpha) + color*alpha
        final nr = (bg.r * (1 - alpha) + color.r * alpha).round();
        final ng = (bg.g * (1 - alpha) + color.g * alpha).round();
        final nb = (bg.b * (1 - alpha) + color.b * alpha).round();
        image.setPixelRgb(px, py, nr, ng, nb);
      }
    }
  }
}

/// Parte un texto en máximo 2 líneas, cortando entre palabras (no a
/// la mitad de una palabra), usando el ancho REAL medido en píxeles.
/// Si aún así la segunda línea no cabe, ahí sí se trunca con "...".
List<String> _wrapTwoLines(String text, int maxWidthPx, img.BitmapFont font) {
  if (_measureTextWidth(text, font) <= maxWidthPx) {
    return [text]; // Cabe completo en una sola línea, no hace falta partir.
  }

  final words = text.split(' ');
  var firstLine = '';
  var splitIndex = 0;

  for (var i = 0; i < words.length; i++) {
    final candidate = firstLine.isEmpty ? words[i] : '$firstLine ${words[i]}';
    if (_measureTextWidth(candidate, font) > maxWidthPx &&
        firstLine.isNotEmpty) {
      break; // Esta palabra ya no cabe: paramos antes de agregarla.
    }
    firstLine = candidate;
    splitIndex = i + 1;
  }

  var secondLine = words.sublist(splitIndex).join(' ');
  while (_measureTextWidth(secondLine, font) > maxWidthPx &&
      secondLine.length > 3) {
    secondLine = '${secondLine.substring(0, secondLine.length - 4)}...';
  }

  return [firstLine, secondLine];
}

/// Corta el texto y agrega "..." si excede el ancho disponible,
/// usando el ancho EXACTO medido carácter por carácter (no una
/// aproximación). Se usa para la línea de ciudad, que solo tiene
/// espacio para una línea (a diferencia de la dirección, que puede
/// usar 2 líneas mediante _wrapTwoLines).
String _truncateToWidth(String text, int maxWidthPx, img.BitmapFont font) {
  if (_measureTextWidth(text, font) <= maxWidthPx) return text;

  var truncated = text;
  while (truncated.isNotEmpty &&
      _measureTextWidth('$truncated...', font) > maxWidthPx) {
    truncated = truncated.substring(0, truncated.length - 1);
  }
  return '$truncated...';
}

String _formatDate(DateTime dt) {
  const days = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];
  // dt.weekday va de 1 (lunes) a 7 (domingo); restamos 1 porque las
  // listas en Dart empiezan en el índice 0.
  final dayName = days[dt.weekday - 1];
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final hh24 = dt.hour;
  final ampm = hh24 >= 12
      ? 'p. m.'
      : 'a. m.'; // operador ternario: condición ? siTrue : siFalso
  final hh12 = (hh24 % 12 == 0) ? 12 : hh24 % 12;
  final min = dt.minute.toString().padLeft(2, '0');
  return '$dayName, $dd/$mm/${dt.year} $hh12:$min $ampm';
}

String _formatTimezone(DateTime dt) {
  final offset = dt.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hh = offset.abs().inHours.toString().padLeft(2, '0');
  final mm = (offset.abs().inMinutes % 60).toString().padLeft(2, '0');
  return 'GMT $sign$hh:$mm';
}
