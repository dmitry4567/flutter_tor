import 'package:flutter/material.dart';

import 'pages/tor_home_page.dart';

class TorDemoApp extends StatelessWidget {
  const TorDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tor_ios demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: const TorHomePage(),
    );
  }
}
