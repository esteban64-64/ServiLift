import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servilift_app/widgets/comunes.dart';

void main() {
  testWidgets('Cargador muestra los datos nuevos al recargar', (tester) async {
    var n = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Cargador<List<int>>(
          cargar: () async => List.generate(++n, (i) => i),
          builder: (context, datos, recargar) => Column(children: [
            Text('items ${datos.length}'),
            TextButton(onPressed: () async => recargar(), child: const Text('recargar')),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('items 1'), findsOneWidget);
    await tester.tap(find.text('recargar'));
    await tester.pumpAndSettle();
    expect(find.text('items 2'), findsOneWidget);
  });
}
