import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import 'inspeccion.dart';
import '../../widgets/historial.dart';

/// Agenda del inspector: visitas asignadas; en cada una elige el edificio/equipo a inspeccionar.
class AgendaScreen extends StatelessWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Cargador<List>(
      cargar: () async => await Api.get('/inspecciones/agenda') as List,
      builder: (context, visitas, recargar) {
        if (visitas.isEmpty) {
          return RefreshIndicator(
            onRefresh: recargar,
            child: ListView(children: const [SizedBox(height: 120), Vacio('No tiene visitas asignadas', icono: Icons.event_busy)]),
          );
        }
        return Contenido(
          ancho: 800,
          child: RefreshIndicator(
            onRefresh: recargar,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: visitas.length,
              itemBuilder: (_, i) => _Visita(v: visitas[i], recargar: recargar),
            ),
          ),
        );
      },
    );
  }
}

class _Visita extends StatelessWidget {
  final Map v;
  final Future<void> Function() recargar;
  const _Visita({required this.v, required this.recargar});

  Future<void> _abrir(BuildContext context, Map equipo) async {
    Map? insp = equipo['inspeccion'];
    final segunda = v['tipo_visita'] == 'SEGUNDA';
    // Abre el informe precargado con los datos del edificio y del equipo (lo crea si aún no existe)
    if (insp == null || (segunda && insp['estado'] == 'APROBADA')) {
      dynamic nueva;
      final ok = await ejecutar(context, () async {
        nueva = await Api.post('/inspecciones/iniciar', {
          'id_programacion': v['id_programacion'],
          'id_cotizacion_equipo': equipo['id_cotizacion_equipo'],
          'uuid_offline': const Uuid().v4(),
        });
      });
      if (!ok) return;
      insp = nueva;
    }
    if (!context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => InspeccionScreen(id: insp!['id_inspeccion'])));
    recargar();
  }

  @override
  Widget build(BuildContext context) {
    final ed = v['edificio'] ?? {};
    final fechaV = DateTime.parse(v['fecha_programada']);
    final hoy = DateUtils.isSameDay(fechaV, DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.event, color: hoy ? Colores.exito : Colores.acento),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${DateFormat("EEE d 'de' MMM", 'es_CO').format(fechaV)} · ${hora(v['hora_inicio'])}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (v['tipo_visita'] == 'SEGUNDA') const EstadoChip('NO_CONFORME', texto: 'Segunda visita'),
          ]),
          const SizedBox(height: 6),
          Text('${ed['nombre']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colores.navy)),
          Text('${v['cliente']} · ${v['numero_cotizacion']}'),
          InkWell(
            onTap: () => launchUrl(Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${ed['direccion']}, ${ed['ciudad']}')}')),
            child: Text('${ed['direccion']}, ${ed['ciudad']}  (ver mapa)', style: const TextStyle(color: Colores.acento)),
          ),
          if (ed['administrador_nombre'] != null)
            Text('Contacto: ${ed['administrador_nombre']} ${ed['administrador_telefono'] ?? ''}',
                style: const TextStyle(color: Colores.gris)),
          if (v['observaciones'] != null) Text('Nota: ${v['observaciones']}', style: const TextStyle(color: Colores.gris)),
          const Divider(),
          for (final e in v['equipos'])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.elevator_outlined, size: 30),
              title: Text(e['equipo']['identificacion'], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(e['codigo_servicio']),
              onLongPress: () => mostrarHistorial(context, e['id_cotizacion_equipo']),
              trailing: FilledButton(
                onPressed: () => _abrir(context, e),
                child: Text(_textoBoton(e)),
              ),
            ),
        ]),
      ),
    );
  }

  String _textoBoton(Map e) {
    final insp = e['inspeccion'];
    if (insp == null) return 'Iniciar';
    switch (insp['estado']) {
      case 'EN_CURSO':
      case 'EN_SEGUNDA_VISITA':
        return 'Continuar';
      case 'DEVUELTA':
        return 'Corregir';
      case 'APROBADA':
        return v['tipo_visita'] == 'SEGUNDA' ? 'Iniciar 2ª visita' : 'Ver';
      default:
        return 'Ver';
    }
  }
}
