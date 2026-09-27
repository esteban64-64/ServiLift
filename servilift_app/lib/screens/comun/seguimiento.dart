import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../../widgets/historial.dart';
import '../../widgets/plazo.dart';

/// Estado por equipo, filtrable por número de cotización. Para el cliente es "Mis equipos".
class SeguimientoScreen extends StatefulWidget {
  const SeguimientoScreen({super.key});

  @override
  State<SeguimientoScreen> createState() => _SeguimientoScreenState();
}

class _SeguimientoScreenState extends State<SeguimientoScreen> {
  final _numero = TextEditingController();
  String? _estado;
  final _cargador = GlobalKey<CargadorState<List>>();

  Future<List> _cargar() async =>
      await Api.get('/seguimiento', query: {'numero_cotizacion': _numero.text.trim(), 'estado': _estado}) as List;

  void _buscar() => _cargador.currentState?.recargar();

  @override
  Widget build(BuildContext context) {
    final esCliente = context.read<Sesion>().rol == Rol.cliente;
    return Contenido(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _numero,
                onSubmitted: (_) => _buscar(),
                decoration: InputDecoration(
                  labelText: 'Número de cotización',
                  hintText: 'COT-2026-0001',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _buscar),
                ),
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String?>(
                initialValue: _estado,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Estado del equipo'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  for (final e in const [
                    'PENDIENTE_APROBACION', 'APROBADO_CLIENTE', 'POR_PROGRAMAR', 'PROGRAMADO', 'EN_INSPECCION',
                    'EN_REVISION', 'NO_CONFORME', 'SEGUNDA_VISITA_SOLICITADA', 'INFORME_APROBADO', 'CERTIFICADO_LISTO', 'RECHAZADO', 'ANULADO'
                  ])
                    DropdownMenuItem(value: e, child: Text(Estados.etiqueta(e))),
                ],
                onChanged: (v) {
                  _estado = v;
                  _buscar();
                },
              ),
            ),
          ]),
        ),
        Expanded(
          child: Cargador<List>(
            key: _cargador,
            cargar: _cargar,
            builder: (context, filas, recargar) {
              if (filas.isEmpty) {
                return Vacio(esCliente ? 'Aún no tiene equipos en proceso' : 'No hay resultados');
              }
              // Agrupar por cotización
              final grupos = <String, List>{};
              for (final f in filas) {
                grupos.putIfAbsent(f['numero_cotizacion'], () => []).add(f);
              }
              return RefreshIndicator(
                onRefresh: recargar,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final g in grupos.entries) _GrupoCotizacion(numero: g.key, filas: g.value),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _GrupoCotizacion extends StatelessWidget {
  final String numero;
  final List filas;
  const _GrupoCotizacion({required this.numero, required this.filas});

  @override
  Widget build(BuildContext context) {
    final f0 = filas.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(numero, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colores.navy)),
            const SizedBox(width: 10),
            Expanded(child: Text('${f0['cliente']} · ${f0['edificio']}', overflow: TextOverflow.ellipsis)),
          ]),
          const Divider(),
          for (final f in filas) _FilaEquipo(f),
        ]),
      ),
    );
  }
}

class _FilaEquipo extends StatelessWidget {
  final Map f;
  const _FilaEquipo(this.f);

  @override
  Widget build(BuildContext context) {
    final prog = f['fecha_programada'] != null
        ? '${f['tipo_visita'] == 'SEGUNDA' ? '2ª visita' : 'Visita'} ${fecha(f['fecha_programada'])} ${hora(f['hora_inicio'])}'
            '${f['inspector'] != null ? ' · ${f['inspector']}' : ''}'
        : null;
    return InkWell(
      onTap: () => mostrarHistorial(context, f['id_cotizacion_equipo']),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 260,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${f['equipo']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${f['codigo_servicio']}', style: const TextStyle(fontSize: 12, color: Colores.gris)),
              if (prog != null) Text(prog, style: const TextStyle(fontSize: 12, color: Colores.gris)),
            ]),
          ),
          EstadoChip(f['estado_equipo'], texto: f['estado_etiqueta']),
          PlazoCorreccion(f),
          BotonSolicitarSegundaVisita(idCotizacionEquipo: f['id_cotizacion_equipo'], estado: f['estado_equipo']),
          if (f['informe_visita1'] == true)
            OutlinedButton.icon(
              onPressed: () => ejecutar(context, () => Api.abrirPdf('/informes/${f['id_informe']}/enlace-pdf?visita=1')),
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Informe 1ª visita'),
            ),
          if (f['informe_visita2'] == true)
            OutlinedButton.icon(
              onPressed: () => ejecutar(context, () => Api.abrirPdf('/informes/${f['id_informe']}/enlace-pdf?visita=2')),
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Informe 2ª visita'),
            ),
          if (f['pdf_certificado'] != null)
            FilledButton.icon(
              onPressed: () => ejecutar(context, () => Api.abrirPdf('/certificados/${f['id_certificado']}/enlace-pdf')),
              icon: const Icon(Icons.workspace_premium, size: 18),
              label: Text('Certificado ${f['numero_certificado'] ?? ''}'),
            ),
        ]),
      ),
    );
  }
}
