import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../../widgets/historial.dart';

String _fechaApi(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _horaApi(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

/// Bandeja de programación: equipos aprobados (1ª visita) y no conformes (2ª visita).
class PorProgramarScreen extends StatelessWidget {
  const PorProgramarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Cargador<List>(
      cargar: () async => await Api.get('/programacion/pendientes') as List,
      builder: (context, lista, recargar) {
        if (lista.isEmpty) return const Vacio('No hay equipos pendientes por programar', icono: Icons.event_available);
        return Contenido(
          child: RefreshIndicator(
            onRefresh: recargar,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final c in lista) ...[
                if ((c['equipos_por_programar'] as List).isNotEmpty)
                  _TarjetaPendiente(c: c, equipos: c['equipos_por_programar'], tipo: 'PRIMERA', recargar: recargar),
                if ((c['equipos_segunda_visita'] as List).isNotEmpty)
                  _TarjetaPendiente(c: c, equipos: c['equipos_segunda_visita'], tipo: 'SEGUNDA', recargar: recargar),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _TarjetaPendiente extends StatelessWidget {
  final Map c;
  final List equipos;
  final String tipo;
  final Future<void> Function() recargar;
  const _TarjetaPendiente({required this.c, required this.equipos, required this.tipo, required this.recargar});

  @override
  Widget build(BuildContext context) {
    final ed = c['edificio_detalle'] ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${c['numero_cotizacion']} · ${c['edificio']}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colores.navy)),
            ),
            EstadoChip(tipo == 'SEGUNDA' ? 'NO_CONFORME' : 'POR_PROGRAMAR',
                texto: tipo == 'SEGUNDA' ? 'Segunda visita' : 'Primera visita'),
          ]),
          Text('${c['cliente']} · ${ed['direccion'] ?? ''}, ${ed['ciudad'] ?? ''}'),
          if (ed['administrador_nombre'] != null)
            Text('Contacto: ${ed['administrador_nombre']} ${ed['administrador_telefono'] ?? ''}',
                style: const TextStyle(color: Colores.gris)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in equipos)
              ActionChip(
                avatar: const Icon(Icons.history, size: 18),
                label: Text(e['dias_restantes'] == null
                    ? e['equipo']['identificacion']
                    : '${e['equipo']['identificacion']} · vence ${fecha(e['fecha_limite_correccion'])} '
                        '(${e['dias_restantes'] < 0 ? 'vencido' : 'quedan ${e['dias_restantes']} días'})'),
                backgroundColor: (e['dias_restantes'] ?? 99) <= 3 ? Colores.error.withValues(alpha: .12) : null,
                tooltip: 'Ver historial',
                onPressed: () => mostrarHistorial(context, e['id_cotizacion_equipo']),
              ),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () async {
                final ok = await showDialog(
                    context: context, builder: (_) => DialogoProgramar(cotizacion: c, equipos: equipos, tipo: tipo));
                if (ok == true) recargar();
              },
              icon: const Icon(Icons.event),
              label: const Text('Programar'),
            ),
          ),
        ]),
      ),
    );
  }
}

class DialogoProgramar extends StatefulWidget {
  final Map cotizacion;
  final List equipos;
  final String tipo;
  const DialogoProgramar({super.key, required this.cotizacion, required this.equipos, required this.tipo});

  @override
  State<DialogoProgramar> createState() => _DialogoProgramarState();
}

class _DialogoProgramarState extends State<DialogoProgramar> {
  List _inspectores = [];
  int? _inspector;
  DateTime _fecha = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _hora = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay? _horaFin;
  late final Set<int> _seleccion = {for (final e in widget.equipos) e['id_cotizacion_equipo'] as int};
  final _obs = TextEditingController();

