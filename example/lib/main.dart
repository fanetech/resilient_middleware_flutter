import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:resilient_middleware_flutter/resilient_middleware.dart';
import 'config/app_config.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Initialize Resilient API Service with middleware
  await ResilientApiService.initialize(
    baseUrl: AppConfig.apiBaseUrl,
    smsGateway: AppConfig.smsGatewayNumber,
    enableSMS: true,
    strategy: ResilienceStrategy.balanced,
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
      title: 'Resilient Banking',
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
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
