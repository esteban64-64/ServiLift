import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/tema.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _ocultar = true;
  bool _enviando = false;
  String? _error;

  Future<void> _entrar() async {
    if (_correo.text.trim().isEmpty || _clave.text.isEmpty) {
      setState(() => _error = 'Ingrese correo y contraseña');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    final error = await context.read<Sesion>().login(_correo.text, _clave.text);
    if (mounted) {
      setState(() {
        _enviando = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colores.navy,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.elevator_outlined, size: 56, color: Colores.acento),
                  const SizedBox(height: 8),
                  const Text('ServiLift', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colores.navy)),
                  const Text('Certificación de ascensores NTC 5926-1', textAlign: TextAlign.center,
                      style: TextStyle(color: Colores.gris)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _correo,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _clave,
                    obscureText: _ocultar,
                    onSubmitted: (_) => _entrar(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_ocultar ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _ocultar = !_ocultar),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colores.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _enviando ? null : _entrar,
                    child: _enviando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Ingresar'),
                  ),
                  const SizedBox(height: 12),
                  Text('Servidor: ${Api.baseUrl}', textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: Colores.gris)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
