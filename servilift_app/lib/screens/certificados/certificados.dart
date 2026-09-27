import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../../widgets/historial.dart';

/// Informes conformes que esperan certificado.
class CertificadosPendientesScreen extends StatelessWidget {
  const CertificadosPendientesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Cargador<List>(
      cargar: () async => await Api.get('/certificados/pendientes') as List,
      builder: (context, lista, recargar) {
        if (lista.isEmpty) return const Vacio('No hay certificados por elaborar', icono: Icons.workspace_premium_outlined);
        return Contenido(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: lista.length,
            itemBuilder: (_, i) {
              final inf = lista[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${inf['edificio']} · ${inf['servicio']['equipo']['identificacion']}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colores.navy)),
                    Text('${inf['cliente']} · ${inf['numero_cotizacion']}'),
                    Text('Informe ${inf['numero_informe']} · ${Estados.etiqueta(inf['concepto'])} · aprobado ${fecha(inf['fecha_aprobacion'])}',
                        style: const TextStyle(color: Colores.gris)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: () => ejecutar(context, () => Api.abrirPdf('/informes/${inf['id_informe']}/enlace-pdf')),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Ver informe'),
                      ),
                      BotonHistorial(inf['servicio']['id_cotizacion_equipo']),
                      FilledButton.icon(
                        onPressed: () async {
                          if (!await confirmar(context, 'Emitir certificado',
                              'Se genera el certificado con número consecutivo, vigencia y código QR de verificación.',
                              si: 'Emitir')) {
                            return;
                          }
                          if (!context.mounted) return;
                          dynamic cert;
                          if (await ejecutar(context, () async => cert = await Api.post('/certificados', {'id_informe': inf['id_informe']}),
                              exito: 'Certificado emitido')) {
                            if (context.mounted) {
                              await ejecutar(context, () => Api.abrirPdf('/certificados/${cert['id_certificado']}/enlace-pdf'));
                            }
                            recargar();
                          }
                        },
                        icon: const Icon(Icons.workspace_premium),
                        label: const Text('Elaborar certificado'),
                      ),
                    ]),
                  ]),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Certificados emitidos: enviar al cliente, ver PDF, anular.
class CertificadosScreen extends StatefulWidget {
  const CertificadosScreen({super.key});

  @override
  State<CertificadosScreen> createState() => _CertificadosScreenState();
}

class _CertificadosScreenState extends State<CertificadosScreen> {
  final _numero = TextEditingController();
  final _cargador = GlobalKey<CargadorState<List>>();

  @override
  Widget build(BuildContext context) {
    return Contenido(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _numero,
            onSubmitted: (_) => _cargador.currentState?.recargar(),
            decoration: const InputDecoration(labelText: 'Número de cotización', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Expanded(
          child: Cargador<List>(
            key: _cargador,
            cargar: () async => await Api.get('/certificados', query: {'numero_cotizacion': _numero.text.trim()}) as List,
            builder: (context, lista, recargar) {
              if (lista.isEmpty) return const Vacio('No hay certificados');
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final c = lista[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.workspace_premium, color: Colores.acento),
                      title: Text('${c['numero_certificado']} · ${c['edificio']} · ${c['servicio']['equipo']['identificacion']}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${c['cliente']} · ${c['numero_cotizacion']}\n'
                          'Emitido ${fecha(c['fecha_emision'])} · vence ${fecha(c['fecha_vencimiento'])}'),
                      isThreeLine: true,
                      trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        EstadoChip(c['estado']),
                        BotonHistorial(c['id_cotizacion_equipo'], compacto: true),
                        IconButton(
                          tooltip: 'Ver PDF',
                          icon: const Icon(Icons.picture_as_pdf),
                          onPressed: () => ejecutar(context, () => Api.abrirPdf('/certificados/${c['id_certificado']}/enlace-pdf')),
                        ),
                        if (c['estado'] == 'EMITIDO')
                          FilledButton(
                            onPressed: () async {
                              if (await confirmar(context, 'Enviar al cliente',
                                  'El cliente podrá ver y descargar el certificado ${c['numero_certificado']}.', si: 'Enviar')) {
                                if (context.mounted &&
                                    await ejecutar(context, () => Api.post('/certificados/${c['id_certificado']}/enviar'),
                                        exito: 'Certificado enviado al cliente')) {
                                  recargar();
                                }
                              }
                            },
                            child: const Text('Enviar'),
                          ),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
