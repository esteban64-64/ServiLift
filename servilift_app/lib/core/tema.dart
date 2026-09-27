import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Paleta (misma familia de colores de LiftSafe).
class Colores {
  Colores._();
  static const acento = Color(0xFF0066CC);
  static const navy = Color(0xFF0B1929);
  static const superficie = Color(0xFFF4F7FA);
  static const gris = Color(0xFF6B7A8C);
  static const exito = Color(0xFF0E7C4A);
  static const alerta = Color(0xFFC97B1A);
  static const error = Color(0xFFC0392B);
  static const info = Color(0xFF2F6FB0);
}

ThemeData temaServiLift() {
  final esquema = ColorScheme.fromSeed(seedColor: Colores.acento, primary: Colores.acento, error: Colores.error);
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Colores.superficie,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colores.navy,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
    ),
  );
}

/// Estados por equipo del backend -> etiqueta y color.
class Estados {
  static const etiquetas = {
    'PENDIENTE_APROBACION': 'Pendiente por aprobación',
    'APROBADO_CLIENTE': 'Aprobado',
    'POR_PROGRAMAR': 'Por programar',
    'PROGRAMADO': 'Programado',
    'EN_INSPECCION': 'En inspección',
    'EN_REVISION': 'En revisión técnica',
    'NO_CONFORME': 'No conforme: solicitar 2ª visita',
    'SEGUNDA_VISITA_SOLICITADA': '2ª visita solicitada',
    'INFORME_APROBADO': 'Informe disponible',
    'CERTIFICADO_LISTO': 'Certificado listo',
    'RECHAZADO': 'Rechazado',
    'ANULADO': 'Anulado',
    // cotización
    'BORRADOR': 'Borrador',
    'ENVIADA_CLIENTE': 'Enviada al cliente',
    'APROBADA_CLIENTE': 'Aprobada por el cliente',
    'RECHAZADA_CLIENTE': 'Rechazada por el cliente',
    'ENVIADA_PROGRAMACION': 'En programación',
    'EN_EJECUCION': 'En ejecución',
    'FINALIZADA': 'Finalizada',
    'ANULADA': 'Anulada',
    // informe / certificado
    'PENDIENTE_REVISION': 'Pendiente de revisión',
    'DEVUELTO': 'Devuelto',
    'APROBADO': 'Aprobado',
    'EMITIDO': 'Emitido',
    'ENVIADO_CLIENTE': 'Enviado al cliente',
  };

  static String etiqueta(String? e) => etiquetas[e] ?? (e ?? '').replaceAll('_', ' ');

  static Color color(String? e) {
    switch (e) {
      case 'CERTIFICADO_LISTO':
      case 'INFORME_APROBADO':
      case 'APROBADO_CLIENTE':
      case 'APROBADA_CLIENTE':
      case 'APROBADO':
      case 'FINALIZADA':
      case 'ENVIADO_CLIENTE':
        return Colores.exito;
      case 'RECHAZADO':
      case 'RECHAZADA_CLIENTE':
      case 'ANULADO':
      case 'ANULADA':
      case 'NO_CONFORME':
      case 'DEVUELTO':
        return Colores.error;
      case 'PENDIENTE_APROBACION':
      case 'ENVIADA_CLIENTE':
      case 'POR_PROGRAMAR':
      case 'SEGUNDA_VISITA_SOLICITADA':
      case 'PENDIENTE_REVISION':
      case 'EN_REVISION':
        return Colores.alerta;
      case 'BORRADOR':
        return Colores.gris;
      default:
        return Colores.info;
    }
  }
}

final _moneda = NumberFormat.currency(locale: 'es_CO', customPattern: '¤ #,##0', symbol: '\$', decimalDigits: 0);
String moneda(dynamic v) => _moneda.format(num.tryParse('$v') ?? 0);

String fecha(dynamic v) {
  if (v == null || '$v'.isEmpty) return '-';
  final d = DateTime.tryParse('$v');
  return d == null ? '$v' : DateFormat('dd/MM/yyyy').format(d);
}

String fechaHora(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '-' : DateFormat('dd/MM/yyyy HH:mm').format(d);
}

String hora(dynamic v) => '${v ?? ''}'.length >= 5 ? '$v'.substring(0, 5) : '${v ?? '-'}';
