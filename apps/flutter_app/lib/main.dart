import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth/auth_account_button.dart';

const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const supabaseClientKey =
    supabasePublishableKey != '' ? supabasePublishableKey : supabaseAnonKey;
const authEnabled = supabaseUrl != '' && supabaseClientKey != '';
const sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseCrashlytics? crashlytics;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp();
      crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
    } catch (error, stack) {
      debugPrint('Firebase initialization failed: $error\n$stack');
    }
  }
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    crashlytics?.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    crashlytics?.recordError(error, stack, fatal: true);
    return true;
  };
  Future<void> startApp() async {
    if (authEnabled) {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseClientKey,
      );
    }
    runApp(const TiagoMarketApp());
  }

  if (sentryDsn.isEmpty) {
    await startApp();
  } else {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = 0.15;
        options.environment = const String.fromEnvironment(
          'APP_ENV',
          defaultValue: 'production',
        );
      },
      appRunner: startApp,
    );
  }
}

class TiagoMarketApp extends StatelessWidget {
  const TiagoMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tiago Market',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006C51)),
        scaffoldBackgroundColor: const Color(0xFFF5F7F5),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFFE1E8E4)),
          ),
        ),
      ),
      home: const AuthFlowGate(),
    );
  }
}

class AuthFlowGate extends StatefulWidget {
  const AuthFlowGate({super.key});

  @override
  State<AuthFlowGate> createState() => _AuthFlowGateState();
}

class _AuthFlowGateState extends State<AuthFlowGate> {
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _minimumLoadingTimer;
  User? _user;
  bool _checkingSession = authEnabled;
  bool _minimumLoadingFinished = !authEnabled;

  @override
  void initState() {
    super.initState();
    if (!authEnabled) return;
    final auth = Supabase.instance.client.auth;
    _user = auth.currentSession?.user;
    _minimumLoadingTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _minimumLoadingFinished = true);
    });
    _authSubscription = auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      setState(() {
        _user = event.session?.user;
        _checkingSession = false;
      });
    });
  }

  @override
  void dispose() {
    _minimumLoadingTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession || !_minimumLoadingFinished) {
      return SessionLoadingPage(returningUser: _user != null);
    }

    final user = _user;
    if (user == null) return const WelcomePage();

    final role = user.userMetadata?['role'] as String?;
    if (role == 'buyer') return const SearchPage();
    if (role == 'seller') return const BusinessComingSoonPage();
    return RoleSelectionPage(user: user);
  }
}

class SessionLoadingPage extends StatelessWidget {
  const SessionLoadingPage({required this.returningUser, super.key});

