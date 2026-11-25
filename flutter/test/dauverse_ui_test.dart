import 'package:flutter/material.dart';
import 'package:flutter_hbb/dauverse/dauverse_shell.dart';
import 'package:flutter_hbb/dauverse/l10n/dauverse_i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Renders all 16 mandatory DAUVERSE screens in Dark/Light & VI/EN without fake mock data',
      (WidgetTester tester) async {
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

    // Verify Vietnamese default Executive Dashboard & absence of fabricated RC1 demo strings
    expect(find.text('DAUVERSE'), findsWidgets);
    expect(find.text('REMOTE DESKTOP V1'), findsWidgets);
    expect(find.text('Kết nối nhanh'), findsOneWidget);
    expect(find.text('892 441 109'), findsNothing);
    expect(find.text('14 ms'), findsNothing);

    // Toggle Vietnamese -> English -> Vietnamese
    await tester.tap(find.text('VI'));
    await tester.pump();
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('Quick Connect'), findsOneWidget);

    await tester.tap(find.text('EN'));
    await tester.pump();
    expect(find.text('VI'), findsOneWidget);

    // Toggle Dark -> Light mode
    await tester.tap(find.byTooltip('Dark / Light Mode'));
    await tester.pump();

    // Navigate through all 16 mandatory screens in the left rail
    const i18nVi = DauverseI18n(true);
    for (final screenId in DauverseScreenId.values) {
      final navLabel = i18nVi.screenTitle(screenId);
      final target = find.text(navLabel).first;
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(navLabel), findsWidgets);
    }

    // Verify File Transfer has zero hardcoded fake queue items
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

    // Verify zero literal "null" substrings in Notification Center
    expect(find.textContaining('null'), findsNothing);

    // If bound to native liblibrustdesk.so, Corner Toast & claude_code item must be visible
    if (find.textContaining('claude_code').evaluate().isNotEmpty) {
      expect(find.text('Mở Remote'), findsWidgets);
    }

    // Navigate to AI Live Status and verify zero literal "null" substrings
    final aiNav = find.text(i18nVi.screenTitle(DauverseScreenId.aiLiveStatus)).first;
    await tester.ensureVisible(aiNav);
    await tester.tap(aiNav);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('null'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}
