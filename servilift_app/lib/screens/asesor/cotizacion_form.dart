import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';

const tiposServicio = [
  ('INSPECCION_PERIODICA', 'Inspección periódica'),
  ('INSPECCION_INICIAL', 'Inspección inicial'),
  ('REINSPECCION', 'Reinspección'),
  ('EXTRAORDINARIA', 'Extraordinaria'),
];

/// Crear o editar (borrador) una cotización: un edificio y sus equipos elegidos uno a uno con valor.
class CotizacionFormScreen extends StatefulWidget {
  final int? idEdificio;
  final Map? cotizacion;
  const CotizacionFormScreen({super.key, this.idEdificio, this.cotizacion});

  @override
  State<CotizacionFormScreen> createState() => _CotizacionFormScreenState();
}

class _Linea {
  bool incluido = false;
  final valor = TextEditingController();
  String tipo = 'INSPECCION_PERIODICA';
  final descripcion = TextEditingController();
}

class _CotizacionFormScreenState extends State<CotizacionFormScreen> {
  List _clientes = [];
  List _edificios = [];
  int? _idCliente;
  int? _idEdificio;
  final _lineas = <int, _Linea>{};
  final _iva = TextEditingController(text: '19');
  final _validez = TextEditingController(text: '30');
  final _valorTodos = TextEditingController();
  final _observaciones = TextEditingController();
  bool _cargando = true;
  bool _guardando = false;

