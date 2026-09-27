import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Error con el mensaje "detail" que devuelve FastAPI.
class ApiException implements Exception {
  final int statusCode;
  final String mensaje;
  final List<String> pendientes;
  ApiException(this.statusCode, this.mensaje, [this.pendientes = const []]);

  @override
  String toString() => pendientes.isEmpty ? mensaje : '$mensaje:\n• ${pendientes.join('\n• ')}';
}

/// Archivo en memoria para subir (sirve igual en web, Android y Windows).
class ArchivoSubida {
  final String nombre;
  final List<int> bytes;
  ArchivoSubida(this.nombre, this.bytes);
}

/// Cliente HTTP del backend ServiLift (FastAPI).
class Api {
  Api._();

  static String? token;
  static void Function()? alExpirarSesion;

  /// URL del backend (assets/.env):
  ///   Chrome / Windows -> http://localhost:8000
  ///   Emulador Android -> http://10.0.2.2:8000
  ///   Celular en la misma Wi-Fi -> http://IP_DEL_PC:8000
  static String get baseUrl {
    final url = dotenv.env['API_URL'] ?? 'http://localhost:8000';
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static String url(String path) => path.startsWith('http') ? path : '$baseUrl$path';

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    return Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  static dynamic _procesar(http.Response res) {
    final cuerpo = res.bodyBytes.isEmpty ? null : utf8.decode(res.bodyBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return cuerpo == null || cuerpo.isEmpty ? null : jsonDecode(cuerpo);
    }
    if (res.statusCode == 401 && token != null) {
      alExpirarSesion?.call();
    }
    var mensaje = 'Error ${res.statusCode}';
    var pendientes = <String>[];
    try {
      final json = jsonDecode(cuerpo ?? '');
      final detalle = json is Map ? json['detail'] : null;
      if (detalle is String) {
        mensaje = detalle;
      } else if (detalle is Map) {
        mensaje = detalle['mensaje']?.toString() ?? mensaje;
        pendientes = List<String>.from(detalle['pendientes'] ?? const []);
      } else if (detalle is List && detalle.isNotEmpty) {
        // Errores de validación de FastAPI
        mensaje = detalle.map((e) => '${(e['loc'] as List).last}: ${e['msg']}').join('\n');
      }
    } catch (_) {}
    throw ApiException(res.statusCode, mensaje, pendientes);
  }

  static const _timeout = Duration(seconds: 30);

  static Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      _procesar(await http.get(_uri(path, query), headers: _headers).timeout(_timeout));

  static Future<dynamic> post(String path, [Object? body]) async =>
      _procesar(await http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})).timeout(_timeout));

  static Future<dynamic> put(String path, [Object? body]) async =>
      _procesar(await http.put(_uri(path), headers: _headers, body: jsonEncode(body ?? {})).timeout(_timeout));

  static Future<dynamic> delete(String path) async =>
      _procesar(await http.delete(_uri(path), headers: _headers).timeout(_timeout));

  /// Sube varias fotos en una sola petición (campo "archivos").
  static Future<dynamic> subirArchivos(String path, List<ArchivoSubida> archivos,
      {Map<String, String> campos = const {}}) async {
    final req = http.MultipartRequest('POST', _uri(path))..fields.addAll(campos);
    for (final a in archivos) {
      req.files.add(http.MultipartFile.fromBytes('archivos', a.bytes, filename: a.nombre));
    }
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 3)));
    return _procesar(res);
  }

  /// Pide al backend un enlace temporal y abre el PDF en el navegador / visor.
  static Future<void> abrirPdf(String pathEnlace) async {
    final data = await get(pathEnlace);
    await launchUrl(Uri.parse(url(data['url'] as String)), mode: LaunchMode.externalApplication);
  }
}
