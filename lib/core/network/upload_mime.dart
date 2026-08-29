import 'package:http_parser/http_parser.dart';

MediaType imageMediaType(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'png':
      return MediaType('image', 'png');
    case 'webp':
      return MediaType('image', 'webp');
    case 'gif':
      return MediaType('image', 'gif');
    case 'jpg':
    case 'jpeg':
      return MediaType('image', 'jpeg');
    default:
      // image_picker re-encodes HEIC to JPEG but may keep a .heic filename.
      return MediaType('image', 'jpeg');
  }
}

String imageUploadFilename(String originalName, {String prefix = 'photo'}) {
  final mime = imageMediaType(originalName);
  final ext = mime.subtype == 'jpeg' ? 'jpg' : mime.subtype;
  return '$prefix.$ext';
}
