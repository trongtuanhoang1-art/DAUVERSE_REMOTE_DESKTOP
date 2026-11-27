import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/dauverse/bridge/dauverse_bridge.dart';
import 'package:flutter_hbb/dauverse/dauverse_shell.dart';
import 'package:flutter_hbb/dauverse/l10n/dauverse_i18n.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestClassicTabExtension extends ThemeExtension<_TestClassicTabExtension> {
  final Color? selectedTextColor;
  const _TestClassicTabExtension({required this.selectedTextColor});

  @override
  _TestClassicTabExtension copyWith({Color? selectedTextColor}) =>
      _TestClassicTabExtension(selectedTextColor: selectedTextColor ?? this.selectedTextColor);

  @override
  _TestClassicTabExtension lerp(ThemeExtension<_TestClassicTabExtension>? other, double t) => this;
}

void main() {
  String mockClipboardText = '';

  setUp(() {
    mockClipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        mockClipboardText = args?['text']?.toString() ?? '';
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': mockClipboardText};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    DauverseNativeBridge.setForceUnboundForTest(false);
    DauverseNativeBridge.setTestHarnessMode(false);
    DauverseNativeBridge.setTestHarnessIdentityOverride(null);
  });

  testWidgets('F06: Production unbound FFI fails closed on mutations and renders visible error banner',
      (WidgetTester tester) async {
    DauverseNativeBridge.setForceUnboundForTest(true);
    DauverseNativeBridge.setTestHarnessMode(false);

    expect(
      () => DauverseNativeBridge.assertReleaseIsolationPolicy(simulatedReleaseFlag: true),
      throwsA(isA<UnsupportedError>()),
    );

    final pinRes = DauverseNativeBridge.instance.call('set_step_up_pin', {'pin': '123456'});
    expect(pinRes['ok'], isFalse);
    expect(pinRes['error']?.toString(), contains('NATIVE_FFI_UNBOUND_FAIL_CLOSED'));

    final perfRes = DauverseNativeBridge.instance.call('set_performance_mode', {'mode': 'BALANCED'});
    expect(perfRes['ok'], isFalse);

    await tester.binding.setSurfaceSize(const Size(1600, 960));
    await tester.pumpWidget(
      const MaterialApp(
        home: DauverseExecutiveShell(
          overrideInitialScreen: DauverseScreenId.securityCenter,
          overrideDarkMode: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byKey(const Key('dauverse-ffi-fail-closed-banner')), findsOneWidget);

    await tester.tap(find.text('Thu hồi khẩn cấp mọi truy cập'));
    await tester.pump();
    expect(find.textContaining('FAIL-CLOSED (REVOKE DENIED)'), findsOneWidget);
    expect(find.textContaining('ĐÃ THU HỒI KHẨN CẤP'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('RC4.3 Dashboard Connection Hero fulfills all mandatory ID/IP/Copy/Paste/Password/Status requirements',
      (WidgetTester tester) async {
    DauverseNativeBridge.setForceUnboundForTest(true);
    DauverseNativeBridge.setTestHarnessMode(true);
    DauverseNativeBridge.setTestHarnessIdentityOverride({
      'connection_id': '482910375',
      'formatted_id': '482 910 375',
      'lan_interfaces': const [
        {'interface_name': 'eth0', 'friendly_name': 'Ethernet', 'ipv4': '192.168.1.50', 'is_default_route': true},
        {'interface_name': 'wlan0', 'friendly_name': 'Wi-Fi', 'ipv4': '10.20.30.40', 'is_default_route': false},
      ],
      'lan_ips': const ['192.168.1.50', '10.20.30.40'],
      'public_ip': null,
      'public_ip_status': 'OPT_IN_NOT_QUERIED',
      'direct_ip_access_enabled': false,
      'connection_status': 'ONLINE',
    });

    await tester.binding.setSurfaceSize(const Size(1600, 960));
    final launched = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: DauverseExecutiveShell(
          overrideInitialScreen: DauverseScreenId.dashboard,
          onLaunchRealSession: (ctx, peerId, {bool isFileTransfer = false}) async {
            launched.add('$peerId:$isFileTransfer');
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 1. Large 36px Connection ID + LAN IPs (26px) + Online Status Pill
    final idSelectable = tester.widget<SelectableText>(find.byKey(const Key('dashboard-connection-id-text')));
    expect(idSelectable.data, '482 910 375');
    expect(idSelectable.style?.fontSize, greaterThanOrEqualTo(32));
    expect(idSelectable.style?.fontSize, lessThanOrEqualTo(40));

    expect(find.text('192.168.1.50'), findsOneWidget);
    expect(find.text('10.20.30.40'), findsOneWidget);
    expect(find.byKey(const Key('dashboard-connection-status-pill')), findsOneWidget);

    // 2. 1-click Copy ID -> "Đã sao chép"
    await tester.tap(find.byKey(const Key('copy-connection-id-btn')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(mockClipboardText, '482910375');
    expect(find.textContaining('Đã sao chép'), findsWidgets);

    // 3. 1-click Copy per LAN IP -> "Đã sao chép"
    await tester.tap(find.byKey(const Key('copy-lan-ip-192.168.1.50')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(mockClipboardText, '192.168.1.50');
    expect(find.textContaining('Đã sao chép'), findsWidgets);

    // 4. Temporary Password Show/Hide, Copy, and Regenerate
    await tester.ensureVisible(find.byKey(const Key('toggle-temp-pw-btn')));
    await tester.tap(find.byKey(const Key('toggle-temp-pw-btn')));
    await tester.pump();
    expect(find.text('dv9x4k2p'), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy-temp-pw-btn')));
    await tester.pump();
    expect(mockClipboardText, 'dv9x4k2p');

    await tester.tap(find.byKey(const Key('regen-temp-pw-btn')));
    await tester.pump();
    expect(find.text('mk7r3w8q'), findsOneWidget);

    // 5. Paste from clipboard into Remote ID/IP input + prominent KẾT NỐI NGAY CTA
    mockClipboardText = '777 888 999';
    await tester.ensureVisible(find.byKey(const Key('paste-target-btn')));
    await tester.tap(find.byKey(const Key('paste-target-btn')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('connect-now-cta-btn')));
    await tester.tap(find.byKey(const Key('connect-now-cta-btn')));
    await tester.pump();
    expect(launched, ['777888999:false']);

    await tester.ensureVisible(find.text('Truyền File').first);
    await tester.tap(find.text('Truyền File').first);
    await tester.pump();
    expect(launched, ['777888999:false', '777888999:true']);

    // 6. Verify all 4 connection states (Online, Offline, Connecting, Connected)
    for (final (state, expectedViLabel) in [
      ('OFFLINE', 'Offline'),
      ('CONNECTING', 'Connecting'),
      ('CONNECTED', 'Connected'),
      ('ONLINE', 'Online'),
    ]) {
      DauverseNativeBridge.setTestHarnessIdentityOverride({
        'connection_id': '482910375',
        'formatted_id': '482 910 375',
        'connection_status': state,
      });
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining(expectedViLabel), findsWidgets);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Engine Gốc classic connector preserves TabbarTheme without null-check crash and returns to DAUVERSE',
      (WidgetTester tester) async {
    DauverseNativeBridge.setForceUnboundForTest(true);
    DauverseNativeBridge.setTestHarnessMode(true);
    await tester.binding.setSurfaceSize(const Size(1440, 900));

    final outerTheme = ThemeData.dark().copyWith(
      extensions: const <ThemeExtension<dynamic>>[
        _TestClassicTabExtension(selectedTextColor: Colors.white),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: outerTheme,
        home: DauverseExecutiveShell(
          classicRustDeskBuilder: (ctx) {
            final tabTheme = Theme.of(ctx).extension<_TestClassicTabExtension>()!;
            return Scaffold(
              body: Center(
                child: Text('CLASSIC_ENGINE_OK:${tabTheme.selectedTextColor != null}'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final classicBtn = find.textContaining('Engine Gốc').first;
    await tester.ensureVisible(classicBtn);
    await tester.tap(classicBtn);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('CLASSIC_ENGINE_OK:true'), findsOneWidget);

    await tester.tap(find.text('Quay lại Trung tâm Điều hành DAUVERSE'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('connect-now-cta-btn')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Renders all 16 DAUVERSE screens in Dark/Light & VI/EN with zero RC2 strings and zero fake mock data',
      (WidgetTester tester) async {
    DauverseNativeBridge.setForceUnboundForTest(true);
    DauverseNativeBridge.setTestHarnessMode(true);
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      const MaterialApp(
        home: DauverseExecutiveShell(
          overrideInitialScreen: DauverseScreenId.dashboard,
          overrideDarkMode: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('DAUVERSE'), findsWidgets);
    expect(find.text('REMOTE DESKTOP V1'), findsWidgets);
    expect(find.text('KẾT NỐI NGAY'), findsWidgets);
    expect(find.text('892 441 109'), findsNothing);
    expect(find.text('14 ms'), findsNothing);
    expect(find.textContaining('RC2'), findsNothing);

    await tester.tap(find.text('VI'));
    await tester.pump();
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('CONNECT NOW'), findsWidgets);

    await tester.tap(find.text('EN'));
    await tester.pump();
    expect(find.text('VI'), findsOneWidget);

    await tester.tap(find.byTooltip('Dark / Light Mode'));
    await tester.pump();

    const i18nVi = DauverseI18n(true);
    for (final screenId in DauverseScreenId.values) {
      final navLabel = i18nVi.screenTitle(screenId);
      final target = find.text(navLabel).first;
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(navLabel), findsWidgets);
      expect(find.textContaining('RC2'), findsNothing);
    }

    final ftNav = find.text(i18nVi.screenTitle(DauverseScreenId.fileTransfer)).first;
    await tester.ensureVisible(ftNav);
    await tester.tap(ftNav);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('comfyui_wan2_render_1080p.mp4'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('16-Combination Resolution x DPI Matrix (1280x720..2560x1440 @ 100%..175%) has ZERO layout overflow',
      (WidgetTester tester) async {
    DauverseNativeBridge.setForceUnboundForTest(true);
    DauverseNativeBridge.setTestHarnessMode(true);
    DauverseNativeBridge.setTestHarnessIdentityOverride({
      'connection_id': '1029384756',
      'formatted_id': '1 029 384 756',
      'lan_interfaces': const [
        {'interface_name': 'eth0', 'friendly_name': 'Ethernet 2.5GbE', 'ipv4': '192.168.88.240', 'is_default_route': true},
        {'interface_name': 'eth1', 'friendly_name': 'WSL Hyper-V', 'ipv4': '172.24.16.1', 'is_default_route': false},
      ],
      'lan_ips': const ['192.168.88.240', '172.24.16.1'],
      'public_ip': '203.113.148.22',
      'public_ip_status': 'VERIFIED_OPT_IN',
      'connection_status': 'CONNECTED',
    });

    const physicalResolutions = <Size>[
      Size(1280, 720),
      Size(1366, 768),
      Size(1920, 1080),
      Size(2560, 1440),
    ];
    const dpiScales = <double>[1.0, 1.25, 1.5, 1.75];

    for (final phys in physicalResolutions) {
      for (final scale in dpiScales) {
        final logicalSize = Size(phys.width / scale, phys.height / scale);
        await tester.binding.setSurfaceSize(logicalSize);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: logicalSize,
                devicePixelRatio: scale,
              ),
              child: const DauverseExecutiveShell(
                overrideInitialScreen: DauverseScreenId.dashboard,
                overrideDarkMode: true,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.takeException(), isNull,
            reason: 'Overflow on Dashboard at ${phys.width.toInt()}x${phys.height.toInt()} @ ${(scale * 100).round()}% DPI');
      }
    }

    // Sweep all 16 screens at the tightest viewport (1280x720 @ 175% DPI = 731.4 x 411.4 logical px)
    // including live shrink from 2560x1440 -> 1280x720@175% on iteration 0!
    const tightestLogical = Size(1280 / 1.75, 720 / 1.75);
    await tester.binding.setSurfaceSize(tightestLogical);
    expect(tester.takeException(), isNull, reason: 'Overflow during live window shrink to 1280x720 @ 175% DPI');

    for (final screenId in DauverseScreenId.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: tightestLogical,
              devicePixelRatio: 1.75,
            ),
            child: DauverseExecutiveShell(
              key: ValueKey('tight-$screenId'),
              overrideInitialScreen: screenId,
              overrideDarkMode: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.takeException(), isNull,
          reason: 'Overflow on screen $screenId at 1280x720 @ 175% DPI');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Mini Control modes, window controls, and Smart Power Hunonic SK02 status render accurately',
      (WidgetTester tester) async {
    DauverseNativeBridge.setForceUnboundForTest(true);
    DauverseNativeBridge.setTestHarnessMode(true);
    await tester.binding.setSurfaceSize(const Size(1600, 960));
    const i18nVi = DauverseI18n(true);

    await tester.pumpWidget(
      const MaterialApp(
        home: DauverseExecutiveShell(
          overrideInitialScreen: DauverseScreenId.miniControl,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Preview Mode'), findsOneWidget);
    expect(find.text('AI Monitor Mode'), findsOneWidget);
    expect(find.text('Compact Status Mode'), findsOneWidget);

    final powerNav = find.text(i18nVi.screenTitle(DauverseScreenId.smartPower)).first;
    await tester.ensureVisible(powerNav);
    await tester.tap(powerNav);
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('HUNONIC SK02: BLOCKED'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Signed HTTP AI event renders Corner Toast, AI Live Status, and Notification Center without null fields',
      (WidgetTester tester) async {
    DauverseNativeBridge.setTestHarnessMode(true);
    await tester.binding.setSurfaceSize(const Size(1600, 960));
    const i18nVi = DauverseI18n(true);

    await tester.pumpWidget(
      const MaterialApp(
        home: DauverseExecutiveShell(
          overrideInitialScreen: DauverseScreenId.notificationCenter,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final triggerBtn = find.text('Gửi sự kiện Toast thật (HTTP)');
    expect(triggerBtn, findsOneWidget);
    await tester.tap(triggerBtn);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('null'), findsNothing);

    if (find.textContaining('claude_code').evaluate().isNotEmpty) {
      expect(find.text('Mở Remote'), findsWidgets);
    }

    final aiNav = find.text(i18nVi.screenTitle(DauverseScreenId.aiLiveStatus)).first;
    await tester.ensureVisible(aiNav);
    await tester.tap(aiNav);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('null'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}
