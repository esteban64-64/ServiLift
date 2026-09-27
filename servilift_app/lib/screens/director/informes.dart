import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../inspector/checklist_tab.dart';
import '../inspector/fotos_tab.dart';
import '../../widgets/historial.dart';

/// Bandeja del director técnico.
class InformesScreen extends StatelessWidget {
  final String estado;
  const InformesScreen({super.key, required this.estado});

  @override
  Widget build(BuildContext context) {
    return Cargador<List>(
      cargar: () async => await Api.get('/informes', query: {'estado': estado}) as List,
      builder: (context, lista, recargar) {
        if (lista.isEmpty) {
          return Vacio(estado == 'PENDIENTE_REVISION' ? 'No hay informes por revisar' : 'No hay informes aprobados',
              icono: Icons.fact_check_outlined);
        }
        return Contenido(
          child: RefreshIndicator(
            onRefresh: recargar,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: lista.length,
              itemBuilder: (_, i) {
                final inf = lista[i];
                final r = inf['resumen_actual'];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: inf['visita_actual'] == 2 ? Colores.alerta : Colores.acento,
                      child: Text('${inf['visita_actual']}ª', style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text('${inf['numero_informe']} · ${inf['edificio']} · ${inf['servicio']['equipo']['identificacion']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${inf['cliente']} · ${inf['numero_cotizacion']} · Inspector: ${inf['inspector']}\n'
                        'No cumple: L ${r['leves']} · G ${r['graves']} · MG ${r['muy_graves']} · '
                        '${inf['total_fotos']} fotos${inf['concepto'] != null ? ' · ${Estados.etiqueta(inf['concepto'])}' : ''}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => RevisionScreen(idInforme: inf['id_informe'])));
                      recargar();
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Revisión y atestación: resumen, checklist, fotos; devolver o aprobar con firma (genera el PDF).
class RevisionScreen extends StatefulWidget {
  final int idInforme;
  const RevisionScreen({super.key, required this.idInforme});

  @override
  State<RevisionScreen> createState() => _RevisionScreenState();
}

class _RevisionScreenState extends State<RevisionScreen> {
  Map? _inf;
  Map? _insp;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final inf = await Api.get('/informes/${widget.idInforme}');
    final insp = await Api.get('/inspecciones/${inf['id_inspeccion']}');
    if (mounted) {
      setState(() {
        _inf = inf;
        _insp = insp;
      });
    }
  }

  bool get _pendiente => _inf?['estado'] == 'PENDIENTE_REVISION';

  Future<void> _devolver() async {
    final obs = await pedirTexto(context, 'Devolver al inspector', etiqueta: 'Qué debe corregir');
    if (obs == null || !mounted) return;
    if (await ejecutar(context, () => Api.post('/informes/${widget.idInforme}/devolver', {'observaciones': obs}),
        exito: 'Informe devuelto al inspector')) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _aprobar() async {
    final params = await Api.get('/catalogos/parametros');
    if (!mounted) return;
    final r = _inf!['resumen_actual'];
    final segunda = _inf!['visita_actual'] == 2;
    final pendientes = segunda ? r['total_no_cumple'] - r['corregidos'] : r['total_no_cumple'];
    String concepto = pendientes == 0 ? 'CONFORME' : 'NO_CONFORME';
    final atestacion = TextEditingController(text: params['TEXTO_ATESTACION'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Aprobar y firmar informe'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(segunda
                    ? 'Segunda visita: ${r['corregidos']} corregidos, ${r['no_corregidos']} no corregidos.'
                    : 'Hallazgos: ${r['leves']} leves, ${r['graves']} graves, ${r['muy_graves']} muy graves.'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: concepto,
                  decoration: const InputDecoration(labelText: 'Concepto'),
                  items: const [
                    DropdownMenuItem(value: 'CONFORME', child: Text('Conforme')),
                    DropdownMenuItem(value: 'NO_CONFORME', child: Text('No conforme')),
                  ],
                  onChanged: (v) => setState(() => concepto = v!),
                ),
                const SizedBox(height: 6),
                Text(
                  concepto == 'CONFORME'
                      ? 'Pasa a Certificados para emitir el certificado.'
                      : 'El certificado queda bloqueado: Programación agenda la segunda visita.',
                  style: TextStyle(color: concepto == 'CONFORME' ? Colores.exito : Colores.error, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(controller: atestacion, maxLines: 6, decoration: const InputDecoration(labelText: 'Atestación')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.draw), label: const Text('Firmar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final firma = await capturarFirma(context, 'Firma del director técnico');
    if (firma == null || !mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Generando PDF...')])),
    );
    final aprobado = await ejecutar(
        context,
        () => Api.post('/informes/${widget.idInforme}/aprobar',
            {'concepto': concepto, 'atestacion': atestacion.text.trim(), 'firma_base64': firma}),
        exito: 'Informe aprobado. Ya está disponible para el cliente.');
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (aprobado && mounted) {
      await ejecutar(context, () => Api.abrirPdf('/informes/${widget.idInforme}/enlace-pdf'));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_inf == null || _insp == null) {
      return Scaffold(appBar: AppBar(title: const Text('Revisión')), body: const Center(child: CircularProgressIndicator()));
    }
    final inf = _inf!, insp = _insp!;
    final segunda = inf['visita_actual'] == 2;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${inf['numero_informe']} · ${inf['servicio']['equipo']['identificacion']}'),
          actions: [
            BotonHistorial(inf['servicio']['id_cotizacion_equipo'], compacto: true),
            if (inf['tiene_pdf_visita1'] == true)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('1ª visita'),
                onPressed: () => ejecutar(context, () => Api.abrirPdf('/informes/${widget.idInforme}/enlace-pdf?visita=1')),
              ),
            if (inf['tiene_pdf_visita2'] == true)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('2ª visita'),
                onPressed: () => ejecutar(context, () => Api.abrirPdf('/informes/${widget.idInforme}/enlace-pdf?visita=2')),
              ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Resumen'), Tab(text: 'Checklist'), Tab(text: 'Fotos')],
          ),
        ),
        body: TabBarView(children: [
          _Resumen(inf: inf, insp: insp),
          ChecklistTab(
            idInspeccion: insp['id_inspeccion'],
            editable: _pendiente,
            segundaVisita: segunda && _pendiente,
            modoDirector: true,
          ),
          FotosTab(idInspeccion: insp['id_inspeccion'], editable: _pendiente, modoDirector: _pendiente),
        ]),
        bottomNavigationBar: _pendiente
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(onPressed: _devolver, icon: const Icon(Icons.undo), label: const Text('Devolver')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colores.exito),
                        onPressed: _aprobar,
                        icon: const Icon(Icons.verified),
                        label: const Text('Aprobar, firmar y generar PDF'),
                      ),
                    ),
                  ]),
                ),
              )
            : null,
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  final Map inf, insp;
  const _Resumen({required this.inf, required this.insp});

  @override
  Widget build(BuildContext context) {
    final d = insp['datos_equipo'] ?? {};
    final r = inf['resumen_actual'];
    return Contenido(
      ancho: 900,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(inf['numero_informe'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                EstadoChip(inf['estado']),
              ]),
              const SizedBox(height: 6),
              Dato('Cotización', '${d['numero_cotizacion']} · ${d['codigo_servicio']}'),
              Dato('Cliente', d['cliente']?['razon_social']),
              Dato('Edificio', '${d['edificio']?['nombre']} · ${d['edificio']?['direccion']}'),
              Dato('Equipo', '${d['equipo']?['identificacion']} · serial ${d['equipo']?['numero_serie'] ?? 'NI'}'),
              Dato('Inspector', '${insp['inspector']} · ${fechaHora(insp['fecha_inicio'])}'),
              if (insp['fecha_visita2'] != null) Dato('Segunda visita', fechaHora(insp['fecha_visita2'])),
              if (inf['concepto_visita1'] != null) Dato('Concepto 1ª visita', Estados.etiqueta(inf['concepto_visita1'])),
              if (inf['concepto'] != null) Dato('Concepto', Estados.etiqueta(inf['concepto'])),
            ]),
          ),
        ),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (inf['estado'] != 'APROBADO')
            FilledButton.icon(
              onPressed: () => ejecutar(context, () => Api.abrirPdf('/informes/${inf['id_informe']}/vista-previa')),
              icon: const Icon(Icons.picture_as_pdf),
              label: Text('Ver informe ${inf['visita_actual'] == 2 ? '2ª' : '1ª'} visita (borrador)'),
            ),
          if (inf['tiene_pdf_visita1'] == true)
            OutlinedButton.icon(
              onPressed: () => ejecutar(context, () => Api.abrirPdf('/informes/${inf['id_informe']}/enlace-pdf?visita=1')),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Informe 1ª visita'),
            ),
          if (inf['tiene_pdf_visita2'] == true)
            OutlinedButton.icon(
              onPressed: () => ejecutar(context, () => Api.abrirPdf('/informes/${inf['id_informe']}/enlace-pdf?visita=2')),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Informe 2ª visita'),
            ),
          OutlinedButton.icon(
            onPressed: () => DefaultTabController.of(context).animateTo(2),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text('Ver las ${inf['total_fotos']} fotos'),
          ),
          OutlinedButton.icon(
            onPressed: () => DefaultTabController.of(context).animateTo(1),
            icon: const Icon(Icons.checklist),
            label: const Text('Ver checklist completo'),
          ),
        ]),
        const Titulo('Resumen de hallazgos'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Cifra('Leves', r['leves'], const Color(0xFF2F6FB0)),
          _Cifra('Graves', r['graves'], Colores.alerta),
          _Cifra('Muy graves', r['muy_graves'], Colores.error),
          _Cifra('No aplica', r['no_aplica'], Colores.gris),
          _Cifra('Fotos', inf['total_fotos'], Colores.navy),
          if (inf['visita_actual'] == 2) ...[
            _Cifra('Corregidos', r['corregidos'], Colores.exito),
            _Cifra('No corregidos', r['no_corregidos'], Colores.error),
          ],
        ]),
        const Titulo('Hallazgos (No cumple)'),
        _Hallazgos(idInspeccion: insp['id_inspeccion']),
        const Titulo('Variantes del equipo'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in insp['variantes']) Chip(label: Text('${v['tipo']}: ${v['opcion']}')),
        ]),
        if ((insp['mediciones'] as List).isNotEmpty) ...[
          const Titulo('Mediciones'),
          for (final m in insp['mediciones']) Dato(m['concepto'], '${m['valor']} ${m['unidad'] ?? ''} ${m['resultado'] ?? ''}'),
        ],
        if (insp['observaciones_generales'] != null && '${insp['observaciones_generales']}'.isNotEmpty) ...[
          const Titulo('Observaciones del inspector'),
          Text(insp['observaciones_generales']),
        ],
        const Titulo('Firmas'),
        for (final f in insp['firmas'])
          ListTile(
            dense: true,
            leading: Text('${f['numero_visita']}ª'),
            title: Text('${Estados.etiqueta(f['tipo_firmante'])}: ${f['nombre']}'),
            trailing: Image.network(Api.url(f['url']), height: 36, errorBuilder: (_, _, _) => const SizedBox()),
          ),
        const SizedBox(height: 80),
      ]),
    );
  }
}

