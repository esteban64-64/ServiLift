import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/tema.dart';
import 'comunes.dart';

/// Línea de tiempo de un equipo cotizado (estados y hechos: envío, visitas, devoluciones, certificado...).
Future<void> mostrarHistorial(BuildContext context, int idCotizacionEquipo) async {
  Map? h;
  final ok = await ejecutar(context, () async => h = await Api.get('/seguimiento/equipo/$idCotizacionEquipo/historial'));
  if (!ok || h == null || !context.mounted) return;
  final datos = h!;
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Historial ${datos['codigo_servicio']}'),
        Text('${datos['edificio']} · ${datos['equipo']}',
            style: const TextStyle(fontSize: 13, color: Colores.gris, fontWeight: FontWeight.normal)),
        const SizedBox(height: 6),
        EstadoChip(datos['estado_actual'], texto: 'Estado actual: ${datos['estado_etiqueta']}'),
      ]),
      content: SizedBox(
        width: 520,
        child: ListView(shrinkWrap: true, children: [
          for (final e in datos['historial'])
            ListTile(
              dense: true,
              leading: Icon(e['evento'] == true ? Icons.info_outline : Icons.circle,
                  size: e['evento'] == true ? 18 : 12, color: Estados.color(e['estado_nuevo'])),
              title: Text(e['estado_etiqueta'] ?? ''),
              subtitle: Text([
                fechaHora(e['fecha']),
                if (e['usuario'] != null) e['usuario'],
                if (e['comentario'] != null) e['comentario'],
              ].join(' · ')),
            ),
          if ((datos['historial'] as List).isEmpty) const Text('Sin movimientos todavía'),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
    ),
  );
}

/// Botón pequeño para abrir el historial desde cualquier módulo.
class BotonHistorial extends StatelessWidget {
  final int? idCotizacionEquipo;
  final bool compacto;
  const BotonHistorial(this.idCotizacionEquipo, {super.key, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    if (idCotizacionEquipo == null) return const SizedBox.shrink();
    if (compacto) {
      return IconButton(
        tooltip: 'Historial',
        icon: const Icon(Icons.history),
        onPressed: () => mostrarHistorial(context, idCotizacionEquipo!),
      );
    }
    return TextButton.icon(
      onPressed: () => mostrarHistorial(context, idCotizacionEquipo!),
      icon: const Icon(Icons.history, size: 18),
      label: const Text('Historial'),
    );
  }
}
