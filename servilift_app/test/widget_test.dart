import 'package:flutter_test/flutter_test.dart';
import 'package:servilift_app/core/tema.dart';

void main() {
  test('etiquetas de estado por equipo', () {
    expect(Estados.etiqueta('NO_CONFORME'), 'No conforme: solicitar 2ª visita');
    expect(Estados.etiqueta('CERTIFICADO_LISTO'), 'Certificado listo');
  });
}
