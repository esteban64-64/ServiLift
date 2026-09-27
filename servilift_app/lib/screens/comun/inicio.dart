import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/tema.dart';
import '../../widgets/comunes.dart';
import '../director/informes.dart';
import 'cotizaciones.dart';

const _paleta = [
  Color(0xFF2F6FB0), Color(0xFF0E7C4A), Color(0xFFC97B1A), Color(0xFFC0392B), Color(0xFF6B4FA0),
  Color(0xFF1B998B), Color(0xFF8C5E3C), Color(0xFF6B7A8C),
];

Color _color(String? nombre, int i) => switch (nombre) {
      'info' => Colores.info,
      'exito' => Colores.exito,
      'alerta' => Colores.alerta,
      'error' => Colores.error,
      'gris' => Colores.gris,
      _ => _paleta[i % _paleta.length],
    };

/// Página de inicio de cada rol: indicadores, gráficas y pendientes (datos de GET /dashboard).
class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Cargador<Map>(
      intervalo: const Duration(seconds: 60),
      cargar: () async => await Api.get('/dashboard') as Map,
      builder: (context, d, recargar) {
        final ancho = MediaQuery.sizeOf(context).width;
        final anchoGrafica = ancho >= 1100 ? 520.0 : double.infinity;
        return RefreshIndicator(
          onRefresh: recargar,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(d['titulo'] ?? 'Inicio', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colores.navy)),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [for (final k in d['kpis'] ?? []) _Kpi(k)]),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 16, children: [
              for (final g in d['graficas'] ?? [])
                SizedBox(width: anchoGrafica, child: _TarjetaGrafica(g)),
            ]),
            const SizedBox(height: 8),
            for (final l in d['listas'] ?? [])
              if ((l['items'] as List).isNotEmpty) _Lista(l, recargar),
          ]),
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  final Map k;
  const _Kpi(this.k);

  @override
  Widget build(BuildContext context) {
    final c = _color(k['color'], 0);
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: c, width: 5)),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k['titulo'], style: const TextStyle(color: Colores.gris, fontSize: 13)),
        const SizedBox(height: 4),
        Text('${k['valor']}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c)),
        if (k['detalle'] != null) Text(k['detalle'], style: const TextStyle(fontSize: 12, color: Colores.gris)),
      ]),
    );
  }
}

class _TarjetaGrafica extends StatelessWidget {
  final Map g;
  const _TarjetaGrafica(this.g);

  @override
  Widget build(BuildContext context) {
    final datos = (g['datos'] as List).cast<Map>();
    final vacio = datos.isEmpty || datos.every((x) => (x['valor'] ?? 0) == 0);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g['titulo'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          if (vacio)
            const SizedBox(height: 80, child: Center(child: Text('Sin datos todavía', style: TextStyle(color: Colores.gris))))
          else
            switch (g['tipo']) {
              'dona' => _Dona(datos),
              'meses' => _Columnas(datos),
              _ => _Barras(datos),
            },
        ]),
      ),
    );
  }
}

/// Barras horizontales (categorías)
class _Barras extends StatelessWidget {
  final List<Map> datos;
  const _Barras(this.datos);

  @override
  Widget build(BuildContext context) {
    final maximo = datos.map((x) => (x['valor'] as num).toDouble()).fold(0.0, math.max);
    return Column(children: [
      for (var i = 0; i < datos.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 170, child: Text(datos[i]['etiqueta'], style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: LayoutBuilder(
                builder: (_, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 18,
                    width: maximo == 0 ? 0 : c.maxWidth * (datos[i]['valor'] as num) / maximo,
                    decoration: BoxDecoration(color: _color(datos[i]['color'], i), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            SizedBox(width: 36, child: Text('${datos[i]['valor']}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
    ]);
  }
}

/// Columnas verticales (series por mes o por día)
class _Columnas extends StatelessWidget {
  final List<Map> datos;
  const _Columnas(this.datos);

  @override
  Widget build(BuildContext context) {
    final maximo = datos.map((x) => (x['valor'] as num).toDouble()).fold(0.0, math.max);
    return SizedBox(
      height: 170,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final x in datos)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${x['valor']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Container(
                  height: maximo == 0 ? 0 : 120 * (x['valor'] as num) / maximo,
                  decoration: BoxDecoration(color: _color(x['color'], 0), borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ),
                const SizedBox(height: 4),
                Text(x['etiqueta'], style: const TextStyle(fontSize: 10, color: Colores.gris), maxLines: 1, overflow: TextOverflow.clip),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Gráfica de dona con leyenda
class _Dona extends StatelessWidget {
  final List<Map> datos;
  const _Dona(this.datos);

  @override
  Widget build(BuildContext context) {
    final total = datos.fold<num>(0, (s, x) => s + (x['valor'] as num));
    final colores = [for (var i = 0; i < datos.length; i++) _color(datos[i]['color'], i)];
    return Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(
        width: 150,
        height: 150,
        child: CustomPaint(
          painter: _PintorDona([for (final x in datos) (x['valor'] as num).toDouble()], colores),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$total', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const Text('total', style: TextStyle(fontSize: 11, color: Colores.gris)),
            ]),
          ),
        ),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < datos.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: colores[i], borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text('${datos[i]['etiqueta']}: ${datos[i]['valor']}', style: const TextStyle(fontSize: 12)),
            ]),
          ),
      ]),
    ]);
  }
}

class _PintorDona extends CustomPainter {
  final List<double> valores;
  final List<Color> colores;
  _PintorDona(this.valores, this.colores);

  @override
  void paint(Canvas canvas, Size size) {
    final total = valores.fold(0.0, (a, b) => a + b);
    if (total == 0) return;
    final rect = Offset.zero & size;
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26;
    var inicio = -math.pi / 2;
    for (var i = 0; i < valores.length; i++) {
      final barrido = 2 * math.pi * valores[i] / total;
      canvas.drawArc(rect.deflate(13), inicio, barrido, false, pincel..color = colores[i]);
      inicio += barrido;
    }
  }

  @override
  bool shouldRepaint(covariant _PintorDona old) => old.valores != valores;
}

class _Lista extends StatelessWidget {
  final Map l;
  final Future<void> Function() recargar;
  const _Lista(this.l, this.recargar);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Titulo(l['titulo']),
      Card(
        margin: EdgeInsets.zero,
        child: Column(children: [
          for (final it in l['items'])
            ListTile(
              dense: true,
              title: Text(it['texto']),
              subtitle: it['subtexto'] == null || '${it['subtexto']}'.isEmpty ? null : Text(it['subtexto']),
              trailing: it['estado'] != null ? EstadoChip(it['estado']) : null,
              onTap: it['id_cotizacion'] != null
                  ? () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => CotizacionDetalleScreen(id: it['id_cotizacion'])));
                      recargar();
                    }
                  : it['id_informe'] != null
                      ? () async {
                          await Navigator.push(
                              context, MaterialPageRoute(builder: (_) => RevisionScreen(idInforme: it['id_informe'])));
                          recargar();
                        }
                      : null,
            ),
        ]),
      ),
      const SizedBox(height: 8),
    ]);
  }
}
