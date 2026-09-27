import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';

/// Firmas del inspector, del técnico de mantenimiento y del representante del edificio (por visita).
class FirmasTab extends StatelessWidget {
  final Map insp;
  final bool editable;
  final Future<void> Function() alCambiar;
  const FirmasTab({super.key, required this.insp, required this.editable, required this.alCambiar});

  static const _tipos = [
    ('INSPECTOR', 'Inspector', Icons.engineering),
    ('TECNICO_MANTENIMIENTO', 'Técnico de mantenimiento', Icons.build_outlined),
    ('REPRESENTANTE_EDIFICIO', 'Representante del edificio', Icons.apartment),
  ];

  Future<void> _firmar(BuildContext context, String tipo, String titulo, int visita) async {
    final sesion = context.read<Sesion>();
    final ed = insp['datos_equipo']?['edificio'] ?? {};
    final nombreInicial = switch (tipo) {
      'INSPECTOR' => sesion.nombre,
      'TECNICO_MANTENIMIENTO' => insp['tecnico_mantenimiento'] ?? '',
      _ => ed['administrador_nombre'] ?? '',
    };
    final nombre = TextEditingController(text: nombreInicial);
    final documento = TextEditingController();
    final cargo = TextEditingController(text: tipo == 'REPRESENTANTE_EDIFICIO' ? 'Administrador(a)' : '');
    final empresa = TextEditingController(text: tipo == 'TECNICO_MANTENIMIENTO' ? (insp['empresa_mantenimiento'] ?? '') : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Firma: $titulo'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre completo *')),
            const SizedBox(height: 8),
            TextField(controller: documento, decoration: const InputDecoration(labelText: 'Documento')),
            const SizedBox(height: 8),
            TextField(controller: cargo, decoration: const InputDecoration(labelText: 'Cargo')),
            if (tipo == 'TECNICO_MANTENIMIENTO') ...[
              const SizedBox(height: 8),
              TextField(controller: empresa, decoration: const InputDecoration(labelText: 'Empresa')),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => nombre.text.trim().isEmpty ? null : Navigator.pop(c, true), child: const Text('Firmar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final firma = await capturarFirma(context, '$titulo: ${nombre.text.trim()}');
    if (firma == null || !context.mounted) return;
    final guardado = await ejecutar(
        context,
        () => Api.post('/inspecciones/${insp['id_inspeccion']}/firmas', {
              'tipo_firmante': tipo,
              'nombre': nombre.text.trim(),
              'documento': documento.text.trim().isEmpty ? null : documento.text.trim(),
              'cargo': cargo.text.trim().isEmpty ? null : cargo.text.trim(),
              'empresa': empresa.text.trim().isEmpty ? null : empresa.text.trim(),
              'firma_base64': firma,
              'numero_visita': visita,
            }),
        exito: 'Firma guardada');
    if (guardado) alCambiar();
  }

  @override
  Widget build(BuildContext context) {
    final visitaActual = insp['estado'] == 'EN_SEGUNDA_VISITA' ? 2 : 1;
    final firmas = insp['firmas'] as List;
    final visitas = {1, ...firmas.map((f) => f['numero_visita'] as int), visitaActual}.toList()..sort();
    return Contenido(
      ancho: 800,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        for (final v in visitas) ...[
          Titulo(v == 1 ? 'Primera visita' : 'Segunda visita (cierre de hallazgos)'),
          for (final (tipo, titulo, icono) in _tipos) _tarjeta(context, v, tipo, titulo, icono, firmas, v == visitaActual),
        ],
        const SizedBox(height: 80),
      ]),
    );
  }

  Widget _tarjeta(BuildContext context, int visita, String tipo, String titulo, IconData icono, List firmas, bool actual) {
    final f = firmas.where((x) => x['numero_visita'] == visita && x['tipo_firmante'] == tipo).firstOrNull;
    return Card(
      child: ListTile(
        leading: Icon(icono, color: f != null ? Colores.exito : Colores.gris),
        title: Text(titulo),
        subtitle: f == null
            ? const Text('Pendiente de firma')
            : Row(children: [
                Expanded(child: Text('${f['nombre']}${f['cargo'] != null ? ' · ${f['cargo']}' : ''}\n${fechaHora(f['fecha_firma'])}')),
                Image.network(Api.url(f['url']), height: 44, errorBuilder: (_, _, _) => const SizedBox()),
              ]),
        trailing: editable && actual
            ? FilledButton.tonal(
                onPressed: () => _firmar(context, tipo, titulo, visita),
                child: Text(f == null ? 'Firmar' : 'Repetir'),
              )
            : (f != null ? const Icon(Icons.check_circle, color: Colores.exito) : null),
      ),
    );
  }
}
