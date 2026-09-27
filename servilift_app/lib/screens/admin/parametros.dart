import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../widgets/comunes.dart';
import '../../widgets/formulario.dart';

const _etiquetas = {
  'PLAZO_DIAS_LEVE': 'Plazo de corrección defecto LEVE (días)',
  'PLAZO_DIAS_GRAVE': 'Plazo de corrección defecto GRAVE (días)',
  'PLAZO_DIAS_MUY_GRAVE': 'Plazo de corrección defecto MUY GRAVE (días)',
  'CERTIFICADO_VIGENCIA_MESES': 'Vigencia del certificado (meses)',
  'EMPRESA_NOMBRE': 'Nombre de la empresa (informes y certificados)',
  'EMPRESA_NIT': 'NIT de la empresa',
  'INFORME_TITULO': 'Título del informe',
  'INFORME_CODIGO_FORMATO': 'Código del formato',
  'INFORME_VERSION_FORMATO': 'Versión del formato',
  'TEXTO_ATESTACION': 'Texto de atestación',
  'CONVENCION_RESULTADOS': 'Convención de resultados',
  'FOTOS_MAX_POR_EQUIPO': 'Máximo de fotos por equipo',
};

/// Parámetros generales (solo administrador): plazos de corrección, datos de la empresa, textos del informe.
class ParametrosScreen extends StatelessWidget {
  const ParametrosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Cargador<Map>(
      intervalo: null,
      cargar: () async => await Api.get('/catalogos/parametros') as Map,
      builder: (context, p, recargar) {
        final claves = [..._etiquetas.keys.where(p.containsKey), ...p.keys.where((k) => !_etiquetas.containsKey(k))];
        return Contenido(
          ancho: 900,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('El plazo de un equipo no conforme es el menor entre sus hallazgos: '
                  'cada defecto usa el plazo de su calificación.'),
            ),
            for (final k in claves)
              Card(
                child: ListTile(
                  title: Text(_etiquetas[k] ?? k),
                  subtitle: Text('${p[k]}', maxLines: 3, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.edit),
                  onTap: () async {
                    final ok = await formularioDialogo(context,
                        titulo: _etiquetas[k] ?? k,
                        campos: [Campo('valor', 'Valor', obligatorio: true, numero: k.startsWith('PLAZO') || k.endsWith('MESES'))],
                        valores: {'valor': p[k]},
                        guardar: (d) => Api.put('/catalogos/parametros/$k', {'valor': '${d['valor']}'}));
                    if (ok != null) recargar();
                  },
                ),
              ),
          ]),
        );
      },
    );
  }
}
