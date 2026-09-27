import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../core/api.dart';
import '../core/tema.dart';

class EstadoChip extends StatelessWidget {
  final String? estado;
  final String? texto;
  const EstadoChip(this.estado, {super.key, this.texto});

  @override
  Widget build(BuildContext context) {
    final c = Estados.color(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(texto ?? Estados.etiqueta(estado),
          style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Carga datos del backend con estados de cargando / error / reintentar.
/// Se actualiza solo: al guardar (recargar) y cada [intervalo] mientras la pantalla está abierta,
/// sin mostrar el indicador de carga ni perder lo que ya se ve.
class Cargador<T> extends StatefulWidget {
  final Future<T> Function() cargar;
  final Widget Function(BuildContext context, T datos, Future<void> Function() recargar) builder;
  final Duration? intervalo;
  const Cargador({
    super.key,
    required this.cargar,
    required this.builder,
    this.intervalo = const Duration(seconds: 20),
  });

  @override
  State<Cargador<T>> createState() => CargadorState<T>();
}

class CargadorState<T> extends State<Cargador<T>> {
  T? _datos;
  bool _tieneDatos = false;
  Object? _error;
  bool _cargando = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    recargar();
    if (widget.intervalo != null) {
      _timer = Timer.periodic(widget.intervalo!, (_) {
        if (mounted && !_cargando) recargar();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Vuelve a pedir los datos. Si ya hay datos en pantalla se reemplazan al llegar (sin parpadeo).
  Future<void> recargar() async {
    if (!_tieneDatos) {
      setState(() {
        _error = null;
      });
    }
    _cargando = true;
    try {
      final datos = await widget.cargar();
      if (!mounted) return;
      setState(() {
        _datos = datos;
        _tieneDatos = true;
        _error = null;
      });
    } catch (e) {
      // Si ya hay datos visibles se conservan (por ejemplo, sin señal por un momento)
      if (mounted && !_tieneDatos) {
        setState(() {
          _error = e;
        });
      }
    } finally {
      _cargando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tieneDatos) return widget.builder(context, _datos as T, recargar);
    if (_error == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48, color: Colores.gris),
          const SizedBox(height: 8),
          Text('$_error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: recargar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ]),
      ),
    );
  }
}

class Vacio extends StatelessWidget {
  final String texto;
  final IconData icono;
  const Vacio(this.texto, {super.key, this.icono = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 56, color: Colores.gris.withValues(alpha: .6)),
            const SizedBox(height: 8),
            Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: Colores.gris)),
          ]),
        ),
      );
}

class Titulo extends StatelessWidget {
  final String texto;
  final Widget? accion;
  const Titulo(this.texto, {super.key, this.accion});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Row(children: [
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ?accion,
        ]),
      );
}

/// Contenedor con ancho máximo para que en PC no se estire todo.
class Contenido extends StatelessWidget {
  final Widget child;
  final double ancho;
  const Contenido({super.key, required this.child, this.ancho = 1100});

  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: ancho), child: child));
}

void mensaje(BuildContext context, String texto, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(texto),
    backgroundColor: error ? Colores.error : Colores.navy,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Ejecuta una acción contra el backend mostrando el resultado. Devuelve true si salió bien.
Future<bool> ejecutar(BuildContext context, Future<dynamic> Function() accion, {String? exito}) async {
  try {
    await accion();
    if (context.mounted && exito != null) mensaje(context, exito);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) {
      if (e.pendientes.isNotEmpty) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(e.mensaje),
            content: SingleChildScrollView(child: Text(e.pendientes.map((p) => '• $p').join('\n'))),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
          ),
        );
      } else {
        mensaje(context, e.mensaje, error: true);
      }
    }
  } catch (e) {
    if (context.mounted) mensaje(context, 'Sin conexión con el servidor', error: true);
  }
  return false;
}

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String si = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(si)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> pedirTexto(BuildContext context, String titulo, {String etiqueta = '', bool obligatorio = true}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 420,
        child: TextField(controller: ctrl, maxLines: 4, autofocus: true, decoration: InputDecoration(labelText: etiqueta)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (obligatorio && ctrl.text.trim().isEmpty) return;
            Navigator.pop(c, ctrl.text.trim());
          },
          child: const Text('Aceptar'),
        ),
      ],
    ),
  );
}

/// Lienzo de firma. Devuelve el PNG en base64 o null si se cancela.
Future<String?> capturarFirma(BuildContext context, String titulo) {
  final ctrl = SignatureController(penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 480,
        height: 240,
        child: Column(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8)),
              child: Signature(controller: ctrl, backgroundColor: Colors.white),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: ctrl.clear, icon: const Icon(Icons.refresh), label: const Text('Borrar')),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            if (ctrl.isEmpty) return;
            final png = await ctrl.toPngBytes();
            if (png != null && c.mounted) Navigator.pop(c, base64Encode(png));
          },
          child: const Text('Guardar firma'),
        ),
      ],
    ),
  );
}

/// Fila etiqueta: valor
class Dato extends StatelessWidget {
  final String etiqueta;
  final String? valor;
  const Dato(this.etiqueta, this.valor, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(etiqueta, style: const TextStyle(color: Colores.gris, fontSize: 13))),
          Expanded(child: Text(valor == null || valor!.isEmpty ? '-' : valor!, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

/// Campo de fecha con calendario y opción "NI / No aplica" (queda vacío y se puede completar
/// más adelante, antes de finalizar). Muestra dd/mm/aaaa; [fechaParaApi] la convierte.
class CampoFecha extends StatelessWidget {
  final TextEditingController controller;
  final String etiqueta;
  final bool habilitado;
  const CampoFecha({super.key, required this.controller, required this.etiqueta, this.habilitado = true});

  static String mostrar(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// '' / NI / N/A -> null. Acepta dd/mm/aaaa o aaaa-mm-dd. Lanza FormatException si no es válida.
  static String? fechaParaApi(String texto) {
    final t = texto.trim().toUpperCase();
    if (t.isEmpty || t == 'NI' || t == 'N/A' || t == 'NA' || t == 'NO APLICA') return null;
    final iso = DateTime.tryParse(t);
    if (iso != null) return iso.toIso8601String().substring(0, 10);
    final p = t.split(RegExp(r'[/-]'));
    if (p.length == 3) {
      final d = int.tryParse(p[0]), m = int.tryParse(p[1]), a = int.tryParse(p[2]);
      if (d != null && m != null && a != null && m >= 1 && m <= 12 && d >= 1 && d <= 31 && a > 1900) {
        return '${a.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      }
    }
    throw FormatException('Fecha inválida: $texto');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, valor, _) => TextField(
        controller: controller,
        enabled: habilitado,
        readOnly: true,
        onTap: habilitado ? () => _elegir(context) : null,
        decoration: InputDecoration(
          labelText: etiqueta,
          hintText: 'NI (no informa / no aplica)',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixIcon: !habilitado
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Elegir fecha', icon: const Icon(Icons.calendar_month, size: 20), onPressed: () => _elegir(context)),
                  TextButton(
                    onPressed: valor.text.isEmpty ? null : () => controller.clear(),
                    child: const Text('NI'),
                  ),
                ]),
        ),
      ),
    );
  }

  Future<void> _elegir(BuildContext context) async {
    DateTime inicial = DateTime.now();
    try {
      final iso = fechaParaApi(controller.text);
      if (iso != null) inicial = DateTime.parse(iso);
    } catch (_) {}
    final d = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(1950),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: etiqueta,
    );
    if (d != null) controller.text = mostrar(d.toIso8601String());
  }
}
