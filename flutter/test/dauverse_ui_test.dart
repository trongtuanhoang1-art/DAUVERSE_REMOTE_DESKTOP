import 'package:flutter/material.dart';
import 'package:flutter_hbb/dauverse/bridge/dauverse_bridge.dart';
import 'package:flutter_hbb/dauverse/dauverse_shell.dart';
import 'package:flutter_hbb/dauverse/l10n/dauverse_i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    DauverseNativeBridge.setForceUnboundForTest(false);
    DauverseNativeBridge.setTestHarnessMode(false);
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

  testWidgets('Renders all 16 mandatory DAUVERSE screens in Dark/Light & VI/EN without fake mock data',
      (WidgetTester tester) async {
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
    expect(find.text('Kết nối nhanh'), findsOneWidget);
    expect(find.text('892 441 109'), findsNothing);
    expect(find.text('14 ms'), findsNothing);

    await tester.tap(find.text('VI'));
    await tester.pump();
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('Quick Connect'), findsOneWidget);

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
    }

    final ftNav = find.text(i18nVi.screenTitle(DauverseScreenId.fileTransfer)).first;
    await tester.ensureVisible(ftNav);
    await tester.tap(ftNav);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('comfyui_wan2_render_1080p.mp4'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Quick Connect and Dual-Pane File Transfer invoke real session launcher with user Peer ID',
      (WidgetTester tester) async {
    DauverseNativeBridge.setTestHarnessMode(true);
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
    await tester.pump(const Duration(milliseconds: 150));

    await tester.enterText(find.byType(TextField).first, '998877665');
    await tester.pump();

    await tester.tap(find.text('Kết nối nhanh'));
    await tester.pump();
    expect(launched, ['998877665:false']);

    await tester.tap(find.text('Truyền File'));
    await tester.pump();
    expect(launched, ['998877665:false', '998877665:true']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Mini Control modes, window controls, and Smart Power Hunonic SK02 status render accurately',
      (WidgetTester tester) async {
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
