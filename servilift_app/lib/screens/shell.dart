import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/tema.dart';
import '../widgets/formulario.dart';
import 'admin/parametros.dart';
import 'admin/usuarios.dart';
import 'asesor/clientes.dart';
import 'certificados/certificados.dart';
import 'comun/cotizaciones.dart';
import 'comun/inicio.dart';
import 'comun/notificaciones.dart';
import 'comun/seguimiento.dart';
import 'director/informes.dart';
import 'inspector/agenda.dart';
import 'programacion/programacion.dart';

class _Seccion {
  final String titulo;
  final IconData icono;
  final Widget Function() pantalla;
  const _Seccion(this.titulo, this.icono, this.pantalla);
}

/// Estructura principal: menú lateral en PC, cajón en celular. Las secciones dependen del rol.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _indice = 0;
  int _noLeidas = 0;
  Timer? _timer;

  List<_Seccion> _secciones(Sesion s) {
    final seguimiento = _Seccion('Seguimiento', Icons.manage_search, () => const SeguimientoScreen());
    final cotizaciones = _Seccion('Cotizaciones', Icons.request_quote_outlined, () => const CotizacionesScreen());
    return [_Seccion('Inicio', Icons.dashboard_outlined, () => const InicioScreen()), ..._seccionesRol(s, seguimiento, cotizaciones)];
  }

  List<_Seccion> _seccionesRol(Sesion s, _Seccion seguimiento, _Seccion cotizaciones) {
    switch (s.rol) {
      case Rol.asesor:
        return [
          seguimiento,
          _Seccion('Clientes', Icons.apartment, () => const ClientesScreen()),
          cotizaciones,
        ];
      case Rol.cliente:
        return [
          _Seccion('Mis equipos', Icons.elevator_outlined, () => const SeguimientoScreen()),
          cotizaciones,
        ];
      case Rol.programacion:
        return [
          _Seccion('Por programar', Icons.event_available, () => const PorProgramarScreen()),
          _Seccion('Calendario', Icons.calendar_month, () => const CalendarioScreen()),
          seguimiento,
        ];
      case Rol.inspector:
        return [_Seccion('Mi agenda', Icons.assignment_outlined, () => const AgendaScreen()), seguimiento];
      case Rol.director:
        return [
          _Seccion('Informes por revisar', Icons.fact_check_outlined, () => const InformesScreen(estado: 'PENDIENTE_REVISION')),
          _Seccion('Informes aprobados', Icons.task_outlined, () => const InformesScreen(estado: 'APROBADO')),
          seguimiento,
        ];
      case Rol.certificados:
        return [
          _Seccion('Por elaborar', Icons.pending_actions, () => const CertificadosPendientesScreen()),
          _Seccion('Certificados', Icons.workspace_premium_outlined, () => const CertificadosScreen()),
          seguimiento,
        ];
      default: // ADMIN
        return [
          _Seccion('Usuarios', Icons.manage_accounts_outlined, () => const UsuariosScreen()),
          _Seccion('Parámetros', Icons.tune, () => const ParametrosScreen()),
          seguimiento,
          _Seccion('Clientes', Icons.apartment, () => const ClientesScreen()),
          cotizaciones,
          _Seccion('Por programar', Icons.event_available, () => const PorProgramarScreen()),
          _Seccion('Calendario', Icons.calendar_month, () => const CalendarioScreen()),
          _Seccion('Informes por revisar', Icons.fact_check_outlined, () => const InformesScreen(estado: 'PENDIENTE_REVISION')),
          _Seccion('Certificados por elaborar', Icons.pending_actions, () => const CertificadosPendientesScreen()),
          _Seccion('Certificados', Icons.workspace_premium_outlined, () => const CertificadosScreen()),
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    _contarNotificaciones();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _contarNotificaciones());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _contarNotificaciones() async {
    try {
      final lista = await Api.get('/notificaciones', query: {'solo_no_leidas': 'true'}) as List;
      if (mounted) setState(() => _noLeidas = lista.length);
    } catch (_) {}
  }

  Future<void> _abrirNotificaciones() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificacionesScreen()));
    _contarNotificaciones();
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<Sesion>();
    final secciones = _secciones(sesion);
    if (_indice >= secciones.length) _indice = 0;
    final ancho = MediaQuery.sizeOf(context).width >= 900;

    final menu = ListView(children: [
      DrawerHeader(
        decoration: const BoxDecoration(color: Colores.navy),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
          const Text('ServiLift', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(sesion.nombre, style: const TextStyle(color: Colors.white)),
          Text(sesion.usuario?['rol_nombre'] ?? sesion.rol, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
      for (var i = 0; i < secciones.length; i++)
        ListTile(
          leading: Icon(secciones[i].icono),
          title: Text(secciones[i].titulo),
          selected: i == _indice,
          onTap: () {
            setState(() => _indice = i);
            if (!ancho) Navigator.pop(context);
          },
        ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.key_outlined),
        title: const Text('Cambiar contraseña'),
        onTap: () async {
          if (!ancho) Navigator.pop(context);
          await formularioDialogo(context,
              titulo: 'Cambiar contraseña',
              campos: const [
                Campo('actual', 'Contraseña actual', obligatorio: true, oculto: true),
                Campo('nueva', 'Nueva contraseña (mín. 6)', obligatorio: true, oculto: true),
              ],
              guardar: (d) => Api.post('/auth/cambiar-contrasena', d));
        },
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Cerrar sesión'),
        onTap: () => context.read<Sesion>().cerrar(),
      ),
    ]);

    final cuerpo = KeyedSubtree(key: ValueKey(_indice), child: secciones[_indice].pantalla());

    return Scaffold(
      appBar: AppBar(
        title: Text(secciones[_indice].titulo),
        automaticallyImplyLeading: !ancho,
        actions: [
          IconButton(
            tooltip: 'Notificaciones',
            onPressed: _abrirNotificaciones,
            icon: Badge(isLabelVisible: _noLeidas > 0, label: Text('$_noLeidas'), child: const Icon(Icons.notifications_outlined)),
          ),
        ],
      ),
      drawer: ancho ? null : Drawer(child: menu),
      body: ancho
          ? Row(children: [
              SizedBox(width: 260, child: Material(color: Colors.white, child: menu)),
              const VerticalDivider(width: 1),
              Expanded(child: cuerpo),
            ])
          : cuerpo,
    );
  }
}
