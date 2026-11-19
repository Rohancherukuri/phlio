// Reads where and when a JPEG photo was taken from its EXIF block (GPS
// latitude / longitude and DateTimeOriginal), so an Experience can show
// the exact spot without asking. Pure Dart, reads only the file's header.

import 'dart:io';
import 'dart:typed_data';

class PhotoExif {
  const PhotoExif({this.lat, this.lng, this.takenAt});
  final double? lat, lng;
  final DateTime? takenAt;
  bool get hasLocation => lat != null && lng != null && !(lat == 0 && lng == 0);
}

Future<PhotoExif> readPhotoExif(String path) async {
  try {
    final file = File(path);
    final raf = await file.open();
    final head = await raf.read(256 * 1024);
    await raf.close();
    return parseExif(head);
  } catch (_) {
    return const PhotoExif();
  }
}

PhotoExif parseExif(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return const PhotoExif();
  var i = 2;
  while (i + 4 < b.length) {
    if (b[i] != 0xFF) return const PhotoExif();
    final marker = b[i + 1];
    final len = (b[i + 2] << 8) | b[i + 3];
    if (marker == 0xE1 && i + 10 < b.length &&
        b[i + 4] == 0x45 && b[i + 5] == 0x78 && b[i + 6] == 0x69 && b[i + 7] == 0x66) {
      return _tiff(ByteData.sublistView(b, i + 10, (i + 2 + len).clamp(0, b.length)));
    }
    if (marker == 0xDA) break; // image data: no EXIF before it
    i += 2 + len;
  }
  return const PhotoExif();
}

PhotoExif _tiff(ByteData d) {
  if (d.lengthInBytes < 8) return const PhotoExif();
  final little = d.getUint8(0) == 0x49;
  final e = little ? Endian.little : Endian.big;
  int u16(int o) => d.getUint16(o, e);
  int u32(int o) => d.getUint32(o, e);

  // Entries of an IFD at offset o: tag -> (type, count, value offset).
  Map<int, (int, int, int)> ifd(int o) {
    final out = <int, (int, int, int)>{};
    if (o <= 0 || o + 2 > d.lengthInBytes) return out;
    final n = u16(o);
    for (var k = 0; k < n; k++) {
      final p = o + 2 + k * 12;
      if (p + 12 > d.lengthInBytes) break;
      out[u16(p)] = (u16(p + 2), u32(p + 4), p + 8);
    }
    return out;
  }

  String ascii((int, int, int) entry) {
    final (_, count, at) = entry;
    final o = count <= 4 ? at : u32(at);
    final chars = <int>[];
    for (var k = 0; k < count && o + k < d.lengthInBytes; k++) {
      final c = d.getUint8(o + k);
      if (c == 0) break;
      chars.add(c);
    }
    return String.fromCharCodes(chars);
  }

  double? dms((int, int, int)? entry) {
    if (entry == null) return null;
    final o = u32(entry.$3);
    if (o + 24 > d.lengthInBytes) return null;
    double r(int k) {
      final den = u32(o + k * 8 + 4);
      return den == 0 ? 0 : u32(o + k * 8) / den;
    }

    return r(0) + r(1) / 60 + r(2) / 3600;
  }

  final ifd0 = ifd(u32(4));
  double? lat, lng;
  final gpsAt = ifd0[0x8825];
  if (gpsAt != null) {
    final gps = ifd(u32(gpsAt.$3));
    lat = dms(gps[2]);
    lng = dms(gps[4]);
    if (lat != null && gps[1] != null && ascii(gps[1]!).startsWith('S')) lat = -lat;
    if (lng != null && gps[3] != null && ascii(gps[3]!).startsWith('W')) lng = -lng;
  }
  DateTime? taken;
  final exifAt = ifd0[0x8769];
  if (exifAt != null) {
    final exif = ifd(u32(exifAt.$3));
    final original = exif[0x9003];
    if (original != null) {
      final m = RegExp(r'(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})').firstMatch(ascii(original));
      if (m != null) {
        taken = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!),
            int.parse(m[6]!));
      }
    }
  }
  return PhotoExif(lat: lat, lng: lng, takenAt: taken);
}
