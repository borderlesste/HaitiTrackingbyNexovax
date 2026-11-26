import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/guest.dart';
import '../../core/theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Idiomas ofrecidos en la bienvenida. Por ahora solo se traduce esta pantalla.
enum WelcomeLang { es, fr, ht, en }

class _WelcomeTexts {
  const _WelcomeTexts({required this.slides, required this.start, required this.haveAccount, required this.signIn, required this.explore});
  final List<String> slides;
  final String start;
  final String haveAccount;
  final String signIn;
  final String explore;
}

const _texts = <WelcomeLang, _WelcomeTexts>{
  WelcomeLang.es: _WelcomeTexts(
    slides: [
      'El mapa colaborativo\nde direcciones de Haití',
      'Completa misiones en el mapa\ny gana recompensas',
      'Ayuda a que cada dirección\nde Haití se pueda encontrar',
    ],
    start: 'Comenzar',
    haveAccount: '¿Ya tienes una cuenta?',
    signIn: 'Iniciar sesión',
    explore: 'Explorar sin registrarme',
  ),
  WelcomeLang.fr: _WelcomeTexts(
    slides: [
      'La carte collaborative\ndes adresses d’Haïti',
      'Accomplissez des missions\net gagnez des récompenses',
      'Aidez à rendre chaque adresse\nd’Haïti facile à trouver',
    ],
    start: 'Commencer',
    haveAccount: 'Vous avez déjà un compte ?',
    signIn: 'Se connecter',
    explore: 'Explorer sans compte',
  ),
  WelcomeLang.ht: _WelcomeTexts(
    slides: [
      'Kat kolaboratif\nadrès Ayiti yo',
      'Fè misyon sou kat la\nepi genyen rekonpans',
      'Ede chak adrès an Ayiti\nfasil pou jwenn',
    ],
    start: 'Kòmanse',
    haveAccount: 'Ou gen yon kont deja?',
    signIn: 'Konekte',
    explore: 'Gade san kont',
  ),
  WelcomeLang.en: _WelcomeTexts(
    slides: [
      'The collaborative map\nof Haiti’s addresses',
      'Complete missions on the map\nand earn rewards',
      'Help make every address\nin Haiti easy to find',
    ],
    start: 'Get started',
    haveAccount: 'Already have an account?',
    signIn: 'Sign in',
    explore: 'Explore without an account',
  ),
};

const _langPrefKey = 'welcome_lang';

/// Pantalla de bienvenida: logo, lema en carrusel, panorámica y accesos a registro o inicio de sesión.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  Timer? _autoplay;
  int _page = 0;
  WelcomeLang _lang = WelcomeLang.es;

  @override
  void initState() {
    super.initState();
    _loadLang();
    _autoplay = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_pages.hasClients) return;
      final next = (_page + 1) % 3;
      _pages.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  Future<void> _loadLang() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_langPrefKey);
    final lang = WelcomeLang.values.where((l) => l.name == saved).firstOrNull;
    if (lang != null && mounted) setState(() => _lang = lang);
  }

  Future<void> _setLang(WelcomeLang lang) async {
    setState(() => _lang = lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langPrefKey, lang.name);
  }

  @override
  void dispose() {
    _autoplay?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _openLogin({required bool registering}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => registering ? const RegisterScreen() : const LoginScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = _texts[_lang]!;
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5B9BEA), Color(0xFFDCEBFC), Colors.white, Colors.white],
            stops: [0, .28, .55, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _LanguagePill(value: _lang, onChanged: _setLang),
                ),
              ),
              SizedBox(height: height * .02),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height * .26),
                  child: Image.asset('assets/images/logo.png', fit: BoxFit.contain, semanticLabel: 'Haiti Tracking by Nexovax'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: PageView.builder(
                  controller: _pages,
                  itemCount: t.slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => Center(
                    child: Text(
                      t.slides[i],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 21, height: 1.25, fontWeight: FontWeight.w600, color: HtColors.navy),
                    ),
                  ),
                ),
              ),
              const Expanded(child: _Panorama()),
              const SizedBox(height: 8),
              _Dots(count: t.slides.length, active: _page),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FilledButton(
                  onPressed: () => _openLogin(registering: true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder(),
                    elevation: 3,
                    shadowColor: HtColors.blue.withValues(alpha: .4),
                    textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  child: Text(t.start),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: OutlinedButton.icon(
                  onPressed: () => Guest.set(true),
                  icon: const Icon(Icons.explore_outlined),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                  label: Text(t.explore),
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(t.haveAccount, style: const TextStyle(fontSize: 15, color: HtColors.navy)),
                  TextButton(
                    onPressed: () => _openLogin(registering: false),
                    child: Text(t.signIn, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Foto de la costa que se funde con el fondo arriba y abajo.
class _Panorama extends StatelessWidget {
  const _Panorama();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
        stops: [0, .18, .82, 1],
      ).createShader(rect),
      child: SizedBox.expand(
        child: Image.asset('assets/images/panorama.jpg', fit: BoxFit.cover, alignment: const Alignment(-.2, 0)),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: i == active ? 13 : 11,
            height: i == active ? 13 : 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == active ? HtColors.blue : HtColors.blue.withValues(alpha: .35),
            ),
          ),
      ],
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.value, required this.onChanged});
  final WelcomeLang value;
  final ValueChanged<WelcomeLang> onChanged;

  static const _names = {
    WelcomeLang.es: 'Español',
    WelcomeLang.fr: 'Français',
    WelcomeLang.ht: 'Kreyòl ayisyen',
    WelcomeLang.en: 'English',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<WelcomeLang>(
      initialValue: value,
      onSelected: onChanged,
      tooltip: 'Idioma',
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        for (final l in WelcomeLang.values) PopupMenuItem(value: l, child: Text(_names[l]!)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, color: HtColors.blue, size: 22),
            const SizedBox(width: 6),
            Text(value.name.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: HtColors.navy)),
            const Icon(Icons.arrow_drop_down, color: HtColors.blue),
          ],
        ),
      ),
    );
  }
}
