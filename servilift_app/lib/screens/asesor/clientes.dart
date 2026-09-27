import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../../widgets/formulario.dart';
import '../comun/cotizaciones.dart';
import 'cotizacion_form.dart';

const camposCliente = [
  Campo(
    'tipo_documento',
    'Tipo de documento',
    obligatorio: true,
    inicial: 'NIT',
    opciones: [('NIT', 'NIT'), ('CC', 'Cédula'), ('CE', 'Cédula de extranjería')],
  ),
  Campo('numero_documento', 'Número de documento', obligatorio: true),
  Campo('razon_social', 'Nombre o razón social', obligatorio: true),
  Campo(
    'tipo_cliente',
    'Tipo de cliente',
    obligatorio: true,
    inicial: 'PROPIEDAD_HORIZONTAL',
    opciones: [
      ('PROPIEDAD_HORIZONTAL', 'Propiedad horizontal'),
      ('EMPRESA', 'Empresa'),
      ('PERSONA_NATURAL', 'Persona natural'),
      ('ENTIDAD_PUBLICA', 'Entidad pública'),
    ],
  ),
  Campo('contacto_nombre', 'Nombre del contacto'),
  Campo('contacto_cargo', 'Cargo del contacto'),
  Campo('contacto_correo', 'Correo del contacto'),
  Campo('contacto_telefono', 'Teléfono del contacto'),
  Campo('direccion', 'Dirección'),
  Campo('ciudad', 'Ciudad'),
];

const camposEdificio = [
  Campo('nombre', 'Nombre del edificio / torre', obligatorio: true),
  Campo('direccion', 'Dirección', obligatorio: true),
  Campo('ciudad', 'Ciudad', obligatorio: true),
  Campo('barrio', 'Barrio'),
  Campo('numero_pisos', 'Número de pisos', numero: true),
  Campo('numero_equipos', 'Número de ascensores', numero: true, obligatorio: true),
  Campo('administrador_nombre', 'Representante / administrador'),
  Campo('administrador_telefono', 'Teléfono del representante'),
  Campo('administrador_correo', 'Correo del representante'),
  Campo('empresa_mantenimiento', 'Empresa de mantenimiento'),
];

// El asesor solo registra el ascensor; los datos técnicos los completa el inspector en la visita.
const camposEquipo = [
  Campo('identificacion', 'Identificación (ej. Ascensor 1, Torre B)', obligatorio: true),
  Campo('tipo_equipo', 'Tipo de equipo', obligatorio: true, inicial: 'ASCENSOR_PASAJEROS', opciones: tiposEquipo),
];