  final bool returningUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 38,
              backgroundColor: Color(0xFF006C51),
              foregroundColor: Colors.white,
              child: Icon(Icons.shopping_basket_rounded, size: 38),
            ),
            const SizedBox(height: 22),
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              returningUser
                  ? 'Ingresando con tu cuenta de Google...'
                  : 'Comprobando tu sesión...',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CircleAvatar(
                    radius: 42,
                    backgroundColor: Color(0xFF006C51),
                    foregroundColor: Colors.white,
                    child: Icon(Icons.shopping_basket_rounded, size: 42),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Tu compra merece\nun mejor precio.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tiago Market compara precios cercanos para ayudarte a ahorrar tiempo y dinero.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (authEnabled)
                    const GoogleSignInButton(expanded: true)
                  else
                    const FilledButton(
                      onPressed: null,
                      child: Text('Configura Supabase para iniciar sesión'),
                    ),
                  const SizedBox(height: 14),
                  const Text(
                    'Al continuar aceptas iniciar sesión de forma segura con tu cuenta de Google.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key, required this.user});

  final User user;

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  bool _loading = false;
  String? _error;

  Future<void> _selectRole(String role) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await GoogleAuthService.setRole(role);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.user.userMetadata ?? const <String, dynamic>{};
    final name = metadata['full_name'] as String? ??
        metadata['name'] as String? ??
        widget.user.email ??
        'Hola';
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => const PrivacyDialog(),
            ),
            tooltip: 'Privacidad',
            icon: const Icon(Icons.privacy_tip_outlined),
          ),
          IconButton(
            onPressed: _loading ? null : GoogleAuthService.signOut,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hola, $name',
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '¿Cómo querés usar Tiago Market?',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 28),
                  _RoleCard(
                    icon: Icons.shopping_cart_checkout_rounded,
                    title: 'Quiero comprar',
                    description:
                        'Compará precios y encontrá opciones cercanas.',
                    onTap: _loading ? null : () => _selectRole('buyer'),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.storefront_rounded,
                    title: 'Tengo un negocio',
                    description:
                        'Prepará tu perfil para publicar precios y ofertas.',
                    onTap: _loading ? null : () => _selectRole('seller'),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(radius: 28, child: Icon(icon)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class BusinessComingSoonPage extends StatelessWidget {
  const BusinessComingSoonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiago Market Negocios'),
        actions: const [AuthAccountButton()],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storefront_rounded,
                    size: 82, color: Color(0xFF006C51)),
                const SizedBox(height: 22),
                const Text(
                  'Estamos preparando tu espacio de negocio.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Próximamente vas a poder publicar productos, precios y ofertas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 26),
                OutlinedButton.icon(
                  onPressed: () => GoogleAuthService.setRole('buyer'),
                  icon: const Icon(Icons.shopping_cart_checkout_rounded),
                  label: const Text('Volver al modo comprador'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _api = MarketApi();

  List<PriceResult> _results = demoPrices;
  bool _loading = false;
  bool _loadingMore = false;
  bool _usingDemo = apiBaseUrl.isEmpty;
  bool _usingCache = false;
  bool _locating = false;
  double? _latitude;
  double? _longitude;
  double _radiusKm = 10;
  String _orderBy = 'price';
  int _page = 1;
  bool _hasMore = true;
  String? _error;
  int _nearbyBranches = 0;
  List<ShoppingItem> _shoppingItems = const [];
  List<ProductCategory> _categories = const [];
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    if (apiBaseUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
    _loadShoppingList();
    _loadCategories();
    _scrollController.addListener(_loadMoreOnScroll);
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _api.categories();
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      // La búsqueda sigue disponible aunque falle el catálogo de categorías.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMoreOnScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore ||
        _usingDemo) {
      return;
    }
    if (_scrollController.position.extentAfter < 700) {
      _search(null, true);
    }
  }

  Future<void> _loadShoppingList() async {
    final items = await ShoppingListStorage.load();
    if (mounted) setState(() => _shoppingItems = items);
  }

  Future<void> _addToShoppingList(ProductComparisonGroup group) async {
    final existingIndex = _shoppingItems.indexWhere(
      (item) => item.comparisonKey == group.comparisonKey,
    );
    final items = [..._shoppingItems];
    if (existingIndex >= 0) {
      items[existingIndex] = items[existingIndex].copyWith(
        quantity: items[existingIndex].quantity + 1,
        prices: group.prices,
      );
    } else {
      items.add(
        ShoppingItem(
          comparisonKey: group.comparisonKey,
          productName: group.productName,
          quantity: 1,
          prices: group.prices,
        ),
      );
    }
    await ShoppingListStorage.save(items);
    if (!mounted) return;
    setState(() => _shoppingItems = items);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${group.productName} agregado a tu lista')),
    );
  }

  Future<void> _updateShoppingItem(ShoppingItem item, int quantity) async {
    final items = [..._shoppingItems];
    final index =
        items.indexWhere((value) => value.comparisonKey == item.comparisonKey);
    if (index < 0) return;
    if (quantity <= 0) {
      items.removeAt(index);
    } else {
      items[index] = item.copyWith(quantity: quantity);
    }
    await ShoppingListStorage.save(items);
    if (mounted) setState(() => _shoppingItems = items);
  }

  Future<void> _showShoppingList() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ShoppingListSheet(
        items: _shoppingItems,
        onQuantityChanged: _updateShoppingItem,
      ),
    );
  }

  Future<void> _search([String? quickQuery, bool append = false]) async {
    if (append && _loading) return;
    if (quickQuery != null) _controller.text = quickQuery;
    final query = _controller.text.trim();
    final page = append ? _page + 1 : 1;

    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    try {
      final results = await _api.compare(
        query,
        latitude: _latitude,
        longitude: _longitude,
        radiusKm: _radiusKm,
        orderBy: _orderBy,
        page: page,
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _results = append ? [..._results, ...results] : results;
        _page = page;
        _hasMore = results.length == 100;
        _usingDemo = apiBaseUrl.isEmpty;
        _usingCache = _api.usedCache;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = demoPrices;
        _usingDemo = true;
        _usingCache = false;
        _error = 'No se pudo consultar la API. Mostrando una vista de ejemplo.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _useLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Activa la ubicación del dispositivo para continuar.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('No se concedió permiso de ubicación.');
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _orderBy = 'distance';
      });
      await _search();
      final nearbyBranches = await _api.nearbyBranchCount(
        position.latitude,
        position.longitude,
        _radiusKm,
      );
      if (mounted) setState(() => _nearbyBranches = nearbyBranches);
      if (mounted && _results.isEmpty) {
        setState(() {
          _error = nearbyBranches > 0
              ? 'Encontramos $nearbyBranches sucursales verificadas cerca. Sus precios específicos todavía no están publicados; mostramos precios online al quitar la ubicación.'
              : 'Todavía no hay sucursales verificadas dentro de este radio.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
      _orderBy = 'price';
      _nearbyBranches = 0;
    });
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupPriceResults(_results);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7F5),
        title: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xFF006C51),
              foregroundColor: Colors.white,
              child: Icon(Icons.shopping_basket_rounded),
            ),
            SizedBox(width: 12),
            Text('Tiago Market', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => FeedbackDialog(api: _api),
            ),
            tooltip: 'Enviar comentario',
            icon: const Icon(Icons.rate_review_outlined),
          ),
          IconButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => const PrivacyDialog(),
            ),
            tooltip: 'Privacidad',
            icon: const Icon(Icons.privacy_tip_outlined),
          ),
          IconButton(
            onPressed: _showShoppingList,
            tooltip: 'Lista de compras',
            icon: Badge(
              isLabelVisible: _shoppingItems.isNotEmpty,
              label: Text('${_shoppingItems.length}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          if (authEnabled) const AuthAccountButton(),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                const Text(
                  'Compara antes\nde comprar.',
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Compara alimentos, bebidas, hogar, limpieza, electrónica y más productos publicados por tiendas reales.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                SearchBar(
                  controller: _controller,
                  hintText: 'Busca leche, arroz, huevo...',
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    IconButton(
                      onPressed: _loading ? null : _search,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final query in ['coca', 'leche', 'arroz', 'huevo'])
                      ActionChip(
                        label: Text(query),
                        onPressed: _loading ? null : () => _search(query),
                      ),
                  ],
                ),
                if (_categories.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('Todo'),
                            selected: _selectedCategory == null,
                            onSelected: (_) {
                              setState(() => _selectedCategory = null);
                              _search();
                            },
                          ),
                        ),
                        for (final category in _categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label:
                                  Text('${category.name} (${category.count})'),
                              selected: _selectedCategory == category.name,
                              onSelected: (_) {
                                setState(
                                  () => _selectedCategory = category.name,
                                );
                                _search();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _locating ? null : _useLocation,
                      icon: _locating
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                      label: Text(
                        _latitude == null
                            ? 'Usar mi ubicación'
                            : 'Ubicación activa',
                      ),
                    ),
                    if (_latitude != null)
                      ActionChip(
                        avatar: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Quitar ubicación'),
                        onPressed: _clearLocation,
                      ),
                    DropdownButton<double>(
                      value: _radiusKm,
                      items: [2, 5, 10, 20]
                          .map(
                            (radius) => DropdownMenuItem(
                              value: radius.toDouble(),
                              child: Text('$radius km'),
                            ),
                          )
                          .toList(),
                      onChanged: _latitude == null
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _radiusKm = value);
                              _search();
                            },
                    ),
                    DropdownButton<String>(
                      value: _orderBy,
                      items: const [
                        DropdownMenuItem(
                          value: 'price',
                          child: Text('Menor precio'),
                        ),
                        DropdownMenuItem(
                          value: 'distance',
                          child: Text('Más cerca'),
                        ),
                      ],
                      onChanged: _latitude == null
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _orderBy = value);
                              _search();
                            },
                    ),
                  ],
                ),
                if (_latitude != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Buscando dentro de ${_radiusKm.toStringAsFixed(0)} km. '
                    'Tu ubicación se usa solo para esta consulta. '
                    '$_nearbyBranches sucursales verificadas cerca.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (_usingDemo)
                  const _Notice(
                    icon: Icons.science_outlined,
                    text:
                        'Vista demo. Al desplegar la API, esta pantalla mostrará datos en vivo.',
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  _Notice(icon: Icons.info_outline, text: _error!),
                ],
                if (_usingCache) ...[
                  const SizedBox(height: 10),
                  const _Notice(
                    icon: Icons.offline_bolt_outlined,
                    text:
                        'Sin conexión estable. Mostrando la última consulta guardada.',
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      'Mejores precios',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${groups.length} productos · ${_results.length} precios',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_results.isEmpty)
                  const _EmptyState()
                else
                  for (final group in groups) ...[
                    ProductComparisonCard(
                      group: group,
                      onAdd: () => _addToShoppingList(group),
                    ),
                    const SizedBox(height: 12),
                  ],
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!_loading && _hasMore && !_usingDemo)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                        child: Text('Desliza para mostrar más productos')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PrivacyDialog extends StatelessWidget {
  const PrivacyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Privacidad en Tiago Market'),
      content: const SingleChildScrollView(
        child: Text(
          'Usamos tu cuenta de Google para identificar tu sesión. '
          'Tu ubicación solo se solicita cuando eliges buscar tiendas cercanas '
          'y se envía para calcular distancias. No vendemos tus datos. '
          'Los precios son observaciones de tiendas y pueden cambiar.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({required this.api, super.key});

  final MarketApi api;

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.api.sendFeedback(_controller.text);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo enviar el comentario.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ayúdanos a mejorar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Cuéntanos qué funcionó y qué deberíamos corregir.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Tu comentario...',
            ),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              _sending || _controller.text.trim().length < 3 ? null : _send,
          child: Text(_sending ? 'Enviando...' : 'Enviar'),
        ),
      ],
    );
  }
}

