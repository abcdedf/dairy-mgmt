// lib/pages/splash_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/auth_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {

  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _anim  = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 900));
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _slide = Tween<double>(begin: 24, end: 0).animate(
        CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
    _boot();
  }

  Future<void> _boot() async {
    final results = await Future.wait([
      AuthService.instance.tryAutoLogin(),
      Future.delayed(const Duration(milliseconds: 1600)),
    ]);
    if (!mounted) return;
    Get.offAllNamed((results[0] as bool) ? '/home' : '/login');
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF1B4F72),
    body: Center(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(0, _slide.value),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.water_drop_outlined,
                    size: 54, color: Colors.white),
              ),
              const SizedBox(height: 28),
              const Text('Dairy Management',
                  style: TextStyle(color: Colors.white, fontSize: 28,
                      fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              Text('Production · Sales · Stock',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
              const SizedBox(height: 56),
              SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5,
                      color: Colors.white.withValues(alpha: 0.45))),
            ]),
          ),
        ),
      ),
    ),
  );
}
