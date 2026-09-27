import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';

bool get _hayCamara => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Toma fotos (cámara) o las elige de la galería y las sube en lotes de 5.
/// Devuelve cuántas se subieron.
Future<int> agregarFotos(BuildContext context, int idInspeccion, {int? idItem, String? descripcion}) async {
  final picker = ImagePicker();
  var fuente = 'galeria';
  if (_hayCamara) {
    final f = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Tomar foto'), onTap: () => Navigator.pop(c, 'camara')),
          ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de la galería (varias)'),
              onTap: () => Navigator.pop(c, 'galeria')),
        ]),
      ),
    );
    if (f == null) return 0;
    fuente = f;
  }
  final archivos = <XFile>[];
  if (fuente == 'camara') {
    final x = await picker.pickImage(source: ImageSource.camera, maxWidth: 1920, imageQuality: 85);
    if (x != null) archivos.add(x);
  } else {
    archivos.addAll(await picker.pickMultiImage(maxWidth: 1920, imageQuality: 85));
  }
  if (archivos.isEmpty || !context.mounted) return 0;

  final progreso = ValueNotifier<int>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: ValueListenableBuilder<int>(
        valueListenable: progreso,
        builder: (_, n, _) => Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: n / archivos.length),
          const SizedBox(height: 12),
          Text('Subiendo fotos $n de ${archivos.length}...'),
        ]),
      ),
    ),
  );
  var subidas = 0;
  String? error;
  for (var i = 0; i < archivos.length; i += 5) {
    final lote = archivos.skip(i).take(5).toList();
    try {
      await Api.subirArchivos(
        '/inspecciones/$idInspeccion/fotos',
        [for (final x in lote) ArchivoSubida(x.name, await x.readAsBytes())],
        campos: {if (idItem != null) 'id_item': '$idItem', 'descripcion': ?descripcion},
      );
      subidas += lote.length;
      progreso.value = subidas;
    } catch (e) {
      error = '$e';
      break;
    }
  }
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
    mensaje(context, error == null ? '$subidas fotos subidas' : 'Se subieron $subidas. Error: $error', error: error != null);
  }
  return subidas;
}

/// Álbum de fotos de la inspección. El director puede marcar cuáles van en el PDF.
class FotosTab extends StatefulWidget {
  final int idInspeccion;
  final bool editable;
  final bool modoDirector;
  const FotosTab({super.key, required this.idInspeccion, required this.editable, this.modoDirector = false});

  @override
  State<FotosTab> createState() => _FotosTabState();
}

class _FotosTabState extends State<FotosTab> with AutomaticKeepAliveClientMixin {
  final _cargador = GlobalKey<CargadorState<List>>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _ver(Map f, Future<void> Function() recargar) async {
    final desc = TextEditingController(text: f['descripcion'] ?? '');
    await showDialog(
      context: context,
      builder: (c) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: InteractiveViewer(child: Image.network(Api.url(f['url'])))),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                TextField(
                  controller: desc,
                  enabled: widget.editable || widget.modoDirector,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
                  if (widget.editable && !widget.modoDirector)
                    TextButton.icon(
                      onPressed: () async {
                        if (await confirmar(c, 'Eliminar foto', '¿Eliminar esta foto?', si: 'Eliminar')) {
                          await Api.delete('/inspecciones/${widget.idInspeccion}/fotos/${f['id_foto']}');
                          if (c.mounted) Navigator.pop(c);
                        }
                      },
                      icon: const Icon(Icons.delete_outline, color: Colores.error),
                      label: const Text('Eliminar', style: TextStyle(color: Colores.error)),
                    ),
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar')),
                  if (widget.editable || widget.modoDirector)
                    FilledButton(
                      onPressed: () async {
                        await Api.put('/inspecciones/${widget.idInspeccion}/fotos/${f['id_foto']}', {'descripcion': desc.text});
                        if (c.mounted) Navigator.pop(c);
                      },
                      child: const Text('Guardar'),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
    recargar();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.editable && !widget.modoDirector
          ? FloatingActionButton.extended(
              heroTag: 'fotos',
              onPressed: () async {
                if (await agregarFotos(context, widget.idInspeccion) > 0) _cargador.currentState?.recargar();
              },
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Agregar fotos'),
            )
          : null,
      body: Cargador<List>(
        key: _cargador,
        cargar: () async => await Api.get('/inspecciones/${widget.idInspeccion}/fotos') as List,
        builder: (context, fotos, recargar) {
          if (fotos.isEmpty) return const Vacio('Aún no hay fotos del equipo', icono: Icons.photo_camera_outlined);
          final enPdf = fotos.where((f) => f['incluir_en_informe'] == true).length;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('${fotos.length} fotos · $enPdf van en el informe'
                  '${widget.modoDirector ? ' (toque la casilla para incluir o excluir)' : ''}'),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 90),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, mainAxisSpacing: 6, crossAxisSpacing: 6),
                itemCount: fotos.length,
                itemBuilder: (_, i) {
                  final f = fotos[i];
                  return GestureDetector(
                    onTap: () => _ver(f, recargar),
                    child: Stack(fit: StackFit.expand, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(Api.url(f['url_miniatura']), fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFE2E8F0), child: Icon(Icons.broken_image))),
                      ),
                      if (f['descripcion'] != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.all(4),
                            child: Text(f['descripcion'], maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        ),
                      if (widget.modoDirector)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Checkbox(
                            value: f['incluir_en_informe'] == true,
                            fillColor: const WidgetStatePropertyAll(Colors.white),
                            checkColor: Colores.acento,
                            onChanged: (v) async {
                              await Api.put('/inspecciones/${widget.idInspeccion}/fotos/${f['id_foto']}',
                                  {'incluir_en_informe': v, 'revisada': true});
                              recargar();
                            },
                          ),
                        ),
                    ]),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}
