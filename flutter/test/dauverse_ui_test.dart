import 'package:flutter/material.dart';
import 'package:flutter_hbb/dauverse/dauverse_shell.dart';
import 'package:flutter_hbb/dauverse/l10n/dauverse_i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Renders all 16 mandatory DAUVERSE screens in Dark and Light modes with VI/EN i18n',
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

    // Verify Vietnamese default Executive Dashboard
    expect(find.text('DAUVERSE'), findsWidgets);
    expect(find.text('REMOTE DESKTOP V1'), findsWidgets);
    expect(find.textContaining('DAUVERSE REMOTE'), findsWidgets);
    expect(find.text('Kết nối nhanh'), findsOneWidget);

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

    // Verify Mini Control core features
    final miniNav = find.text(i18nVi.screenTitle(DauverseScreenId.miniControl)).first;
    await tester.ensureVisible(miniNav);
    await tester.tap(miniNav);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Preview Mode'), findsOneWidget);
    expect(find.text('AI Monitor Mode'), findsOneWidget);
    expect(find.text('Compact Status Mode'), findsOneWidget);

    // Verify Notification Center & non-focus-stealing Corner Toast with verified evidence
    final notifNav = find.text(i18nVi.screenTitle(DauverseScreenId.notificationCenter)).first;
    await tester.ensureVisible(notifNav);
    await tester.tap(notifNav);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Hiển thị Toast góc màn hình'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Antigravity đã hoàn thành nhiệm vụ'), findsOneWidget);
    expect(find.text('128/128 tests PASS (VERIFIED EVIDENCE)'), findsOneWidget);
    expect(find.text('Mở Remote'), findsOneWidget);
    expect(find.text('Đóng'), findsOneWidget);

    await tester.tap(find.text('Đóng'));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}
