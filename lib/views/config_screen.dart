import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';

/// Pantalla de configuración de la conexión a ERPNext.
/// Login con usuario y contraseña de ERPNext + "Recordarme".
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _isConnected = false;
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
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _isConnected = false;
      _error = null;
      _progressText = 'Iniciando sesión...';
    });

    final provider = context.read<InventoryProvider>();

    final ok = await provider.connectToErpNext(
      url: _urlController.text,
      username: _userController.text,
      password: _passController.text,
      rememberMe: _rememberMe,
      onProgress: (loaded, total) {
        if (mounted) {
          setState(() {
            _progressText = total != null
                ? 'Cargando productos... $loaded / $total'
                : 'Cargando productos... $loaded';
          });
        }
      },
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (ok) {
      setState(() => _isConnected = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Conectado — ${provider.allItems.length} productos cargados'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      setState(() => _error = provider.connectionError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔌 Conexión a ERPNext'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  Icon(
                    Icons.inventory_2,
                    size: 80,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 32),

                  // Campo URL
                  TextFormField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL de ERPNext',
                      hintText: 'https://mi-instancia.erp.nextoncloud.net',
                      prefixIcon: Icon(Icons.language),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Ingresá la URL';
                      if (!v.startsWith('http')) return 'Debe empezar con http:// o https://';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Campo Usuario
                  TextFormField(
                    controller: _userController,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      hintText: 'ej: oscar@superzito.com',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Ingresá el usuario' : null,
                  ),
                  const SizedBox(height: 16),

                  // Campo Contraseña
                  TextFormField(
                    controller: _passController,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Ingresá la contraseña' : null,
                  ),
                  const SizedBox(height: 12),

                  // Recordarme
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (v) => setState(() => _rememberMe = v ?? false),
                      ),
                      const Text('Recordarme'),
                      const Spacer(),
                      if (_isConnected)
                        Text(
                          '🟢 Conectado',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Error
                  if (_error != null)
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
                  if (_error != null) const SizedBox(height: 16),

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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : _isConnected
                              ? const Icon(Icons.check_circle)
                              : const Icon(Icons.wifi),
                      label: Text(
                        _isLoading
                            ? _progressText.isNotEmpty ? _progressText : 'Conectando...'
                            : _isConnected
                                ? 'Conectado ✓'
                                : 'Iniciar Sesión',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isConnected ? Colors.green : Theme.of(context).primaryColor,
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
