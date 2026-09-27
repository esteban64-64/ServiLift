import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import 'fotos_tab.dart';

const _colorCalif = {'L': Color(0xFF2F6FB0), 'G': Color(0xFFC97B1A), 'MG': Color(0xFFC0392B)};

/// Checklist NTC 5926-1 por zonas. Guarda automáticamente (y reintenta si no hay señal).
/// En segunda visita solo muestra los hallazgos para marcarlos como corregidos / no corregidos.
class ChecklistTab extends StatefulWidget {
  final int idInspeccion;
  final bool editable;
  final bool segundaVisita;
  final bool modoDirector;
  final Future<void> Function()? alCambiar;
  const ChecklistTab({
    super.key,
    required this.idInspeccion,
    required this.editable,
    this.segundaVisita = false,
    this.modoDirector = false,
    this.alCambiar,
  });

  @override
  State<ChecklistTab> createState() => _ChecklistTabState();
}

class _ChecklistTabState extends State<ChecklistTab> with AutomaticKeepAliveClientMixin {
  Map? _data;
  String? _error;
  String _filtro = 'TODOS';
  final _pendientes = <int, Map<String, dynamic>>{};
  Timer? _timer;
  bool _guardando = false;
  final _obs = <int, TextEditingController>{};
  final _medida = <int, TextEditingController>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Último intento al salir de la pantalla (sin tocar la interfaz)
    final lote = _pendientes.values.where((x) => !widget.segundaVisita || x['estado_segunda_visita'] != null).toList();
    if (lote.isNotEmpty) {
      Api.put('/inspecciones/${widget.idInspeccion}/${widget.segundaVisita ? 'segunda-visita' : 'resultados'}', lote)
          .catchError((_) => null);
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final d = await Api.get('/inspecciones/${widget.idInspeccion}/checklist');
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Map? _res(Map item) => item['resultado'];

  void _cambiar(Map item, Map<String, dynamic> cambios) {
    final id = item['id_item'] as int;
    item['resultado'] = {...?_res(item), ...cambios};
    if (widget.segundaVisita) {
      _pendientes[id] = {
        'id_item': id,
        'estado_segunda_visita': item['resultado']['estado_segunda_visita'],
        'observacion_segunda_visita': item['resultado']['observacion_segunda_visita'],
      };
    } else {
      final r = item['resultado'];
      _pendientes[id] = {
        'id_item': id,
        'resultado': r['resultado'] ?? 'NO_VERIFICADO',
        'valor_medido': r['valor_medido'],
        'unidad_medida': r['unidad_medida'],
        'observacion': r['observacion'],
      };
    }
    setState(() {});
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), _guardar);
  }

  Future<void> _guardar() async {
    if (_pendientes.isEmpty || _guardando) return;
    final lote = _pendientes.values.toList();
    if (widget.segundaVisita && lote.any((x) => x['estado_segunda_visita'] == null)) {
      lote.removeWhere((x) => x['estado_segunda_visita'] == null);
      if (lote.isEmpty) return;
    }
    _guardando = true;
    if (mounted) setState(() {});
    try {
      final path = widget.segundaVisita ? 'segunda-visita' : 'resultados';
      final r = await Api.put('/inspecciones/${widget.idInspeccion}/$path', lote);
      for (final x in lote) {
        if (identical(_pendientes[x['id_item']], x)) _pendientes.remove(x['id_item']);
      }
      if (_data != null) _data!['resumen'] = r['resumen'];
    } catch (e) {
      // Sin señal: se queda en pendientes y se reintenta
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 15), _guardar);
    }
    _guardando = false;
    if (mounted) setState(() {});
  }

  bool _visible(Map item) {
    final r = _res(item);
    if (widget.segundaVisita) return r?['resultado'] == 'NO_CUMPLE';
    switch (_filtro) {
      case 'PENDIENTES':
        return r == null || r['resultado'] == 'NO_VERIFICADO';
      case 'NO_CUMPLE':
        return r?['resultado'] == 'NO_CUMPLE';
      case 'MEDICION':
        return item['requiere_medicion'] == true && r?['resultado'] != 'NO_APLICA';
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_data == null) return Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!));
    final res = _data!['resumen'];
    final categorias = _data!['categorias'] as List;
    final total = categorias.fold<int>(0, (s, c) => s + (c['items'] as List).length);
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Text(
                widget.segundaVisita
                    ? 'Hallazgos: ${res['total_no_cumple']} · Corregidos ${res['corregidos']} · No corregidos ${res['no_corregidos']}'
                    : '${res['calificados']}/$total calificados · NC: L ${res['leves']} G ${res['graves']} MG ${res['muy_graves']} · NA ${res['no_aplica']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (_guardando)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else if (_pendientes.isNotEmpty)
              TextButton.icon(
                onPressed: _guardar,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text('Sin guardar (${_pendientes.length})'),
              )
            else
              const Icon(Icons.cloud_done_outlined, color: Colores.exito),
          ]),
          if (!widget.segundaVisita) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: total == 0 ? 0 : (res['calificados'] as int) / total),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (v, t) in const [
                  ('TODOS', 'Todos'),
                  ('PENDIENTES', 'Pendientes'),
                  ('NO_CUMPLE', 'No cumple'),
                  ('MEDICION', 'Con medición')
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(t), selected: _filtro == v, onSelected: (_) => setState(() => _filtro = v)),
                  ),
              ]),
            ),
          ],
        ]),
      ),
      Expanded(
        child: Contenido(
          ancho: 900,
          child: ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 80), children: [
            for (final c in categorias) _categoria(c),
          ]),
        ),
      ),
    ]);
  }

  Widget _categoria(Map c) {
    final items = (c['items'] as List).where((i) => _visible(i)).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final hechos = (c['items'] as List).where((i) => _res(i) != null && _res(i)!['resultado'] != 'NO_VERIFICADO').length;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: widget.segundaVisita || _filtro != 'TODOS',
        title: Text(c['nombre'], style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: widget.segundaVisita ? null : Text('$hechos de ${(c['items'] as List).length}'),
        children: [for (final i in items) _item(i)],
      ),
    );
  }

  Widget _item(Map it) {
    final r = _res(it);
    final resultado = r?['resultado'];
    final id = it['id_item'] as int;
    final e = widget.editable;
    _obs.putIfAbsent(id, () => TextEditingController(
        text: widget.segundaVisita ? (r?['observacion_segunda_visita'] ?? '') : (r?['observacion'] ?? '')));
    _medida.putIfAbsent(id, () => TextEditingController(text: r?['valor_medido'] ?? ''));
    final calif = it['calificacion_corta'];
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEFF2F5)))),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 34, child: Text('${it['numero']}', style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(child: Text(it['descripcion'])),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: _colorCalif[calif], borderRadius: BorderRadius.circular(6)),
            child: Text(calif, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (it['criterio_cumplimiento'] != null)
          Padding(
            padding: const EdgeInsets.only(left: 34, top: 2),
            child: Text(it['criterio_cumplimiento'], style: const TextStyle(fontSize: 12, color: Colores.alerta)),
          ),
        if (r?['no_aplica_automatico'] == true)
          const Padding(
            padding: EdgeInsets.only(left: 34, top: 2),
            child: Text('No aplica según las variantes del equipo', style: TextStyle(fontSize: 12, color: Colores.gris)),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: widget.segundaVisita ? _controlesSegunda(it, r, e) : _controles(it, r, resultado, e, id),
        ),
      ]),
    );
  }

  Widget _controles(Map it, Map? r, String? resultado, bool e, int id) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: 'CUMPLE', label: Text('Cumple')),
            ButtonSegment(value: 'NO_CUMPLE', label: Text('No cumple')),
            ButtonSegment(value: 'NO_APLICA', label: Text('N/A')),
          ],
          selected: {if (resultado != null && resultado != 'NO_VERIFICADO') resultado},
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((s) {
              if (!s.contains(WidgetState.selected)) return null;
              return {'CUMPLE': const Color(0xFFD4EDDA), 'NO_CUMPLE': const Color(0xFFF8D7DA), 'NO_APLICA': const Color(0xFFE2E8F0)}[resultado];
            }),
          ),
          onSelectionChanged: e ? (s) => _cambiar(it, {'resultado': s.isEmpty ? 'NO_VERIFICADO' : s.first}) : null,
        ),
        if (it['requiere_medicion'] == true && resultado != 'NO_APLICA')
          SizedBox(
            width: 150,
            child: TextField(
              controller: _medida[id],
              enabled: e,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Medida *', suffixText: it['unidad_medida'] ?? ''),
              onChanged: (v) => _cambiar(it, {'valor_medido': v, 'unidad_medida': it['unidad_medida']}),
            ),
          ),
        if (e || (it['fotos'] as List).isNotEmpty)
          TextButton.icon(
            onPressed: e
                ? () async {
                    final n = await agregarFotos(context, widget.idInspeccion, idItem: id);
                    if (n > 0) _cargarFotos(it);
                  }
                : null,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text('Foto (${(it['fotos'] as List).length})'),
          ),
      ]),
      if (resultado == 'NO_CUMPLE' && (it['fotos'] as List).isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Agregue al menos una foto de evidencia de esta no conformidad (va en el informe).',
              style: TextStyle(color: Colores.error, fontSize: 12)),
        ),
      if (resultado == 'NO_CUMPLE' || (_obs[id]!.text.isNotEmpty))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _obs[id],
            enabled: e,
            maxLines: null,
            decoration: const InputDecoration(labelText: 'Observación del hallazgo'),
            onChanged: (v) => _cambiar(it, {'observacion': v}),
          ),
        ),
      if ((it['fotos'] as List).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final f in it['fotos'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(Api.url(f['url_miniatura']), width: 64, height: 64, fit: BoxFit.cover),
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }

  Future<void> _cargarFotos(Map it) async {
    final d = await Api.get('/inspecciones/${widget.idInspeccion}/checklist');
    for (final c in d['categorias']) {
      for (final i in c['items']) {
        if (i['id_item'] == it['id_item'] && mounted) setState(() => it['fotos'] = i['fotos']);
      }
    }
  }

  Widget _controlesSegunda(Map it, Map? r, bool e) {
    final id = it['id_item'] as int;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (r?['observacion'] != null)
        Text('Hallazgo 1ª visita: ${r!['observacion']}', style: const TextStyle(fontSize: 12, color: Colores.gris)),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        showSelectedIcon: false,
        emptySelectionAllowed: true,
        segments: const [
          ButtonSegment(value: 'CORREGIDO', label: Text('Corregido'), icon: Icon(Icons.check)),
          ButtonSegment(value: 'NO_CORREGIDO', label: Text('No corregido'), icon: Icon(Icons.close)),
        ],
        selected: {if (r?['estado_segunda_visita'] != null) r!['estado_segunda_visita']},
        onSelectionChanged: e ? (s) => _cambiar(it, {'estado_segunda_visita': s.isEmpty ? null : s.first}) : null,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: _obs[id],
          enabled: e,
          decoration: const InputDecoration(labelText: 'Observación segunda visita'),
          onChanged: (v) => _cambiar(it, {'observacion_segunda_visita': v}),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (e)
            OutlinedButton.icon(
              onPressed: () async {
                final n = await agregarFotos(context, widget.idInspeccion, idItem: id, descripcion: 'Corrección 2ª visita');
                if (n > 0) _cargarFotos(it);
              },
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Foto de la corrección'),
            ),
          for (final f in it['fotos'])
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(Api.url(f['url_miniatura']), width: 64, height: 64, fit: BoxFit.cover),
            ),
        ]),
      ),
    ]);
  }
}
