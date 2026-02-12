import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application configuration loaded from .env file
class AppConfig {
  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';

  static String get smsGatewayNumber =>
      dotenv.env['SMS_GATEWAY_NUMBER'] ?? '+22670000000';

  static int get pinLength =>
      int.tryParse(dotenv.env['PIN_LENGTH'] ?? '6') ?? 6;
}
