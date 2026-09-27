import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../asesor/clientes.dart' show tiposEquipo;
import 'checklist_tab.dart';
import 'firmas_tab.dart';
import 'fotos_tab.dart';
import '../../widgets/historial.dart';

/// Informe de inspección en el celular: datos precargados, variantes, checklist, fotos, firmas y finalizar.
class InspeccionScreen extends StatefulWidget {
  final int id;
  const InspeccionScreen({super.key, required this.id});

  @override
  State<InspeccionScreen> createState() => _InspeccionScreenState();
}

class _InspeccionScreenState extends State<InspeccionScreen> {
  Map? _insp;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final d = await Api.get('/inspecciones/${widget.id}');
      if (mounted) setState(() => _insp = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  bool get _segunda => _insp?['estado'] == 'EN_SEGUNDA_VISITA';

  bool _editable(Sesion s) =>
      s.rol == Rol.inspector && ['EN_CURSO', 'DEVUELTA', 'EN_SEGUNDA_VISITA'].contains(_insp?['estado']);

  Future<void> _finalizar() async {
    final val = await Api.get('/inspecciones/${widget.id}/validar');
    if (!mounted) return;
    if (val['puede_finalizar'] != true) {
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Faltan datos para finalizar'),
          content: SingleChildScrollView(child: Text((val['pendientes'] as List).map((p) => '• $p').join('\n'))),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
        ),
      );
      return;
    }
    if (!await confirmar(context, 'Finalizar ${_segunda ? 'segunda visita' : 'inspección'}',
        'El informe pasará al director técnico para su revisión y atestación. No podrá modificarlo después.',
        si: 'Finalizar')) {
      return;
    }
    if (!mounted) return;
    if (await ejecutar(context, () => Api.post('/inspecciones/${widget.id}/finalizar'),
        exito: 'Enviado al director técnico')) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<Sesion>();
    if (_insp == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inspección')),
        body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)),
      );
    }
    final i = _insp!;
    final editable = _editable(sesion);
    final equipo = i['datos_equipo']?['equipo'] ?? {};
    final edificio = i['datos_equipo']?['edificio'] ?? {};
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${edificio['nombre'] ?? ''} · ${equipo['identificacion'] ?? ''}', style: const TextStyle(fontSize: 17)),
            Text('${i['numero_inspeccion']} · ${Estados.etiqueta(i['estado'])}${_segunda ? '' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
          actions: [BotonHistorial(i['id_cotizacion_equipo'], compacto: true)],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.info_outline), text: 'Datos'),
              Tab(icon: Icon(Icons.checklist), text: 'Checklist'),
              Tab(icon: Icon(Icons.photo_library_outlined), text: 'Fotos'),
              Tab(icon: Icon(Icons.draw_outlined), text: 'Firmas'),
            ],
          ),
        ),
        body: Column(children: [
          if (i['estado'] == 'DEVUELTA' && i['informe']?['observaciones_revision'] != null)
            MaterialBanner(
              backgroundColor: const Color(0xFFFDECEA),
              leading: const Icon(Icons.undo, color: Colores.error),
              content: Text('Devuelto por el director: ${i['informe']['observaciones_revision']}'),
              actions: const [SizedBox.shrink()],
            ),
          if (_segunda)
            const MaterialBanner(
              backgroundColor: Color(0xFFFFF4E5),
              leading: Icon(Icons.fact_check, color: Colores.alerta),
              content: Text('Segunda visita: marque cada hallazgo como corregido o no corregido y recoja las firmas.'),
              actions: [SizedBox.shrink()],
            ),
          Expanded(
            child: TabBarView(children: [
              DatosTab(insp: i, editable: editable && !_segunda, alCambiar: _cargar),
              ChecklistTab(idInspeccion: widget.id, editable: editable, segundaVisita: _segunda, alCambiar: _cargar),
              FotosTab(idInspeccion: widget.id, editable: editable),
              FirmasTab(insp: i, editable: editable, alCambiar: _cargar),
            ]),
          ),
        ]),
        bottomNavigationBar: editable
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colores.exito),
                    onPressed: _finalizar,
                    icon: const Icon(Icons.send),
                    label: Text(_segunda ? 'Finalizar segunda visita' : 'Finalizar inspección'),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Datos del cliente/edificio/equipo (precargados), encabezado del informe, variantes e instrumentos.
class DatosTab extends StatefulWidget {
  final Map insp;
  final bool editable;
  final Future<void> Function() alCambiar;
  const DatosTab({super.key, required this.insp, required this.editable, required this.alCambiar});

  @override
  State<DatosTab> createState() => _DatosTabState();
}

class _DatosTabState extends State<DatosTab> with AutomaticKeepAliveClientMixin {
  List _variantes = [];
  List _instrumentos = [];
  late Map<int, int> _seleccion;
  late Set<int> _instrSel;
  final _c = <String, TextEditingController>{};
  String _conservacion = 'DIGITAL';