class _Cifra extends StatelessWidget {
  final String etiqueta;
  final dynamic valor;
  final Color color;
  const _Cifra(this.etiqueta, this.valor, this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text('$valor', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          Text(etiqueta, style: TextStyle(color: color)),
        ]),
      );
}


/// Ítems NO CUMPLE con su calificación, observación, medida y fotos, para revisarlos de un vistazo.
class _Hallazgos extends StatelessWidget {
  final int idInspeccion;
  const _Hallazgos({required this.idInspeccion});

  @override
  Widget build(BuildContext context) {
    return Cargador<Map>(
      intervalo: null,
      cargar: () async => await Api.get('/inspecciones/$idInspeccion/checklist') as Map,
      builder: (context, d, _) {
        final items = [
          for (final c in d['categorias'])
            for (final i in c['items'])
              if (i['resultado']?['resultado'] == 'NO_CUMPLE') i
        ];
        if (items.isEmpty) {
          return const Card(child: ListTile(leading: Icon(Icons.check_circle, color: Colores.exito), title: Text('Sin hallazgos')));
        }
        return Column(children: [
          for (final i in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 36, child: Text('${i['numero']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                    Expanded(child: Text(i['descripcion'])),
                    const SizedBox(width: 8),
                    EstadoChip('NO_CONFORME', texto: i['calificacion_corta']),
                  ]),
                  if (i['resultado']['observacion'] != null && '${i['resultado']['observacion']}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 36, top: 4),
                      child: Text('Observación: ${i['resultado']['observacion']}', style: const TextStyle(color: Colores.gris)),
                    ),
                  if (i['resultado']['valor_medido'] != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 36, top: 2),
                      child: Text('Medida: ${i['resultado']['valor_medido']} ${i['resultado']['unidad_medida'] ?? ''}',
                          style: const TextStyle(color: Colores.gris)),
                    ),
                  if (i['resultado']['estado_segunda_visita'] != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 36, top: 2),
                      child: Text('2ª visita: ${Estados.etiqueta(i['resultado']['estado_segunda_visita'])}'),
                    ),
                  if ((i['fotos'] as List).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 36, top: 8),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final f in i['fotos'])
                          InkWell(
                            onTap: () => showDialog(
                              context: context,
                              builder: (c) => Dialog(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Flexible(child: InteractiveViewer(child: Image.network(Api.url(f['url'])))),
                                  if (f['descripcion'] != null) Padding(padding: const EdgeInsets.all(8), child: Text(f['descripcion'])),
                                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar')),
                                ]),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(Api.url(f['url_miniatura']), width: 90, height: 90, fit: BoxFit.cover),
                            ),
                          ),
                      ]),
                    ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
