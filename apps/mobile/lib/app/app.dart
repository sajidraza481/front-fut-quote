import 'package:flutter/material.dart';
import 'package:frontfut/core/env.dart';

class FrontfutApp extends StatelessWidget {
  const new({required this.flavor, super.key});

  final Flavor flavor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frontfut',
      debugShowCheckedModeBanner: flavor == Flavor.dev,
      home: const Scaffold(body: Center(child: Text('Frontfut'))),
    );
  }
}