const tiposEquipo = [
  ('ASCENSOR_PASAJEROS', 'Ascensor de pasajeros'),
  ('ASCENSOR_CARGA', 'Ascensor de carga'),
  ('MONTACARGAS', 'Montacargas'),
  ('MONTACAMILLAS', 'Montacamillas'),
  ('ASCENSOR_VEHICULAR', 'Ascensor vehicular'),
  ('OTRO', 'Otro'),
];

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  final _buscar = TextEditingController();
  final _cargador = GlobalKey<CargadorState<List>>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final nuevo = await formularioDialogo(
            context,
            titulo: 'Nuevo cliente',
            campos: camposCliente,
            guardar: (d) => Api.post('/clientes', d),
          );
          if (nuevo is Map && context.mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ClienteDetalleScreen(id: nuevo['id_cliente'])),
            );
          }
          _cargador.currentState?.recargar();
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nuevo cliente'),
      ),
      body: Contenido(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                controller: _buscar,
                onSubmitted: (_) => _cargador.currentState?.recargar(),
                decoration: const InputDecoration(labelText: 'Buscar por nombre o NIT', prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: Cargador<List>(
                key: _cargador,
                cargar: () async => await Api.get('/clientes', query: {'buscar': _buscar.text.trim()}) as List,
                builder: (context, lista, recargar) {
                  if (lista.isEmpty) return const Vacio('No hay clientes registrados');
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: lista.length,
                    itemBuilder: (_, i) {
                      final c = lista[i];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.apartment)),
                          title: Text(c['razon_social'], style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${c['tipo_documento']} ${c['numero_documento']} · ${c['ciudad'] ?? ''}'
                            '\nAsesor: ${c['asesor'] ?? '-'}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ClienteDetalleScreen(id: c['id_cliente'])),
                            );
                            recargar();
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClienteDetalleScreen extends StatelessWidget {
  final int id;
  const ClienteDetalleScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cliente')),
      body: Cargador<Map>(
        cargar: () async => await Api.get('/clientes/$id') as Map,
        builder: (context, c, recargar) {
          final edificios = c['edificios'] as List;
          final esAdmin = context.read<Sesion>().rol == Rol.admin;
          final usuarios = c['usuarios'] as List;
          return Contenido(
            ancho: 1000,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c['razon_social'],
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colores.navy),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final ok = await formularioDialogo(
                                  context,
                                  titulo: 'Editar cliente',
                                  campos: camposCliente,
                                  valores: Map<String, dynamic>.from(c),
                                  guardar: (d) => Api.put('/clientes/$id', d),
                                );
                                if (ok != null) recargar();
                              },
                            ),
                          ],
                        ),
                        Dato('Documento', '${c['tipo_documento']} ${c['numero_documento']}'),
                        Dato(
                          'Contacto',
                          [
                            c['contacto_nombre'],
                            c['contacto_cargo'],
                            c['contacto_telefono'],
                            c['contacto_correo'],
                          ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                        ),
                        Dato('Dirección', '${c['direccion'] ?? ''} ${c['ciudad'] ?? ''}'),
                        Dato('Asesor', c['asesor']),
                      ],
                    ),
                  ),
                ),
                Titulo(
                  'Acceso al portal del cliente',
                  accion: !esAdmin
                      ? null
                      : TextButton.icon(
                          icon: const Icon(Icons.person_add),
                          label: const Text('Crear usuario'),
                          onPressed: () async {
                            final ok = await formularioDialogo(
                              context,
                              titulo: 'Usuario del portal',
                              campos: const [
                                Campo('nombre_completo', 'Nombre completo', obligatorio: true),
                                Campo('correo', 'Correo', obligatorio: true),
                                Campo('contrasena', 'Contraseña inicial (mín. 6)', obligatorio: true, oculto: true),
                                Campo('cargo', 'Cargo'),
                                Campo('telefono', 'Teléfono'),
                              ],
                              guardar: (d) => Api.post('/clientes/$id/usuarios', d),
                            );
                            if (ok != null) recargar();
                          },
                        ),
                ),
                if (usuarios.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline, color: Colores.alerta),
                      title: Text('Sin usuarios. El administrador debe crear uno para poder enviarle cotizaciones.'),
                    ),
                  ),
                for (final u in usuarios)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(u['nombre_completo']),
                      subtitle: Text(u['correo']),
                    ),
                  ),
                Titulo(
                  'Edificios',
                  accion: TextButton.icon(
                    icon: const Icon(Icons.add_business),
                    label: const Text('Agregar edificio'),
                    onPressed: () async {
                      final nuevo = await formularioDialogo(
                        context,
                        titulo: 'Nuevo edificio',
                        campos: camposEdificio,
                        guardar: (d) => Api.post('/clientes/$id/edificios', d),
                      );
                      if (nuevo is Map && (nuevo['numero_equipos'] ?? 0) > 0 && context.mounted) {
                        if (await confirmar(
                          context,
                          'Registrar ascensores',
                          '¿Crear ${nuevo['numero_equipos']} ascensores (Ascensor 1, 2, ...) para completar sus datos después?',
                          si: 'Crear',
                        )) {
                          if (context.mounted) {
                            await ejecutar(
                              context,
                              () => Api.post('/edificios/${nuevo['id_edificio']}/equipos/generar'),
                            );
                          }
                        }
                      }
                      recargar();
                    },
                  ),
                ),
                if (edificios.isEmpty) const Vacio('Agregue el primer edificio del cliente', icono: Icons.apartment),
                for (final e in edificios) _Edificio(e: e, recargar: recargar),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Edificio extends StatelessWidget {
  final Map e;
  final Future<void> Function() recargar;
  const _Edificio({required this.e, required this.recargar});

  @override
  Widget build(BuildContext context) {
    final equipos = e['equipos'] as List;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.apartment, color: Colores.acento),
        title: Text(e['nombre'], style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${e['direccion']}, ${e['ciudad']} · ${equipos.length} de ${e['numero_equipos']} ascensores registrados',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final q in equipos)
            ListTile(
              dense: true,
              leading: const Icon(Icons.elevator_outlined),
              title: Text(q['identificacion']),
              subtitle: Text(
                [
                  q['marca'],
                  q['numero_serie'],
                  if (q['capacidad_kg'] != null) '${q['capacidad_kg']} kg',
                  if (q['numero_paradas'] != null) '${q['numero_paradas']} paradas',
                ].where((x) => x != null).join(' · '),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () async {
                  final ok = await formularioDialogo(
                    context,
                    titulo: 'Editar ${q['identificacion']}',
                    campos: camposEquipo,
                    valores: Map<String, dynamic>.from(q),
                    guardar: (d) => Api.put('/equipos/${q['id_equipo']}', d),
                  );
                  if (ok != null) recargar();
                },
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Agregar ascensor'),
                onPressed: () async {
                  final ok = await formularioDialogo(
                    context,
                    titulo: 'Nuevo ascensor en ${e['nombre']}',
                    campos: camposEquipo,
                    guardar: (d) => Api.post('/edificios/${e['id_edificio']}/equipos', d),
                  );
                  if (ok != null) recargar();
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_location_alt),
                label: const Text('Editar edificio'),
                onPressed: () async {
                  final ok = await formularioDialogo(
                    context,
                    titulo: 'Editar edificio',
                    campos: camposEdificio,
                    valores: Map<String, dynamic>.from(e),
                    guardar: (d) => Api.put('/edificios/${e['id_edificio']}', d),
                  );
                  if (ok != null) recargar();
                },
              ),
              if (equipos.isNotEmpty)
                FilledButton.icon(
                  icon: const Icon(Icons.request_quote),
                  label: const Text('Nueva cotización'),
                  onPressed: () async {
                    final cot = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => CotizacionFormScreen(idEdificio: e['id_edificio'])),
                    );
                    if (cot is Map && context.mounted) {
                      // Abre la cotización recién creada para enviarla al cliente
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => CotizacionDetalleScreen(id: cot['id_cotizacion'])),
                      );
                    }
                    recargar();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
