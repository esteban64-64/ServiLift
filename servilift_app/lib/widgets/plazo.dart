import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/tema.dart';
import 'comunes.dart';

/// Plazo para corregir los hallazgos y hacer la segunda visita, con los días que quedan.
class PlazoCorreccion extends StatelessWidget {
  final Map datos; // plazo_dias, fecha_limite_correccion, dias_restantes
  const PlazoCorreccion(this.datos, {super.key});

  @override
  Widget build(BuildContext context) {
    final dias = datos['dias_restantes'];
    if (dias == null) return const SizedBox.shrink();
    final vencido = dias < 0;
    final color = vencido || dias <= 3 ? Colores.error : (dias <= 10 ? Colores.alerta : Colores.info);
    final inmediata = datos['plazo_dias'] == 0;
    final texto = inmediata
        ? 'Corrección inmediata (hallazgos muy graves)'
        : vencido
            ? 'Plazo vencido hace ${-dias} días (límite ${fecha(datos['fecha_limite_correccion'])})'
            : 'Plazo ${datos['plazo_dias']} días · vence ${fecha(datos['fecha_limite_correccion'])} · quedan $dias días';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(texto, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Botón "Solicitar segunda visita" (cliente o asesor) cuando el equipo quedó no conforme.
class BotonSolicitarSegundaVisita extends StatelessWidget {
  final int idCotizacionEquipo;
  final String estado;
  final VoidCallback? alSolicitar;
  const BotonSolicitarSegundaVisita(
      {super.key, required this.idCotizacionEquipo, required this.estado, this.alSolicitar});

  @override
  Widget build(BuildContext context) {
    final rol = context.read<Sesion>().rol;
    if (estado != 'NO_CONFORME' || !(rol == Rol.cliente || rol == Rol.asesor || rol == Rol.admin)) {
      return const SizedBox.shrink();
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: Colores.alerta),
      onPressed: () async {
        final comentario = await pedirTexto(context, 'Solicitar segunda visita',
            etiqueta: 'Comentario (ej. hallazgos corregidos el 10/10)', obligatorio: false);
        if (comentario == null || !context.mounted) return;
        if (await ejecutar(
            context,
            () => Api.post('/seguimiento/equipo/$idCotizacionEquipo/solicitar-segunda-visita',
                {'comentario': comentario.isEmpty ? null : comentario}),
            exito: 'Segunda visita solicitada. Programación fue notificada.')) {
          if (alSolicitar != null) {
            alSolicitar!();
          } else if (context.mounted) {
            context.findAncestorStateOfType<CargadorState<List>>()?.recargar();
            context.findAncestorStateOfType<CargadorState<Map>>()?.recargar();
          }
        }
      },
      icon: const Icon(Icons.event_repeat),
      label: const Text('Solicitar segunda visita'),
    );
  }
}
