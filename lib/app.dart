import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/pos_provider.dart';
import 'providers/server_provider.dart';
import 'providers/admin_provider.dart';
import 'ui/screens/web_pos_screen.dart';

class MasterDrinksApp extends StatelessWidget {
  const MasterDrinksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => PosProvider()),
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
      ],
      child: MaterialApp(
        title: 'MasterDrinks POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const WebPosScreen(),
      ),
    );
  }
}