class ProductComparisonGroup {
  const ProductComparisonGroup({
    required this.comparisonKey,
    required this.productName,
    required this.prices,
  });

  final String comparisonKey;
  final String productName;
  final List<PriceResult> prices;

  PriceResult get best => prices.first;
}

List<ProductComparisonGroup> groupPriceResults(List<PriceResult> results) {
  final grouped = <String, List<PriceResult>>{};
  for (final result in results) {
    final key = result.comparisonKey;
    grouped.putIfAbsent(key, () => []).add(result);
  }

  return grouped.entries.map((entry) {
    final prices = [...entry.value]..sort((a, b) => a.price.compareTo(b.price));
    return ProductComparisonGroup(
      comparisonKey: entry.key,
      productName: prices.first.productName,
      prices: prices,
    );
  }).toList()
    ..sort((a, b) => a.best.price.compareTo(b.best.price));
}

class ProductComparisonCard extends StatelessWidget {
  const ProductComparisonCard(
      {required this.group, required this.onAdd, super.key});

  final ProductComparisonGroup group;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final best = group.best;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: 58,
            child: best.imageUrl == null
                ? _ProductImageFallback(storeName: best.storeName)
                : Image.network(
                    best.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _ProductImageFallback(storeName: best.storeName),
                  ),
          ),
        ),
        title: Text(
          group.productName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${best.presentation ?? "Presentación por verificar"} · ${group.prices.length} ${group.prices.length == 1 ? "precio" : "precios"} · desde \$${best.price.toStringAsFixed(2)}',
        ),
        trailing: IconButton(
          onPressed: onAdd,
          tooltip: 'Agregar a mi lista',
          icon: const Icon(Icons.add_shopping_cart_rounded),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (final price in group.prices) ...[
            PriceCard(result: price),
            if (price != group.prices.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class PriceCard extends StatelessWidget {
  const PriceCard({required this.result, super.key});

  final PriceResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox.square(
                dimension: 76,
                child: result.imageUrl == null
                    ? _ProductImageFallback(storeName: result.storeName)
                    : Image.network(
                        result.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _ProductImageFallback(storeName: result.storeName),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.storeName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    result.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (result.branchName != null)
                    Text(
                      'Sucursal: ${result.branchName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    )
                  else
                    const Text(
                      'Precio publicado online',
                      style: TextStyle(fontSize: 12),
                    ),
                  Text(
                    result.observationLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (result.distanceKm != null)
                    Text(
                      '${result.distanceKm!.toStringAsFixed(1)} km de distancia',
                      style: const TextStyle(
                        color: Color(0xFF006C51),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (result.storeProductUrl != null)
                        TextButton.icon(
                          onPressed: () => _openUrl(result.storeProductUrl!),
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          label: const Text('Ver en la tienda'),
                        ),
                    ],
                  ),
                  if (result.freshness == 'old') ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Este precio puede estar desactualizado.',
                      style: TextStyle(
                        color: Color(0xFF9A3412),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '\$${result.price.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Color(0xFF006C51),
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ProductImageFallback extends StatelessWidget {
  const _ProductImageFallback({required this.storeName});

  final String storeName;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE2F3EB),
      child: Center(
        child: Text(
          storeName.substring(0, 1),
          style: const TextStyle(
            color: Color(0xFF006C51),
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 44),
          SizedBox(height: 10),
          Text('No encontramos precios para esa búsqueda.'),
        ],
      ),
    );
  }
}

class MarketApi {
  bool usedCache = false;

  Future<List<PriceResult>> compare(
    String query, {
    double? latitude,
    double? longitude,
    double radiusKm = 10,
    String orderBy = 'price',
    int page = 1,
    String? category,
  }) async {
    if (apiBaseUrl.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return demoPricesFor(query);
    }

    final uri = Uri.parse('$apiBaseUrl/api/v1/compare').replace(
      queryParameters: {
        'query': query,
        'limit': '100',
        'page': page.toString(),
        if (query.trim().isNotEmpty) 'query': query,
        if (category != null) 'category': category,
        if (latitude != null && longitude != null) ...{
          'lat': latitude.toString(),
          'lng': longitude.toString(),
          'radius_km': radiusKm.toString(),
          'order_by': orderBy,
        },
      },
    );
    final cacheKey = 'price-cache:${uri.toString()}';
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('API respondió ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];
      final results = data
          .map((item) => PriceResult.fromJson(item as Map<String, dynamic>))
          .toList();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        cacheKey,
        jsonEncode(results.map((result) => result.toJson()).toList()),
      );
      usedCache = false;
      return results;
    } catch (_) {
      final preferences = await SharedPreferences.getInstance();
      final cached = preferences.getString(cacheKey);
      if (cached == null) rethrow;
      usedCache = true;
      return (jsonDecode(cached) as List<dynamic>)
          .map((item) => PriceResult.fromJson(item as Map<String, dynamic>))
          .toList();
    }
  }

  Future<List<ProductCategory>> categories() async {
    if (apiBaseUrl.isEmpty) return const [];
    final response = await http
        .get(Uri.parse('$apiBaseUrl/api/v1/categories'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('API respondió ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['data'] as List<dynamic>? ?? [])
        .map((item) => ProductCategory.fromJson(item as Map<String, dynamic>))
        .where((category) => category.count > 0)
        .toList();
  }

  Future<void> sendFeedback(String message) async {
    if (apiBaseUrl.isEmpty) throw Exception('API no configurada');
    final userId =
        authEnabled ? Supabase.instance.client.auth.currentUser?.id : null;
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/api/v1/feedback'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': message.trim(),
            'user_id': userId,
            'context': {'platform': 'flutter', 'app_version': '0.2.0'},
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 201) {
      throw Exception('API respondió ${response.statusCode}');
    }
  }

  Future<int> nearbyBranchCount(
    double latitude,
    double longitude,
    double radiusKm,
  ) async {
    if (apiBaseUrl.isEmpty) return 0;
    final uri = Uri.parse('$apiBaseUrl/api/v1/branches').replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
        'radius_km': radiusKm.toString(),
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return 0;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final meta = body['meta'] as Map<String, dynamic>? ?? {};
    return (meta['total'] as num?)?.toInt() ?? 0;
  }
}

class ProductCategory {
  const ProductCategory({required this.name, required this.count});

  factory ProductCategory.fromJson(Map<String, dynamic> json) =>
      ProductCategory(
        name: json['name'] as String? ?? 'Otros',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  final String name;
  final int count;
}

class PriceResult {
  const PriceResult({
    required this.storeName,
    required this.productName,
    this.normalizedName = '',
    this.branchName,
    required this.price,
    required this.capturedAt,
    this.source = 'direct',
    this.freshness = 'fresh',
    this.daysOld = 0,
    this.distanceKm,
    this.storeProductUrl,
    this.imageUrl,
    this.presentation,
    this.category,
  });

  factory PriceResult.fromJson(Map<String, dynamic> json) {
    return PriceResult(
      storeName: json['store_name'] as String? ?? 'Tienda',
      productName: json['product_name'] as String? ?? 'Producto',
      normalizedName: json['normalized_name'] as String? ??
          json['product_name'] as String? ??
          'producto',
      branchName: json['branch_name'] as String?,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      source: json['source'] as String? ?? 'fuente no informada',
      capturedAt: json['captured_at'] as String? ?? '',
      freshness: json['freshness'] as String? ?? 'old',
      daysOld: (json['days_old'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      storeProductUrl: json['store_product_url'] as String?,
      imageUrl: json['image_url'] as String?,
      presentation: json['presentation'] as String?,
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'store_name': storeName,
        'product_name': productName,
        'normalized_name': normalizedName,
        'branch_name': branchName,
        'price': price,
        'source': source,
        'captured_at': capturedAt,
        'freshness': freshness,
        'days_old': daysOld,
        'distance_km': distanceKm,
        'store_product_url': storeProductUrl,
        'image_url': imageUrl,
        'presentation': presentation,
        'category': category,
      };

  final String storeName;
  final String productName;
  final String normalizedName;
  final String? branchName;
  final double price;
  final String source;
  final String capturedAt;
  final String freshness;
  final int daysOld;
  final double? distanceKm;
  final String? storeProductUrl;
  final String? imageUrl;
  final String? presentation;
  final String? category;

  String get comparisonKey {
    final name = normalizedName.isEmpty
        ? productName.toLowerCase().trim()
        : normalizedName.toLowerCase().trim();
    final pack = _normalizedPresentation(presentation ?? name);
    final baseName = name
        .replaceAll(
          RegExp(
            r'\b\d+\s*(?:pza|pack|paquete)?\s*(?:de|x)\s*\d+(?:[.,]\d+)?\s*(?:ml|l|g|kg)\b',
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'\b\d+(?:[.,]\d+)?\s*(?:ml|l|g|kg|pza|rollos?|gal)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return pack == null ? baseName : '$baseName|$pack';
  }

  String get observationLabel {
    final age = daysOld == 1 ? 'hace 1 día' : 'hace $daysOld días';
    return 'Actualizado $age · fuente directa';
  }
}

String? _normalizedPresentation(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll(RegExp(r'kilogramos?|kilos?'), 'kg')
      .replaceAll(RegExp(r'gramos?'), 'g')
      .replaceAll(RegExp(r'litros?|lts?'), 'l')
      .replaceAll(RegExp(r'mililitros?'), 'ml')
      .replaceAll(RegExp(r'piezas?|pzas?'), 'pza');
  final multipack = RegExp(
    r'\b(\d+)\s*(?:pza|pack|paquete)?\s*(?:de|x)\s*(\d+(?:[.,]\d+)?)\s*(ml|l|g|kg)\b',
  ).firstMatch(normalized);
  if (multipack != null) {
    final count = int.tryParse(multipack.group(1)!);
    final amount = double.tryParse(multipack.group(2)!.replaceAll(',', '.'));
    final unit = multipack.group(3);
    if (count != null && amount != null && unit != null) {
      final canonicalAmount =
          unit == 'kg' || unit == 'l' ? amount * 1000 : amount;
      final canonicalUnit = unit == 'kg'
          ? 'g'
          : unit == 'l'
              ? 'ml'
              : unit;
      return '${count}x$canonicalAmount:$canonicalUnit';
    }
  }
  final match = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s*(ml|l|g|kg|pza|rollos?|gal)\b',
  ).firstMatch(normalized);
  if (match == null) return null;
  final amount = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  final unit = match.group(2);
  if (amount == null || unit == null) return null;
  if (unit == 'kg') return '${amount * 1000}:g';
  if (unit == 'l') return '${amount * 1000}:ml';
  if (unit == 'gal') return '${(amount * 3785.41).round()}:ml';
  if (unit.startsWith('rollo')) return '$amount:rollos';
  return '$amount:$unit';
}

class ShoppingItem {
  const ShoppingItem({
    required this.comparisonKey,
    required this.productName,
    required this.quantity,
    required this.prices,
  });

  factory ShoppingItem.fromJson(Map<String, dynamic> json) => ShoppingItem(
        comparisonKey: json['comparison_key'] as String,
        productName: json['product_name'] as String,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        prices: (json['prices'] as List<dynamic>? ?? [])
            .map((item) => PriceResult.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final String comparisonKey;
  final String productName;
  final int quantity;
  final List<PriceResult> prices;

  ShoppingItem copyWith({int? quantity, List<PriceResult>? prices}) =>
      ShoppingItem(
        comparisonKey: comparisonKey,
        productName: productName,
        quantity: quantity ?? this.quantity,
        prices: prices ?? this.prices,
      );

  Map<String, dynamic> toJson() => {
        'comparison_key': comparisonKey,
        'product_name': productName,
        'quantity': quantity,
        'prices': prices.map((price) => price.toJson()).toList(),
      };
}

class ShoppingListStorage {
  static const _key = 'shopping-list-v1';

  static Future<List<ShoppingItem>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_key);
    if (value == null) return const [];
    try {
      return (jsonDecode(value) as List<dynamic>)
          .map((item) => ShoppingItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<ShoppingItem> items) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }
}

class StoreCartTotal {
  const StoreCartTotal({
    required this.storeName,
    required this.total,
    required this.coveredItems,
  });

  final String storeName;
  final double total;
  final int coveredItems;
}

List<StoreCartTotal> calculateStoreTotals(List<ShoppingItem> items) {
  final totals = <String, double>{};
  final coverage = <String, int>{};
  for (final item in items) {
    final bestByStore = <String, double>{};
    for (final price in item.prices) {
      final current = bestByStore[price.storeName];
      if (current == null || price.price < current) {
        bestByStore[price.storeName] = price.price;
      }
    }
    for (final entry in bestByStore.entries) {
      totals[entry.key] =
          (totals[entry.key] ?? 0) + entry.value * item.quantity;
      coverage[entry.key] = (coverage[entry.key] ?? 0) + 1;
    }
  }
  return totals.entries
      .map(
        (entry) => StoreCartTotal(
          storeName: entry.key,
          total: entry.value,
          coveredItems: coverage[entry.key] ?? 0,
        ),
      )
      .toList()
    ..sort((a, b) {
      final coverageOrder = b.coveredItems.compareTo(a.coveredItems);
      return coverageOrder != 0 ? coverageOrder : a.total.compareTo(b.total);
    });
}

class ShoppingListSheet extends StatefulWidget {
  const ShoppingListSheet({
    required this.items,
    required this.onQuantityChanged,
    super.key,
  });

  final List<ShoppingItem> items;
  final Future<void> Function(ShoppingItem item, int quantity)
      onQuantityChanged;

  @override
  State<ShoppingListSheet> createState() => _ShoppingListSheetState();
}

class _ShoppingListSheetState extends State<ShoppingListSheet> {
  late final List<ShoppingItem> _items = [...widget.items];

  Future<void> _changeQuantity(ShoppingItem item, int quantity) async {
    await widget.onQuantityChanged(item, quantity);
    if (!mounted) return;
    setState(() {
      final index = _items.indexWhere(
        (value) => value.comparisonKey == item.comparisonKey,
      );
      if (index < 0) return;
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index] = item.copyWith(quantity: quantity);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final totals = calculateStoreTotals(_items);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: ListView(
            children: [
              Text(
                'Mi lista de compras',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Los totales usan los últimos precios guardados al agregar cada producto.',
              ),
              const SizedBox(height: 18),
              if (_items.isEmpty)
                const _EmptyState()
              else
                for (final item in _items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.productName),
                    subtitle: Text('${item.prices.length} precios disponibles'),
                    leading: IconButton(
                      onPressed: () => _changeQuantity(item, item.quantity - 1),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${item.quantity}'),
                        IconButton(
                          onPressed: () =>
                              _changeQuantity(item, item.quantity + 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
              if (totals.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  'Estimación por tienda',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                for (final total in totals)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(total.storeName),
                    subtitle: Text(
                      '${total.coveredItems} de ${_items.length} productos disponibles',
                    ),
                    trailing: Text(
                      '\$${total.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF006C51),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const demoPrices = [
  PriceResult(
    storeName: 'Arteli online',
    productName: 'Refresco Coca-Cola sin Azúcar 600ml',
    price: 15,
    source: 'arteli-direct',
    capturedAt: '2026-06-13T02:57:31.493Z',
    imageUrl:
        'https://arteli.vteximg.com.br/arquivos/ids/201431/7501055320639_00.jpg?v=638576437520930000',
    storeProductUrl:
        'https://www.arteli.com.mx/refresco-coca-cola-sin-azucar-600ml-3062158/p',
  ),
  PriceResult(
    storeName: 'Smart & Final México online',
    productName: 'Soda Coca Cola light 600 ml',
    price: 24,
    source: 'smart-final-direct',
    capturedAt: '2026-06-13T02:57:29.956Z',
    imageUrl:
        'https://www.smartnfinal.com.mx/wp-content/uploads/2021/07/91024-Soda-sabor-cola-ligera-Coca-Cola-600-ml.jpg',
    storeProductUrl:
        'https://www.smartnfinal.com.mx/tienda/aguas-y-bebidas/soda-sabor-cola-ligera-coca-cola/',
  ),
];

List<PriceResult> demoPricesFor(String query) {
  final normalized = query.toLowerCase();
  if (normalized.contains('leche')) return demoMilkPrices;
  if (normalized.contains('arroz')) return demoRicePrices;
  if (normalized.contains('huevo')) return demoEggPrices;
  return demoPrices;
}

const demoMilkPrices = [
  PriceResult(
    storeName: 'Smart & Final México online',
    productName: 'Leche entera Santa Clara 1 l',
    price: 38,
    source: 'smart-final-direct',
    capturedAt: '2026-06-13T02:57:29.956Z',
    imageUrl:
        'https://www.smartnfinal.com.mx/wp-content/uploads/2022/11/7951-Leche-entera-Santa-Clara-1-l.jpg',
    storeProductUrl:
        'https://www.smartnfinal.com.mx/tienda/desayuno-y-reposteria/leche-entera-santa-clara-2/',
  ),
];

const demoRicePrices = [
  PriceResult(
    storeName: 'Arteli online',
    productName: 'Arroz SOS integral 1Kg',
    price: 16.5,
    source: 'arteli-direct',
    capturedAt: '2026-06-13T02:57:31.493Z',
    imageUrl:
        'https://arteli.vteximg.com.br/arquivos/ids/214145/7501111105095_00.jpg?v=638576494379770000',
    storeProductUrl:
        'https://www.arteli.com.mx/arroz-sos-integral-1kg-3008400/p',
  ),
];

const demoEggPrices = [
  PriceResult(
    storeName: 'Arteli online',
    productName: 'Huevo San Juan Blanco 12 Piezas',
    price: 28.5,
    source: 'arteli-direct',
    capturedAt: '2026-06-13T02:57:31.493Z',
    imageUrl:
        'https://arteli.vteximg.com.br/arquivos/ids/256360/7503000555011_00.jpg?v=638635805372130000',
    storeProductUrl:
        'https://www.arteli.com.mx/huevo-san-juan-blanco-12-piezas-3101213/p',
  ),
];
