import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'resilient_middleware_flutter_platform_interface.dart';

/// An implementation of [ResilientMiddlewareFlutterPlatform] that uses method channels.
class MethodChannelResilientMiddlewareFlutter extends ResilientMiddlewareFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('resilient_middleware_flutter');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
