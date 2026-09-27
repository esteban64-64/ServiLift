// Almacenamiento de la sesión.
// En web se usa sessionStorage: cada pestaña del navegador tiene su propia sesión,
// así se puede tener un rol distinto en cada pestaña sin conflicto.
// En Android / Windows se usa SharedPreferences (la sesión se conserva al cerrar la app).
export 'almacen_prefs.dart' if (dart.library.js_interop) 'almacen_web.dart';
