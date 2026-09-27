import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../../widgets/formulario.dart';

const roles = [
  ('ADMIN', 'Administrador'),
  ('ASESOR', 'Asesor'),
  ('PROGRAMACION', 'Programación'),
  ('INSPECTOR', 'Inspector'),
  ('DIRECTOR_TECNICO', 'Director técnico'),
  ('CERTIFICADOS', 'Certificados'),
  ('CLIENTE', 'Cliente'),
];

/// Gestión de usuarios: solo el administrador crea usuarios, cambia roles y restablece contraseñas.
class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  final _cargador = GlobalKey<CargadorState<List>>();

  Future<List<(String, String)>> _clientes() async {
    final l = await Api.get('/clientes') as List;
    return [for (final c in l) ('${c['id_cliente']}', '${c['razon_social']} (${c['numero_documento']})')];
  }

  Future<void> _crear() async {
    final clientes = await _clientes();
    if (!mounted) return;
    final ok = await formularioDialogo(context,
        titulo: 'Nuevo usuario',
        campos: [
          const Campo('rol', 'Rol', obligatorio: true, opciones: roles),
          const Campo('nombre_completo', 'Nombre completo', obligatorio: true),
          const Campo('correo', 'Correo', obligatorio: true),
          const Campo('contrasena', 'Contraseña (mín. 6)', obligatorio: true, oculto: true),
          Campo('id_cliente', 'Cliente (solo para rol Cliente)', opciones: clientes),
          const Campo('documento', 'Documento'),
          const Campo('telefono', 'Teléfono'),
          const Campo('cargo', 'Cargo'),
          const Campo('matricula_profesional', 'Matrícula profesional'),
        ],
        guardar: (d) {
          if (d['id_cliente'] != null) d['id_cliente'] = int.parse(d['id_cliente']);
          return Api.post('/usuarios', d);
        });
    if (ok != null) _cargador.currentState?.recargar();
  }

  Future<void> _editar(Map u) async {
    final clientes = await _clientes();
    if (!mounted) return;
    final valores = Map<String, dynamic>.from(u)..['id_cliente'] = u['id_cliente']?.toString();
    final ok = await formularioDialogo(context,
        titulo: 'Editar ${u['correo']}',
        valores: valores,
        campos: [
          const Campo('rol', 'Rol', obligatorio: true, opciones: roles),
          const Campo('nombre_completo', 'Nombre completo', obligatorio: true),
          Campo('id_cliente', 'Cliente (solo para rol Cliente)', opciones: clientes),
          const Campo('estado', 'Estado', obligatorio: true, opciones: [('ACTIVO', 'Activo'), ('INACTIVO', 'Inactivo')]),
          const Campo('telefono', 'Teléfono'),
          const Campo('cargo', 'Cargo'),
          const Campo('matricula_profesional', 'Matrícula profesional'),
          const Campo('contrasena', 'Nueva contraseña (dejar vacío para no cambiarla)', oculto: true),
        ],
        guardar: (d) {
          if (d['id_cliente'] != null) d['id_cliente'] = int.parse(d['id_cliente']);
          if (d['contrasena'] == null) d.remove('contrasena');
          return Api.put('/usuarios/${u['id_usuario']}', d);
        });
    if (ok != null) _cargador.currentState?.recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crear,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo usuario'),
      ),
      body: Cargador<List>(
        key: _cargador,
        cargar: () async => await Api.get('/usuarios') as List,
        builder: (context, lista, recargar) => Contenido(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: lista.length,
            itemBuilder: (_, i) {
              final u = lista[i];
              final activo = u['estado'] == 'ACTIVO';
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text((u['nombre_completo'] as String).substring(0, 1))),
                  title: Text(u['nombre_completo'], style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${u['correo']} · ${u['rol_nombre']}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!activo) const EstadoChip('ANULADO', texto: 'Inactivo'),
                    IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: () => _editar(u)),
                  ]),
                  tileColor: activo ? null : Colores.superficie,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
