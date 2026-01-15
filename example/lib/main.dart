import 'package:flutter/material.dart';
import 'package:resilient_middleware_flutter/resilient_middleware.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Resilient Middleware
  await ResilientMiddleware.initialize(
    smsGateway: '+22670000000', // Demo SMS gateway number
    enableSMS: true,
    strategy: ResilienceStrategy.balanced,
    timeout: const Duration(seconds: 30),
    maxQueueSize: 1000,
  );

  // Enable logging
  Logger.setEnabled(true);
  Logger.setMinLevel(LogLevel.debug);

  runApp(const BankingDemoApp());
}

class BankingDemoApp extends StatelessWidget {
  const BankingDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resilient Banking Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
