import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'resilient_middleware_flutter_method_channel.dart';

abstract class ResilientMiddlewareFlutterPlatform extends PlatformInterface {
  /// Constructs a ResilientMiddlewareFlutterPlatform.
  ResilientMiddlewareFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static ResilientMiddlewareFlutterPlatform _instance = MethodChannelResilientMiddlewareFlutter();

  /// The default instance of [ResilientMiddlewareFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelResilientMiddlewareFlutter].
  static ResilientMiddlewareFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ResilientMiddlewareFlutterPlatform] when
  /// they register themselves.
  static set instance(ResilientMiddlewareFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
