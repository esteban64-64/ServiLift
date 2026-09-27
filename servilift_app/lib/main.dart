import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/auth.dart';
import 'core/tema.dart';
import 'screens/login.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env');
  await initializeDateFormatting('es_CO');
  runApp(ChangeNotifierProvider(create: (_) => Sesion()..restaurar(), child: const ServiLiftApp()));
}

class ServiLiftApp extends StatelessWidget {
  const ServiLiftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ServiLift',
      debugShowCheckedModeBanner: false,
      theme: temaServiLift(),
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Consumer<Sesion>(
        builder: (_, sesion, _) {
          if (sesion.cargando) {
            return const Scaffold(
              backgroundColor: Colores.navy,
              body: Center(child: CircularProgressIndicator(color: Colors.white)),
            );
          }
          return sesion.autenticado ? Shell(key: ValueKey(sesion.idUsuario)) : const LoginScreen();
        },
      ),
    );
  }
}
