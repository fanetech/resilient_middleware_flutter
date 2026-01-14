import 'package:flutter_test/flutter_test.dart';
import 'package:resilient_middleware_flutter/resilient_middleware_flutter.dart';
import 'package:resilient_middleware_flutter/resilient_middleware_flutter_platform_interface.dart';
import 'package:resilient_middleware_flutter/resilient_middleware_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockResilientMiddlewareFlutterPlatform
    with MockPlatformInterfaceMixin
    implements ResilientMiddlewareFlutterPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ResilientMiddlewareFlutterPlatform initialPlatform = ResilientMiddlewareFlutterPlatform.instance;

  test('$MethodChannelResilientMiddlewareFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelResilientMiddlewareFlutter>());
  });

  test('getPlatformVersion', () async {
    ResilientMiddlewareFlutter resilientMiddlewareFlutterPlugin = ResilientMiddlewareFlutter();
    MockResilientMiddlewareFlutterPlatform fakePlatform = MockResilientMiddlewareFlutterPlatform();
    ResilientMiddlewareFlutterPlatform.instance = fakePlatform;

    expect(await resilientMiddlewareFlutterPlugin.getPlatformVersion(), '42');
  });
}
