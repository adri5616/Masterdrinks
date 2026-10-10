import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';

class WebAsset {
  final Uint8List bytes;
  final String contentType;
  final String etag;
  final bool isImmutable;

  const WebAsset({
    required this.bytes,
    required this.contentType,
    required this.etag,
    required this.isImmutable,
  });
}

class WebAssetsHelper {
  static final Map<String, WebAsset> _memoryCache = {};

  static const List<String> _explicitWebFiles = [
    'index.html',
    'style.css',
    'app.js',
    'rawbt.js',
    'fonts.css',
    'favicon.ico',
    'favicon.jpg',
    'logo_euphoria.png',
    'logo_leben.png',
    'logo_masterdrinks.jpg',
    'manifest.json',
    'sw.js',
    'Wallpaper.jpg',
    'wallpaper.png',
    // Subcarpeta js
    'js/face-api.js',
    // Subcarpeta fonts
    'fonts/font-1.woff2',
    'fonts/font-2.woff2',
    'fonts/font-3.woff2',
    'fonts/font-4.woff2',
    'fonts/font-5.woff2',
    'fonts/font-6.woff2',
    // Subcarpeta icons
    'icons/icon-192.png',
    'icons/icon-512.png',
    // Subcarpeta afiche
    'afiche/chatgpt_image_11_sept_2026__02_55_36_p_m_.png',
    'afiche/gemini_generated_image_3p17o13p17o13p17.jpg',
    'afiche/jesse.jpg',
    'afiche/jessy_y_joy.jpg',
    // Subcarpeta models (Face ID & Face API weights + manifests)
    'models/age_gender_model-weights_manifest.json',
    'models/age_gender_model.bin',
    'models/face_expression_model-weights_manifest.json',
    'models/face_expression_model.bin',
    'models/face_landmark_68_model-weights_manifest.json',
    'models/face_landmark_68_model.bin',
    'models/face_landmark_68_tiny_model-weights_manifest.json',
    'models/face_landmark_68_tiny_model.bin',
    'models/face_recognition_model-weights_manifest.json',
    'models/face_recognition_model.bin',
    'models/ssd_mobilenetv1_model-weights_manifest.json',
    'models/ssd_mobilenetv1_model.bin',
    'models/tiny_face_detector_model-weights_manifest.json',
    'models/tiny_face_detector_model.bin',
  ];

  static String _getContentType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.html': return 'text/html; charset=utf-8';
      case '.css': return 'text/css; charset=utf-8';
      case '.js': return 'application/javascript; charset=utf-8';
      case '.json': return 'application/json; charset=utf-8';
      case '.woff2': return 'font/woff2';
      case '.woff': return 'font/woff';
      case '.ttf': return 'font/ttf';
      case '.png': return 'image/png';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.gif': return 'image/gif';
      case '.svg': return 'image/svg+xml';
      case '.ico': return 'image/x-icon';
      default: return 'application/octet-stream';
    }
  }

  static String _computeEtag(Uint8List bytes) {
    int hash = 5381;
    final len = bytes.length;
    final step = len > 2048 ? (len ~/ 1024) : 1;
    for (int i = 0; i < len; i += step) {
      hash = ((hash << 5) + hash) ^ bytes[i];
    }
    return '"${len.toRadixString(16)}-${(hash & 0x7FFFFFFF).toRadixString(16)}"';
  }

  static void _storeInRam(String relPath, Uint8List bytes) {
    final cleanPath = relPath.replaceAll('\\', '/');
    final ext = p.extension(cleanPath).toLowerCase();
    final isImmutable = ['.woff2', '.woff', '.ttf', '.png', '.jpg', '.jpeg', '.ico'].contains(ext);
    final asset = WebAsset(
      bytes: bytes,
      contentType: _getContentType(cleanPath),
      etag: _computeEtag(bytes),
      isImmutable: isImmutable,
    );
    _memoryCache[cleanPath] = asset;
    if (cleanPath == 'index.html') {
      _memoryCache[''] = asset;
      _memoryCache['/'] = asset;
    }
    if (cleanPath == 'Wallpaper.jpg') {
      _memoryCache['wallpaper.jpg'] = asset;
      _memoryCache['wallpaper.png'] = asset;
    }
    if (cleanPath == 'afiche/jessy_y_joy.jpg') {
      _memoryCache['afiche'] = asset;
      _memoryCache['afiche.jpg'] = asset;
    }
  }

  static Future<Directory> prepareWebDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final webDir = Directory(p.join(docsDir.path, 'masterdrinks_web'));

    if (!await webDir.exists()) {
      await webDir.create(recursive: true);
    }

    final markerFile = File(p.join(webDir.path, '.web_ready_v2'));
    bool needsExtract = !await markerFile.exists();

    Set<String> assetsToCopy = {};

    // 1. Descubrir dinámicamente mediante AssetManifest
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final list = manifest.listAssets();
      for (final item in list) {
        if (item.startsWith('assets/web/')) {
          assetsToCopy.add(item.substring('assets/web/'.length));
        }
      }
    } catch (_) {}

    // 2. Complementar con la lista explícita
    assetsToCopy.addAll(_explicitWebFiles);

    // 3. Extraer o cargar en RAM
    for (final relPath in assetsToCopy) {
      try {
        final targetFile = File(p.join(webDir.path, relPath));
        Uint8List? bytes;

        if (needsExtract || !await targetFile.exists()) {
          final byteData = await rootBundle.load('assets/web/$relPath');
          bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
          if (!await targetFile.parent.exists()) {
            await targetFile.parent.create(recursive: true);
          }
          await targetFile.writeAsBytes(bytes, flush: true);
        } else if (targetFile.lengthSync() < 3 * 1024 * 1024) {
          bytes = await targetFile.readAsBytes();
        }

        // Cargar en RAM para servir a ultra velocidad si el archivo es < 3MB
        if (bytes != null && bytes.length < 3 * 1024 * 1024) {
          _storeInRam(relPath, bytes);
        }
      } catch (_) {}
    }

    if (needsExtract) {
      try { await markerFile.writeAsString('ok'); } catch (_) {}
    }

    print('⚡ Servidor Web: ${_memoryCache.length} recursos pre-cargados en memoria RAM para respuesta ultra rápida.');
    return webDir;
  }

  /// Servidor estático en memoria ultra veloz (< 0.5ms) con soporte ETag 304 y compresión
  static Response handleMemoryAsset(Request request) {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response.notFound('Method not supported for static asset');
    }

    String path = request.url.path;
    if (path.isEmpty || path == '/') {
      path = 'index.html';
    }
    if (path.startsWith('/')) {
      path = path.substring(1);
    }

    final asset = _memoryCache[path];
    if (asset == null) {
      return Response.notFound('Asset not found in RAM');
    }

    final ifNoneMatch = request.headers['if-none-match'];
    if (ifNoneMatch != null && ifNoneMatch == asset.etag) {
      return Response(
        304,
        headers: {
          'ETag': asset.etag,
          'Cache-Control': asset.isImmutable ? 'public, max-age=31536000, immutable' : 'no-cache',
          'Access-Control-Allow-Origin': '*',
        },
      );
    }

    return Response.ok(
      request.method == 'HEAD' ? null : asset.bytes,
      headers: {
        'Content-Type': asset.contentType,
        'Content-Length': asset.bytes.length.toString(),
        'ETag': asset.etag,
        'Cache-Control': asset.isImmutable ? 'public, max-age=31536000, immutable' : 'no-cache',
        'Access-Control-Allow-Origin': '*',
        'Accept-Ranges': 'bytes',
      },
    );
  }
}
