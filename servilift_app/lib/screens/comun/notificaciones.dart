import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../certificados/certificados.dart';
import '../director/informes.dart';
import '../inspector/agenda.dart';
import '../inspector/inspeccion.dart';
import '../programacion/programacion.dart';
import 'cotizaciones.dart';

class NotificacionesScreen extends StatelessWidget {
  const NotificacionesScreen({super.key});

  /// Abre la pantalla a la que apunta la notificación (campo "enlace" del backend).
  static Future<void> abrir(BuildContext context, Map n) async {
    final enlace = '${n['enlace'] ?? ''}';
    final partes = enlace.split('/').where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return;
    final id = partes.length > 1 ? int.tryParse(partes[1]) : null;
    final rol = context.read<Sesion>().rol;

    Widget? pantalla;
    String titulo = n['titulo'] ?? '';
    switch (partes[0]) {
      case 'cotizaciones':
        if (id != null) pantalla = CotizacionDetalleScreen(id: id);
        break;
      case 'inspecciones':
        pantalla = id != null ? InspeccionScreen(id: id) : const AgendaScreen();
        titulo = 'Mi agenda';
        break;
      case 'informes':
        if (id == null) {
          pantalla = const InformesScreen(estado: 'PENDIENTE_REVISION');
          titulo = 'Informes por revisar';
        } else if (rol == Rol.director || rol == Rol.admin) {
          pantalla = RevisionScreen(idInforme: id);
        } else {
          // Cliente / certificados: abre el PDF del informe
          await ejecutar(context, () => Api.abrirPdf('/informes/$id/enlace-pdf'));
          return;
        }
        break;
      case 'programacion':
        pantalla = const PorProgramarScreen();
        titulo = 'Por programar';
        break;
      case 'certificados':
        if (id != null) {
          await ejecutar(context, () => Api.abrirPdf('/certificados/$id/enlace-pdf'));
          return;
        }
        pantalla = const CertificadosPendientesScreen();
        titulo = 'Certificados por elaborar';
        break;
    }
    if (pantalla == null || !context.mounted) return;
    // Las pantallas de detalle ya traen su propia barra; las de lista se envuelven en una
    final conBarra = pantalla is CotizacionDetalleScreen || pantalla is InspeccionScreen || pantalla is RevisionScreen;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => conBarra ? pantalla! : Scaffold(appBar: AppBar(title: Text(titulo)), body: pantalla),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: Cargador<List>(
        cargar: () async => await Api.get('/notificaciones') as List,
        builder: (context, lista, recargar) {
          if (lista.isEmpty) return const Vacio('No tiene notificaciones', icono: Icons.notifications_none);
          return Contenido(
            ancho: 800,
            child: RefreshIndicator(
              onRefresh: recargar,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final n = lista[i];
                  final leida = n['leida'] == true;
                  return Card(
                    child: ListTile(
                      leading: Icon(leida ? Icons.notifications_none : Icons.notifications_active,
                          color: leida ? Colores.gris : Colores.acento),
                      title: Text(n['titulo'], style: TextStyle(fontWeight: leida ? FontWeight.normal : FontWeight.w700)),
                      subtitle: Text('${n['mensaje']}\n${fechaHora(n['fecha_creacion'])}'),
                      isThreeLine: true,
                      trailing: n['enlace'] != null ? const Icon(Icons.chevron_right) : null,
                      onTap: () async {
                        if (!leida) {
                          try {
                            await Api.put('/notificaciones/${n['id_notificacion']}/leida');
                          } catch (_) {}
                        }
                        if (context.mounted) await abrir(context, n);
                        recargar();
                      },
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
