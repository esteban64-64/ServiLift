import 'package:shared_preferences/shared_preferences.dart';

Future<String?> leer(String clave) async => (await SharedPreferences.getInstance()).getString(clave);

Future<void> guardar(String clave, String valor) async =>
    (await SharedPreferences.getInstance()).setString(clave, valor);

Future<void> borrar(String clave) async => (await SharedPreferences.getInstance()).remove(clave);
