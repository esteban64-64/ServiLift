import 'package:web/web.dart' as web;

Future<String?> leer(String clave) async => web.window.sessionStorage.getItem(clave);

Future<void> guardar(String clave, String valor) async => web.window.sessionStorage.setItem(clave, valor);

Future<void> borrar(String clave) async => web.window.sessionStorage.removeItem(clave);
