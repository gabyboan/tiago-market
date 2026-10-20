import 'package:flutter/material.dart';

/// Keeps the navigator mounted while presenting the brand on a cold start.
/// Resuming the app preserves this state and never restarts the introduction.
class StartupSplash extends StatefulWidget {
  const StartupSplash({required this.child, super.key});

  final Widget child;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _brandOpacity;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .25, curve: Curves.easeOut),
    );
    _brandOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.3, .6, curve: Curves.easeOut),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _finished = true);
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Initialize the usual entry flow during the introduction, without
        // exposing its controls or recreating it when the splash finishes.
        Offstage(offstage: !_finished, child: widget.child),
        if (!_finished)
          Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: reduceMotion
                          ? const AlwaysStoppedAnimation(1.0)
                          : _logoOpacity,
                      child: const CircleAvatar(
                        radius: 56,
                        backgroundColor: Color(0xFF006C51),
                        foregroundColor: Colors.white,
                        child: Icon(Icons.shopping_basket, size: 62),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeTransition(
                      opacity: reduceMotion
                          ? const AlwaysStoppedAnimation(1.0)
                          : _brandOpacity,
                      child: const Text(
                        'Tiago Market',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF006C51),
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 120,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) => LinearProgressIndicator(
                          value: _controller.value,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(3),
                          semanticsLabel: 'Iniciando Tiago Market',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
