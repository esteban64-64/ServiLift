import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'almacen/almacen.dart' as almacen;
import 'api.dart';

/// Roles (tabla rol.codigo del backend)
class Rol {
  static const admin = 'ADMIN';
  static const asesor = 'ASESOR';
  static const cliente = 'CLIENTE';
  static const programacion = 'PROGRAMACION';
  static const inspector = 'INSPECTOR';
  static const director = 'DIRECTOR_TECNICO';
  static const certificados = 'CERTIFICADOS';
}

class Sesion extends ChangeNotifier {
  Map<String, dynamic>? usuario;
  bool cargando = true;

  static const _kToken = 'servilift_token';
  static const _kUsuario = 'servilift_usuario';

  bool get autenticado => Api.token != null && usuario != null;
  String get rol => usuario?['rol'] ?? '';
  String get nombre => usuario?['nombre_completo'] ?? '';
  int? get idUsuario => usuario?['id_usuario'];
  bool es(String r) => rol == r || rol == Rol.admin;

  Sesion() {
    Api.alExpirarSesion = cerrar;
  }

  Future<void> restaurar() async {
    final token = await almacen.leer(_kToken);
    final usuarioJson = await almacen.leer(_kUsuario);
    if (token != null && usuarioJson != null) {
      Api.token = token;
      usuario = jsonDecode(usuarioJson);
      try {
        usuario = await Api.get('/auth/me'); // valida que el token siga vigente
      } catch (_) {
        await cerrar();
      }
    }
    cargando = false;
    notifyListeners();
  }

  /// Devuelve null si entra, o el mensaje de error.
  Future<String?> login(String correo, String contrasena) async {
    try {
      final data = await Api.post('/auth/login', {'correo': correo.trim(), 'contrasena': contrasena});
      Api.token = data['access_token'];
      usuario = Map<String, dynamic>.from(data['usuario']);
      await almacen.guardar(_kToken, Api.token!);
      await almacen.guardar(_kUsuario, jsonEncode(usuario));
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.mensaje;
    } catch (_) {
      return 'No hay conexión con el servidor (${Api.baseUrl})';
    }
  }

  Future<void> cerrar() async {
    Api.token = null;
    usuario = null;
    await almacen.borrar(_kToken);
    await almacen.borrar(_kUsuario);
    notifyListeners();
  }
}
