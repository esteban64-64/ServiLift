import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../asesor/cotizacion_form.dart';
import '../../widgets/historial.dart';
import '../../widgets/plazo.dart';

class CotizacionesScreen extends StatefulWidget {
  const CotizacionesScreen({super.key});

  @override
  State<CotizacionesScreen> createState() => _CotizacionesScreenState();
}

class _CotizacionesScreenState extends State<CotizacionesScreen> {
  final _numero = TextEditingController();
  String? _estado;
  final _cargador = GlobalKey<CargadorState<List>>();

  @override
  Widget build(BuildContext context) {
    final sesion = context.read<Sesion>();
    final esAsesor = sesion.es(Rol.asesor);
    return Scaffold(
      floatingActionButton: esAsesor
          ? FloatingActionButton.extended(
              onPressed: () async {
                final creada = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CotizacionFormScreen()));
                if (creada is Map && context.mounted) {
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => CotizacionDetalleScreen(id: creada['id_cotizacion'])));
                }
                _cargador.currentState?.recargar();
              },
              icon: const Icon(Icons.add),
              label: const Text('Nueva cotización'),
            )
          : null,
      body: Contenido(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _numero,
                  onSubmitted: (_) => _cargador.currentState?.recargar(),
                  decoration: const InputDecoration(labelText: 'Buscar por número', prefixIcon: Icon(Icons.search)),
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String?>(
                  initialValue: _estado,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    for (final e in [
                      if (esAsesor) 'BORRADOR', 'ENVIADA_CLIENTE', 'APROBADA_CLIENTE', 'RECHAZADA_CLIENTE',
                      'ENVIADA_PROGRAMACION', 'EN_EJECUCION', 'FINALIZADA', 'ANULADA'
                    ])
                      DropdownMenuItem(value: e, child: Text(Estados.etiqueta(e))),
                  ],
                  onChanged: (v) {
                    _estado = v;
                    _cargador.currentState?.recargar();
                  },
                ),
              ),
            ]),
          ),
          Expanded(
            child: Cargador<List>(
              key: _cargador,
              cargar: () async =>
                  await Api.get('/cotizaciones', query: {'numero': _numero.text.trim(), 'estado': _estado}) as List,
              builder: (context, lista, recargar) {
                if (lista.isEmpty) return const Vacio('No hay cotizaciones');
                return RefreshIndicator(
                  onRefresh: recargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: lista.length,
                    itemBuilder: (_, i) {
                      final c = lista[i];
                      return Card(
                        child: ListTile(
                          title: Text('${c['numero_cotizacion']} · ${c['edificio']}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${c['cliente']}\n${c['cantidad_equipos']} equipos · ${moneda(c['total'])} · '
                              '${fecha(c['fecha_cotizacion'])}'),
                          isThreeLine: true,
                          trailing: EstadoChip(c['estado']),
                          onTap: () async {
                            await Navigator.push(context,
                                MaterialPageRoute(builder: (_) => CotizacionDetalleScreen(id: c['id_cotizacion'])));
                            recargar();
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class CotizacionDetalleScreen extends StatelessWidget {
  final int id;
  const CotizacionDetalleScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final sesion = context.read<Sesion>();
    return Scaffold(
      appBar: AppBar(title: const Text('Cotización')),
      body: Cargador<Map>(
        cargar: () async => await Api.get('/cotizaciones/$id') as Map,
        builder: (context, c, recargar) {
          final estado = c['estado'];
          Future<void> accion(String path, String exito, [Object? body]) async {
            if (await ejecutar(context, () => Api.post('/cotizaciones/$id/$path', body), exito: exito)) recargar();
          }

          final acciones = <Widget>[
            if (sesion.es(Rol.asesor) && estado == 'BORRADOR') ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => CotizacionFormScreen(cotizacion: c)));
                  if (r != null) recargar();
                },
                icon: const Icon(Icons.edit),
                label: const Text('Editar'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (await confirmar(context, 'Enviar al cliente',
                      'La cotización ${c['numero_cotizacion']} quedará visible en el portal del cliente para su aprobación.')) {
                    accion('enviar-cliente', 'Cotización enviada al cliente');
                  }
                },
                icon: const Icon(Icons.send),
                label: const Text('Enviar al cliente'),
              ),
            ],
            if (sesion.rol == Rol.cliente && estado == 'ENVIADA_CLIENTE') ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colores.exito),
                onPressed: () async {
                  if (await confirmar(context, 'Aprobar cotización', '¿Aprueba la cotización por ${moneda(c['total'])}?',
                      si: 'Aprobar')) {
                    accion('responder', 'Cotización aprobada', {'aprobada': true});
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Aprobar'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final motivo = await pedirTexto(context, 'Rechazar cotización', etiqueta: 'Motivo');
                  if (motivo != null) accion('responder', 'Cotización rechazada', {'aprobada': false, 'comentario': motivo});
                },
                icon: const Icon(Icons.close),
                label: const Text('Rechazar'),
              ),
            ],
            if (sesion.es(Rol.asesor) && estado == 'APROBADA_CLIENTE')
              FilledButton.icon(
                onPressed: () async {
                  if (await confirmar(context, 'Enviar a programación',
                      'Acepta la aprobación del cliente y envía los equipos a programación.')) {
                    accion('enviar-programacion', 'Enviada a programación');
                  }
                },
                icon: const Icon(Icons.event),
                label: const Text('Aceptar y enviar a programación'),
              ),
            if (sesion.es(Rol.asesor) && ['BORRADOR', 'ENVIADA_CLIENTE', 'APROBADA_CLIENTE'].contains(estado))
              TextButton.icon(
                onPressed: () async {
                  final motivo = await pedirTexto(context, 'Anular cotización', etiqueta: 'Motivo');
                  if (motivo != null) accion('anular', 'Cotización anulada', {'motivo': motivo});
                },
                icon: const Icon(Icons.block, color: Colores.error),
                label: const Text('Anular', style: TextStyle(color: Colores.error)),
              ),
          ];

          return Contenido(
            ancho: 900,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(c['numero_cotizacion'],
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colores.navy)),
                      ),
                      EstadoChip(estado),
                    ]),
                    const SizedBox(height: 8),
                    Dato('Cliente', c['cliente']),
                    Dato('Edificio', '${c['edificio']} · ${c['edificio_detalle']?['direccion'] ?? ''}, ${c['edificio_detalle']?['ciudad'] ?? ''}'),
                    Dato('Asesor', c['asesor']),
                    Dato('Fecha', '${fecha(c['fecha_cotizacion'])} · válida ${c['dias_validez']} días'),
                    if (c['comentario_cliente'] != null) Dato('Comentario del cliente', c['comentario_cliente']),
                    if (c['observaciones'] != null) Dato('Observaciones', c['observaciones']),
                  ]),
                ),
              ),
              const Titulo('Equipos cotizados'),
              for (final e in c['equipos'])
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.elevator_outlined),
                    onTap: () => mostrarHistorial(context, e['id_cotizacion_equipo']),
                    title: Text('${e['equipo']['identificacion']} · ${e['codigo_servicio']}'),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${Estados.etiqueta(e['tipo_servicio']).toLowerCase()}'
                          '${e['descripcion'] != null ? ' · ${e['descripcion']}' : ''}'),
                      if (e['dias_restantes'] != null) ...[const SizedBox(height: 4), PlazoCorreccion(e)],
                      if (e['estado'] == 'NO_CONFORME') ...[
                        const SizedBox(height: 6),
                        BotonSolicitarSegundaVisita(idCotizacionEquipo: e['id_cotizacion_equipo'], estado: e['estado']),
                      ],
                    ]),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(moneda(e['valor']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      EstadoChip(e['estado'], texto: e['estado_etiqueta']),
                    ]),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _Total('Subtotal', moneda(c['subtotal'])),
                    _Total('IVA ${c['iva_porcentaje']}%', moneda(c['iva_valor'])),
                    _Total('Total', moneda(c['total']), fuerte: true),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: acciones),
            ]),
          );
        },
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final String etiqueta, valor;
  final bool fuerte;
  const _Total(this.etiqueta, this.valor, {this.fuerte = false});

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(fontSize: fuerte ? 18 : 14, fontWeight: fuerte ? FontWeight.w800 : FontWeight.normal);
    return Row(children: [Expanded(child: Text(etiqueta, style: estilo)), Text(valor, style: estilo)]);
  }
}