  @override
  void initState() {
    super.initState();
    Api.get('/usuarios', query: {'rol': 'INSPECTOR'}).then((l) {
      if (mounted) setState(() => _inspectores = (l as List).where((u) => u['rol'] == 'INSPECTOR').toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.tipo == 'SEGUNDA' ? 'Segunda visita' : 'Programar'} ${widget.cotizacion['numero_cotizacion']}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final e in widget.equipos)
              CheckboxListTile(
                dense: true,
                value: _seleccion.contains(e['id_cotizacion_equipo']),
                onChanged: (v) => setState(() =>
                    v == true ? _seleccion.add(e['id_cotizacion_equipo']) : _seleccion.remove(e['id_cotizacion_equipo'])),
                title: Text(e['equipo']['identificacion']),
                subtitle: Text(e['codigo_servicio']),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _inspector,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Inspector'),
              items: [
                for (final u in _inspectores)
                  DropdownMenuItem(value: u['id_usuario'] as int, child: Text(u['nombre_completo'])),
              ],
              onChanged: (v) => setState(() => _inspector = v),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(DateFormat('EEE dd/MM/yyyy', 'es_CO').format(_fecha)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _fecha,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) setState(() => _fecha = d);
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text('Inicio ${_hora.format(context)}'),
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: _hora);
                  if (t != null) setState(() => _hora = t);
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_outlined),
                label: Text(_horaFin == null ? 'Fin estimado' : 'Fin ${_horaFin!.format(context)}'),
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: _horaFin ?? _hora);
                  if (t != null) setState(() => _horaFin = t);
                },
              ),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _obs, maxLines: 2, decoration: const InputDecoration(labelText: 'Observaciones')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            if (_inspector == null || _seleccion.isEmpty) {
              mensaje(context, 'Seleccione inspector y equipos', error: true);
              return;
            }
            final ok = await ejecutar(
                context,
                () => Api.post('/programacion', {
                      'id_cotizacion': widget.cotizacion['id_cotizacion'],
                      'id_inspector': _inspector,
                      'fecha_programada': _fechaApi(_fecha),
                      'hora_inicio': _horaApi(_hora),
                      'hora_fin_estimada': _horaFin == null ? null : _horaApi(_horaFin!),
                      'ids_cotizacion_equipo': _seleccion.toList(),
                      'tipo_visita': widget.tipo,
                      'observaciones': _obs.text.trim().isEmpty ? null : _obs.text.trim(),
                    }),
                exito: 'Programado. Se notificó al inspector.');
            if (ok && context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Programar y notificar'),
        ),
      ],
    );
  }
}

/// Visitas programadas (agenda de todos los inspectores).
class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key});

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  DateTime _desde = DateTime.now().subtract(const Duration(days: 1));
  final _cargador = GlobalKey<CargadorState<List>>();

  @override
  Widget build(BuildContext context) {
    return Contenido(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text('Desde ${DateFormat('dd/MM/yyyy').format(_desde)}'),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _desde,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) {
                  _desde = d;
                  _cargador.currentState?.recargar();
                }
              },
            ),
          ]),
        ),
        Expanded(
          child: Cargador<List>(
            key: _cargador,
            cargar: () async => await Api.get('/programacion', query: {'desde': _fechaApi(_desde)}) as List,
            builder: (context, lista, recargar) {
              if (lista.isEmpty) return const Vacio('No hay visitas programadas', icono: Icons.calendar_month);
              final porDia = <String, List>{};
              for (final p in lista) {
                porDia.putIfAbsent(p['fecha_programada'], () => []).add(p);
              }
              return ListView(padding: const EdgeInsets.all(12), children: [
                for (final d in porDia.entries) ...[
                  Titulo(DateFormat("EEEE d 'de' MMMM", 'es_CO').format(DateTime.parse(d.key))),
                  for (final p in d.value) _Visita(p: p, recargar: recargar),
                ],
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _Visita extends StatelessWidget {
  final Map p;
  final Future<void> Function() recargar;
  const _Visita({required this.p, required this.recargar});

  @override
  Widget build(BuildContext context) {
    final cerrada = p['estado'] == 'REALIZADA' || p['estado'] == 'CANCELADA';
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(hora(p['hora_inicio']), style: const TextStyle(fontSize: 11))),
        title: Text('${p['numero_cotizacion']} · ${p['edificio']?['nombre'] ?? ''}'
            '${p['tipo_visita'] == 'SEGUNDA' ? ' (2ª visita)' : ''}'),
        subtitle: Text('${p['inspector']} · ${(p['equipos'] as List).map((e) => e['equipo']['identificacion']).join(', ')}'
            '\n${p['edificio']?['direccion'] ?? ''}'),
        isThreeLine: true,
        trailing: cerrada
            ? EstadoChip(p['estado'])
            : PopupMenuButton<String>(
                onSelected: (op) async {
                  final motivo = await pedirTexto(context, op == 'cancelar' ? 'Cancelar visita' : 'Reprogramar visita',
                      etiqueta: 'Motivo');
                  if (motivo == null || !context.mounted) return;
                  if (op == 'cancelar') {
                    if (await ejecutar(context,
                        () => Api.post('/programacion/${p['id_programacion']}/cancelar', {'motivo_cambio': motivo}),
                        exito: 'Visita cancelada')) {
                      recargar();
                    }
                    return;
                  }
                  final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(p['fecha_programada']),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d == null || !context.mounted) return;
                  final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
                  if (t == null || !context.mounted) return;
                  if (await ejecutar(
                      context,
                      () => Api.put('/programacion/${p['id_programacion']}',
                          {'fecha_programada': _fechaApi(d), 'hora_inicio': _horaApi(t), 'motivo_cambio': motivo}),
                      exito: 'Visita reprogramada')) {
                    recargar();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reprogramar', child: Text('Reprogramar')),
                  PopupMenuItem(value: 'cancelar', child: Text('Cancelar')),
                ],
              ),
      ),
    );
  }
}
