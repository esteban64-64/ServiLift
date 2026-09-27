import 'package:flutter/material.dart';

import 'comunes.dart';

/// Campo de un formulario simple en diálogo.
class Campo {
  final String clave;
  final String etiqueta;
  final bool obligatorio;
  final bool numero;
  final bool decimal;
  final List<(String, String)>? opciones; // (valor, texto)
  final String? inicial;
  final bool oculto;
  const Campo(this.clave, this.etiqueta,
      {this.obligatorio = false,
      this.numero = false,
      this.decimal = false,
      this.opciones,
      this.inicial,
      this.oculto = false});
}

/// Muestra un formulario en diálogo y envía los datos con [guardar].
/// Devuelve lo que responda el backend, o null si se cancela.
Future<dynamic> formularioDialogo(
  BuildContext context, {
  required String titulo,
  required List<Campo> campos,
  required Future<dynamic> Function(Map<String, dynamic> datos) guardar,
  Map<String, dynamic>? valores,
}) {
  final ctrls = {
    for (final c in campos) c.clave: TextEditingController(text: '${valores?[c.clave] ?? c.inicial ?? ''}')
  };
  final seleccion = <String, String?>{
    for (final c in campos.where((c) => c.opciones != null)) c.clave: (valores?[c.clave] ?? c.inicial)?.toString()
  };
  final formKey = GlobalKey<FormState>();
  var enviando = false;

  return showDialog(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(titulo),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final campo in campos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: campo.opciones != null
                        ? DropdownButtonFormField<String>(
                            initialValue: seleccion[campo.clave],
                            isExpanded: true,
                            decoration: InputDecoration(labelText: campo.etiqueta + (campo.obligatorio ? ' *' : '')),
                            items: [for (final o in campo.opciones!) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
                            validator: (v) => campo.obligatorio && v == null ? 'Obligatorio' : null,
                            onChanged: (v) => seleccion[campo.clave] = v,
                          )
                        : TextFormField(
                            controller: ctrls[campo.clave],
                            obscureText: campo.oculto,
                            keyboardType: campo.numero ? TextInputType.numberWithOptions(decimal: campo.decimal) : null,
                            decoration: InputDecoration(labelText: campo.etiqueta + (campo.obligatorio ? ' *' : '')),
                            validator: (v) {
                              if (campo.obligatorio && (v == null || v.trim().isEmpty)) return 'Obligatorio';
                              if (campo.numero && v != null && v.trim().isNotEmpty && num.tryParse(v.trim()) == null) {
                                return 'Número inválido';
                              }
                              return null;
                            },
                          ),
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
            onPressed: enviando
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    final datos = <String, dynamic>{};
                    for (final campo in campos) {
                      if (campo.opciones != null) {
                        if (seleccion[campo.clave] != null) datos[campo.clave] = seleccion[campo.clave];
                        continue;
                      }
                      final t = ctrls[campo.clave]!.text.trim();
                      if (t.isEmpty) {
                        if (valores != null) datos[campo.clave] = null;
                        continue;
                      }
                      datos[campo.clave] = campo.numero ? (campo.decimal ? double.parse(t) : int.parse(t)) : t;
                    }
                    setState(() => enviando = true);
                    dynamic resultado;
                    final ok = await ejecutar(c, () async => resultado = await guardar(datos));
                    setState(() => enviando = false);
                    if (ok && c.mounted) Navigator.pop(c, resultado ?? true);
                  },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}
