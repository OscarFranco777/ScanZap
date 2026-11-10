import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/inventory_provider.dart';

/// Pantalla de inicio de sesión contra ERPNext (URL + usuario + contraseña).
/// Vive aparte para que la pantalla de Configuración quede limpia.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _rememberMe = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;
  String _progressText = '';

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final provider = context.read<InventoryProvider>();
    final config = await provider.loadSavedConfig();
    _urlController.text = config['url'] ?? '';
    _userController.text = config['username'] ?? '';
    // Solo cargar contraseña si estaba guardada (Recordarme activo)
    if (config['password']!.isNotEmpty) {
      _passController.text = config['password']!;
      _rememberMe = config['remember'] == 'true';
    }
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _progressText = 'Iniciando sesión...';
    });

    final provider = context.read<InventoryProvider>();

    // Login rápido: solo autentica y configura la sesión. El catálogo de
    // productos se carga en segundo plano DESPUÉS de entrar al panel principal.
    final ok = await provider.connectToErpNext(
      url: _normalizeUrl(_urlController.text),
      username: _userController.text,
      password: _passController.text,
      rememberMe: _rememberMe,
      deferItems: true,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (ok) {
      // Si al login le faltaron permisos mínimos, avisar pero igual dejar
      // entrar (el detalle completo se revisa en Configuración → Permisos).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.missingPermissions
              ? '⚠️ Conectado, pero faltan permisos — revisá Configuración'
              : '✅ Conectado — cargando productos en segundo plano...'),
          backgroundColor: provider.missingPermissions
              ? Colors.orange
              : Colors.green,
        ),
      );
      Navigator.of(context).pushReplacementNamed('/home');
      provider.loadInitialItems();
    } else {
      setState(() => _error = provider.connectionError);
    }
  }

  /// Normaliza la URL: agrega https:// si el usuario no lo escribió y
  /// quita barras finales para evitar '//api' en los endpoints.
  String _normalizeUrl(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'https://$v';
    }
    return v.replaceAll(RegExp(r'/+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔌 Iniciar sesión'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2,
                    size: 72,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Inventario ERPNext',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ingresá tus credenciales de ERPNext',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 28),

                  // Campo URL
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL de ERPNext',
                      hintText: 'mi-instancia.erp.nextoncloud.net',
                      prefixIcon: Icon(Icons.language),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Ingresá la URL' : null,
                  ),
                  const SizedBox(height: 16),

                  // Campo Usuario
                  TextFormField(
                    controller: _userController,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      hintText: 'ej: usuario@empresa.com',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Ingresá el usuario'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Campo Contraseña
                  TextFormField(
                    controller: _passController,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Ingresá la contraseña'
                        : null,
                  ),
                  const SizedBox(height: 12),

                  // Recordarme
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (v) =>
                            setState(() => _rememberMe = v ?? false),
                      ),
                      const Text('Recordarme'),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Error
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[300]!),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red[800]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Botón conectar
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _connect,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.wifi),
                      label: Text(
                        _isLoading
                            ? (_progressText.isNotEmpty
                                ? _progressText
                                : 'Conectando...')
                            : 'Iniciar Sesión',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }
}
