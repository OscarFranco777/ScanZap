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
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isConnected = false;
  String? _error;
  String _progressText = '';
  bool _checkingPerms = false;
  List<Map<String, dynamic>> _permResults = [];
  String? _permError;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    // Si el login ya corrió la validación de permisos (auto-login con
    // Recordarme, o login manual previo), mostrar el resultado de una.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<InventoryProvider>();
      if (provider.permissionResults.isNotEmpty) {
        setState(() => _permResults = provider.permissionResults);
      }
    });
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
      setState(() => _isConnected = true);

      // Si al login le faltaron permisos mínimos, quedarse en esta pantalla
      // mostrando el detalle en vez de entrar al panel.
      if (provider.missingPermissions) {
        setState(() {
          _permResults = provider.permissionResults;
          _permError =
              '⚠️ Iniciaste sesión, pero tu usuario no tiene los permisos mínimos (leer y elegir) para algunos registros. Detalle abajo.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Faltan permisos — revisá el detalle abajo'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Conectado — cargando productos en segundo plano...'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pushReplacementNamed('/home');
      // Carga de productos en segundo plano, sin bloquear el panel principal.
      provider.loadInitialItems();
    } else {
      setState(() => _error = provider.connectionError);
    }
  }

  /// Valida que el usuario tenga acceso de lectura a los registros clave
  /// (centro de costo, almacén, plantillas de impuestos).
  Future<void> _validatePermissions() async {
    setState(() {
      _checkingPerms = true;
      _permResults = [];
      _permError = null;
    });

    final provider = context.read<InventoryProvider>();

    // Si no hay sesión activa, avisar en vez de marcar todo en rojo.
    try {
      await provider.erpNextService.testConnection();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingPerms = false;
        _permError = 'Iniciá sesión primero para validar los permisos.';
      });
      return;
    }

    try {
      final results = await provider.erpNextService.checkUserPermissions();
      if (!mounted) return;
      setState(() => _permResults = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _permError = e.toString().replaceFirst('Exception: ', ''));
    }

    if (mounted) setState(() => _checkingPerms = false);
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
                      hintText: 'mi-instancia.erp.nextoncloud.net',
                      prefixIcon: Icon(Icons.language),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    // El https:// se agrega solo en _normalizeUrl; acá no se
                    // exige para no obligar a escribirlo a mano.
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
                    validator: (v) => v == null || v.trim().isEmpty ? 'Ingresá el usuario' : null,
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

                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 8),

                  // ══════════════════════════════════════════════
                  // Validación de permisos del usuario
                  // ══════════════════════════════════════════════
                  Row(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Permisos del usuario',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Verifica que tu usuario tenga acceso a los registros que el app necesita: centro de costo, almacén y plantillas de impuestos.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: _checkingPerms ? null : _validatePermissions,
                      icon: _checkingPerms
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fact_check_outlined),
                      label: Text(_checkingPerms ? 'Validando...' : 'Validar permisos'),
                    ),
                  ),

                  // Resultado de la validación
                  if (_permError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[300]!),
                      ),
                      child: Text(
                        _permError!,
                        style: TextStyle(color: Colors.orange[900]),
                      ),
                    ),
                  ],
                  if (_permResults.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        children: [
                          for (final r in _permResults)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    r['ok'] == true
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color: r['ok'] == true
                                        ? Colors.green
                                        : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r['label'] as String,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          r['ok'] == true
                                              ? 'Con acceso (leer y elegir)'
                                              : r['read'] == true
                                                  ? 'Puede leer pero NO elegir (select) — pedile al administrador el rol necesario'
                                                  : 'Sin acceso — pedile al administrador el rol necesario',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: r['ok'] == true
                                                ? Colors.green[700]
                                                : Colors.red[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_permResults.any((r) => r['ok'] != true))
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '⚠️ Tu usuario no tiene acceso a algunos registros. Pedile al administrador que te asigne los permisos necesarios.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red[800],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
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
}
