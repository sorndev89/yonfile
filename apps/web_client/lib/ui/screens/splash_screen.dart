import 'package:flutter/material.dart';

import '../../core/theme/yon_theme.dart';

class YonFileSplashScreen extends StatelessWidget {
  const YonFileSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10192D),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.12),
            radius: 0.9,
            colors: [Color(0xFF1C2941), Color(0xFF10192D)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/branding/yonfile-mark.png',
                width: 116,
                height: 116,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 22),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                  children: [
                    TextSpan(
                      text: 'Yon',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextSpan(
                      text: 'File',
                      style: TextStyle(color: YonTheme.yonOrange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'ສົ່ງໄຟລ໌ລະຫວ່າງອຸປະກອນ ງ່າຍ ແລະ ໄວ',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFAFBBD0), fontSize: 13),
              ),
              const SizedBox(height: 34),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(YonTheme.yonOrange),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