  bool get _editando => widget.cotizacion != null;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      _clientes = await Api.get('/clientes') as List;
      final c = widget.cotizacion;
      if (c != null) {
        _idCliente = c['id_cliente'];
        _iva.text = '${c['iva_porcentaje']}';
        _validez.text = '${c['dias_validez']}';
        _observaciones.text = c['observaciones'] ?? '';
        await _cargarEdificios(c['id_edificio']);
        for (final e in c['equipos']) {
          final l = _lineas[e['id_equipo']];
          if (l == null) continue;
          l.incluido = true;
          l.valor.text = '${(num.tryParse('${e['valor']}') ?? 0).round()}';
          l.tipo = e['tipo_servicio'];
          l.descripcion.text = e['descripcion'] ?? '';
        }
      } else if (widget.idEdificio != null) {
        final ed = await Api.get('/edificios/${widget.idEdificio}');
        _idCliente = ed['id_cliente'];
        await _cargarEdificios(widget.idEdificio);
      }
    } catch (e) {
      if (mounted) mensaje(context, '$e', error: true);
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarEdificios(int? seleccionar) async {
    _edificios = _idCliente == null ? [] : await Api.get('/clientes/$_idCliente/edificios') as List;
    _seleccionarEdificio(seleccionar ?? (_edificios.length == 1 ? _edificios.first['id_edificio'] : null));
  }

  void _seleccionarEdificio(int? id) {
    _idEdificio = id;
    _lineas.clear();
    final ed = _edificios.where((e) => e['id_edificio'] == id).firstOrNull;
    for (final q in (ed?['equipos'] as List? ?? [])) {
      _lineas[q['id_equipo']] = _Linea();
    }
  }

  List get _equipos => (_edificios.where((e) => e['id_edificio'] == _idEdificio).firstOrNull?['equipos'] as List?) ?? [];

  double get _subtotal => _lineas.values
      .where((l) => l.incluido)
      .fold(0.0, (s, l) => s + (double.tryParse(l.valor.text.replaceAll('.', '').replaceAll(',', '')) ?? 0));

  Future<void> _guardar() async {
    final seleccion = _lineas.entries.where((e) => e.value.incluido).toList();
    if (_idEdificio == null || seleccion.isEmpty) {
      mensaje(context, 'Seleccione el edificio y al menos un equipo', error: true);
      return;
    }
    for (final s in seleccion) {
      if (double.tryParse(s.value.valor.text.replaceAll('.', '').replaceAll(',', '')) == null) {
        mensaje(context, 'Ingrese el valor de cada equipo seleccionado', error: true);
        return;
      }
    }
    final body = {
      'id_edificio': _idEdificio,
      'dias_validez': int.tryParse(_validez.text) ?? 30,
      'iva_porcentaje': double.tryParse(_iva.text) ?? 19,
      'observaciones': _observaciones.text.trim().isEmpty ? null : _observaciones.text.trim(),
      'equipos': [
        for (final s in seleccion)
          {
            'id_equipo': s.key,
            'valor': double.parse(s.value.valor.text.replaceAll('.', '').replaceAll(',', '')),
            'tipo_servicio': s.value.tipo,
            'descripcion': s.value.descripcion.text.trim().isEmpty ? null : s.value.descripcion.text.trim(),
          }
      ],
    };
    setState(() => _guardando = true);
    dynamic r;
    final ok = await ejecutar(context, () async {
      r = _editando
          ? await Api.put('/cotizaciones/${widget.cotizacion!['id_cotizacion']}', body)
          : await Api.post('/cotizaciones', body);
    }, exito: _editando ? 'Cotización actualizada' : 'Cotización creada');
    if (mounted) setState(() => _guardando = false);
    if (ok && mounted) Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final iva = (double.tryParse(_iva.text) ?? 0) / 100;
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar ${widget.cotizacion!['numero_cotizacion']}' : 'Nueva cotización')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Contenido(
              ancho: 900,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                DropdownButtonFormField<int>(
                  initialValue: _idCliente,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cliente'),
                  items: [
                    for (final c in _clientes)
                      DropdownMenuItem(value: c['id_cliente'] as int, child: Text('${c['razon_social']} (${c['numero_documento']})')),
                  ],
                  onChanged: _editando
                      ? null
                      : (v) async {
                          _idCliente = v;
                          await _cargarEdificios(null);
                          setState(() {});
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('ed$_idCliente'),
                  initialValue: _idEdificio,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Edificio'),
                  items: [
                    for (final e in _edificios)
                      DropdownMenuItem(value: e['id_edificio'] as int, child: Text('${e['nombre']} · ${e['direccion']}')),
                  ],
                  onChanged: _editando ? null : (v) => setState(() => _seleccionarEdificio(v)),
                ),
                Titulo('Equipos a certificar (${_lineas.values.where((l) => l.incluido).length} de ${_equipos.length})',
                    accion: SizedBox(
                      width: 230,
                      child: TextField(
                        controller: _valorTodos,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Mismo valor a todos',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.done_all),
                            onPressed: () => setState(() {
                              for (final l in _lineas.values) {
                                l.incluido = true;
                                l.valor.text = _valorTodos.text;
                              }
                            }),
                          ),
                        ),
                      ),
                    )),
                if (_equipos.isEmpty) const Vacio('El edificio no tiene equipos registrados'),
                for (final q in _equipos) _lineaEquipo(q),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _iva,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'IVA %'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _validez,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Validez (días)'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(controller: _observaciones, maxLines: 3, decoration: const InputDecoration(labelText: 'Observaciones')),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      _fila('Subtotal', moneda(_subtotal)),
                      _fila('IVA', moneda(_subtotal * iva)),
                      _fila('Total', moneda(_subtotal * (1 + iva)), fuerte: true),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: const Icon(Icons.save),
                  label: Text(_editando ? 'Guardar cambios' : 'Crear cotización'),
                ),
              ]),
            ),
    );
  }

  Widget _lineaEquipo(Map q) {
    final l = _lineas[q['id_equipo']]!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
          SizedBox(
            width: 250,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: l.incluido,
              onChanged: (v) => setState(() => l.incluido = v ?? false),
              title: Text(q['identificacion'], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([q['marca'], q['numero_serie']].where((x) => x != null).join(' · ')),
            ),
          ),
          if (l.incluido) ...[
            SizedBox(
              width: 160,
              child: TextField(
                controller: l.valor,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Valor', prefixText: '\$ '),
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String>(
                initialValue: l.tipo,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Servicio'),
                items: [for (final t in tiposServicio) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
                onChanged: (v) => l.tipo = v ?? l.tipo,
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _fila(String a, String b, {bool fuerte = false}) {
    final st = TextStyle(fontSize: fuerte ? 18 : 14, fontWeight: fuerte ? FontWeight.w800 : FontWeight.normal,
        color: fuerte ? Colores.navy : null);
    return Row(children: [Expanded(child: Text(a, style: st)), Text(b, style: st)]);
  }
}
