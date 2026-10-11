import 'package:flutter/material.dart';

/// Placeholder until login → center select → member home are built.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('박스인')),
      body: const Center(child: Text('박스인 v0.1 — 준비 중')),
    );
  }
}