  static const _camposTexto = [
    ('tipo_acrilico', 'Tipo de acrílico de certificación', false),
    ('empresa_mantenimiento', 'Empresa de mantenimiento', false),
    ('tecnico_mantenimiento', 'Técnico de mantenimiento', false),
    ('fecha_ultimo_mantenimiento', 'Último mantenimiento', false),
    ('fecha_ultima_inspeccion', 'Última inspección', false),
  ];

  // Datos del ascensor que verifica el inspector (se guardan en el equipo y en el informe)
  static const _camposEquipo = [
    ('marca', 'Marca', false),
    ('modelo', 'Modelo', false),
    ('numero_serie', 'Identificación del equipo (serial)', false),
    ('anio_fabricacion', 'Año de fabricación', true),
    ('capacidad_kg', 'Capacidad (kg)', true),
    ('capacidad_personas', 'Capacidad (personas)', true),
    ('numero_paradas', 'Número de paradas', true),
    ('velocidad_ms', 'Velocidad (m/s)', true),
    ('recorrido_m', 'Recorrido (m)', true),
    ('profundidad_foso_mm', 'Profundidad de foso (mm)', true),
    ('fecha_puesta_marcha', 'Puesta en marcha', false),
  ];
  final _ce = <String, TextEditingController>{};
  String _tipoEquipo = 'ASCENSOR_PASAJEROS';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final i = widget.insp;
    _seleccion = {for (final v in i['variantes']) v['id_variante_tipo'] as int: v['id_variante_opcion'] as int};
    _instrSel = {for (final x in i['instrumentos']) x['id_instrumento'] as int};
    _conservacion = i['conservacion_informacion'] ?? 'DIGITAL';
    for (final (k, _, _) in _camposTexto) {
      _c[k] = TextEditingController(text: i[k] == null ? '' : (k.startsWith('fecha_') ? CampoFecha.mostrar(i[k]) : '${i[k]}'));
    }
    _c['observaciones_generales'] = TextEditingController(text: i['observaciones_generales'] ?? '');
    final eq = (i['datos_equipo']?['equipo'] ?? {}) as Map;
    for (final (k, _, _) in _camposEquipo) {
      _ce[k] = TextEditingController(text: eq[k] == null ? '' : (k.startsWith('fecha_') ? CampoFecha.mostrar(eq[k]) : '${eq[k]}'));
    }
    _tipoEquipo = eq['tipo_equipo'] ?? 'ASCENSOR_PASAJEROS';
    Api.get('/catalogos/variantes').then((v) => mounted ? setState(() => _variantes = v) : null);
    Api.get('/instrumentos').then((v) => mounted ? setState(() => _instrumentos = v) : null);
  }

  Future<void> _guardarVariantes() async {
    final faltan = _variantes.where((t) => t['obligatoria'] == true && !_seleccion.containsKey(t['id_variante_tipo']));
    await ejecutar(context, () async {
      await Api.put('/inspecciones/${widget.insp['id_inspeccion']}/variantes', [
        for (final e in _seleccion.entries) {'id_variante_tipo': e.key, 'id_variante_opcion': e.value}
      ]);
      await widget.alCambiar();
    }, exito: faltan.isEmpty ? 'Variantes guardadas: el checklist se ajustó' : 'Guardado. Faltan ${faltan.length} variantes');
  }

  Future<void> _guardarEquipo() async {
    try {
      await _guardarEquipoValidado();
    } on FormatException catch (e) {
      if (mounted) mensaje(context, e.message, error: true);
    }
  }

  Future<void> _guardarEquipoValidado() async {
    final body = <String, dynamic>{'tipo_equipo': _tipoEquipo};
    for (final (k, _, numero) in _camposEquipo) {
      final t = _ce[k]!.text.trim().replaceAll(',', '.');
      if (k.startsWith('fecha_')) {
        body[k] = CampoFecha.fechaParaApi(_ce[k]!.text);
        continue;
      }
      body[k] = t.isEmpty || t.toUpperCase() == 'NI' ? null : (numero ? num.tryParse(t) : t);
      if (numero && t.isNotEmpty && body[k] == null) {
        throw FormatException('Revise el valor numérico de "$k"');
      }
    }
    await ejecutar(context, () async {
      await Api.put('/inspecciones/${widget.insp['id_inspeccion']}/equipo', body);
      await widget.alCambiar();
    }, exito: 'Datos del ascensor guardados');
  }

  Future<void> _guardarEncabezado() async {
    try {
      await _guardarEncabezadoValidado();
    } on FormatException catch (e) {
      if (mounted) mensaje(context, e.message, error: true);
    }
  }

  Future<void> _guardarEncabezadoValidado() async {
    final body = <String, dynamic>{'conservacion_informacion': _conservacion};
    for (final (k, _, numero) in _camposTexto) {
      final t = _c[k]!.text.trim();
      if (k.startsWith('fecha_')) {
        body[k] = CampoFecha.fechaParaApi(t);
        continue;
      }
      body[k] = t.isEmpty ? null : (numero ? num.tryParse(t) : t);
    }
    body['observaciones_generales'] = _c['observaciones_generales']!.text.trim();
    await ejecutar(context, () async {
      await Api.put('/inspecciones/${widget.insp['id_inspeccion']}/encabezado', body);
      await Api.put('/inspecciones/${widget.insp['id_inspeccion']}/instrumentos', _instrSel.toList());
    }, exito: 'Datos del informe guardados');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = widget.insp['datos_equipo'] ?? {};
    final cli = d['cliente'] ?? {}, ed = d['edificio'] ?? {}, eq = d['equipo'] ?? {};
    final e = widget.editable;
    final r = widget.insp['resumen'];
    return Contenido(
      ancho: 900,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Dato('Cotización', '${d['numero_cotizacion']} · ${d['codigo_servicio']}'),
              Dato('Cliente', '${cli['razon_social']} (${cli['tipo_documento']} ${cli['numero_documento']})'),
              Dato('Edificio', '${ed['nombre']} · ${ed['direccion']}, ${ed['ciudad']}'),
              Dato('Equipo', [eq['identificacion'], eq['marca'], eq['modelo']].where((x) => x != null).join(' · ')),
              Dato('Serial', eq['numero_serie']),
              Dato('Avance', '${r['calificados']} ítems calificados · ${r['total_no_cumple']} no cumple · ${r['no_aplica']} no aplica'),
            ]),
          ),
        ),
        Titulo('Datos del ascensor',
            accion: e ? FilledButton.tonal(onPressed: _guardarEquipo, child: const Text('Guardar ascensor')) : null),
        const Text('Los verifica el inspector en sitio; quedan en el equipo y en el informe.',
            style: TextStyle(color: Colores.gris, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: _tipoEquipo,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo de equipo'),
              items: [for (final t in tiposEquipo) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
              onChanged: e ? (v) => _tipoEquipo = v! : null,
            ),
          ),
          for (final (k, etiqueta, numero) in _camposEquipo)
            SizedBox(
              width: 260,
              child: k.startsWith('fecha_')
                  ? CampoFecha(controller: _ce[k]!, etiqueta: etiqueta, habilitado: e)
                  : TextField(
                      controller: _ce[k],
                      enabled: e,
                      keyboardType: numero ? const TextInputType.numberWithOptions(decimal: true) : null,
                      decoration: InputDecoration(
                          labelText: etiqueta, hintText: 'NI', floatingLabelBehavior: FloatingLabelBehavior.always),
                    ),
            ),
        ]),
        Titulo('Variantes del equipo',
            accion: e ? FilledButton.tonal(onPressed: _guardarVariantes, child: const Text('Guardar variantes')) : null),
        const Text('Según las variantes, los ítems que no aplican se marcan solos como "No aplica".',
            style: TextStyle(color: Colores.gris, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final t in _variantes)
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int>(
                initialValue: _seleccion[t['id_variante_tipo']],
                isExpanded: true,
                decoration: InputDecoration(labelText: t['nombre'] + (t['obligatoria'] == true ? ' *' : '')),
                items: [
                  for (final o in t['opciones'])
                    DropdownMenuItem(value: o['id_variante_opcion'] as int, child: Text(o['nombre'])),
                ],
                onChanged: e ? (v) => setState(() => _seleccion[t['id_variante_tipo']] = v!) : null,
              ),
            ),
        ]),
        Titulo('Datos del informe',
            accion: e ? FilledButton.tonal(onPressed: _guardarEncabezado, child: const Text('Guardar datos')) : null),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: _conservacion,
              decoration: const InputDecoration(labelText: 'Conservación de la información'),
              items: const [
                DropdownMenuItem(value: 'DIGITAL', child: Text('Digital')),
                DropdownMenuItem(value: 'FISICO', child: Text('Físico')),
              ],
              onChanged: e ? (v) => _conservacion = v! : null,
            ),
          ),
          for (final (k, etiqueta, numero) in _camposTexto)
            SizedBox(
              width: 260,
              child: k.startsWith('fecha_')
                  ? CampoFecha(controller: _c[k]!, etiqueta: etiqueta, habilitado: e)
                  : TextField(
                      controller: _c[k],
                      enabled: e,
                      keyboardType: numero ? const TextInputType.numberWithOptions(decimal: true) : null,
                      decoration: InputDecoration(
                          labelText: etiqueta, hintText: 'NI', floatingLabelBehavior: FloatingLabelBehavior.always),
                    ),
            ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _c['observaciones_generales'],
          enabled: e,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Observaciones generales'),
        ),
        const Titulo('Equipos de medición utilizados'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in _instrumentos)
            FilterChip(
              label: Text('${x['tipo'].toString().replaceAll('_', ' ').toLowerCase()} ${x['codigo']}'),
              selected: _instrSel.contains(x['id_instrumento']),
              onSelected: e
                  ? (v) => setState(() => v ? _instrSel.add(x['id_instrumento']) : _instrSel.remove(x['id_instrumento']))
                  : null,
            ),
          if (_instrumentos.isEmpty) const Text('No hay instrumentos registrados', style: TextStyle(color: Colores.gris)),
        ]),
        const SizedBox(height: 80),
      ]),
    );
  }
}
