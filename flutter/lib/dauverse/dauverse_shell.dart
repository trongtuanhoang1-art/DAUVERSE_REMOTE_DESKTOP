import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'bridge/dauverse_bridge.dart';
import 'l10n/dauverse_i18n.dart';
import 'screens/ai_and_hardware_screens.dart';
import 'screens/dashboard_screen.dart';
import 'screens/devices_and_session_screens.dart';
import 'screens/power_security_ops_screens.dart';
import 'screens/transfer_and_clipboard_screens.dart';
import 'theme/dauverse_theme.dart';
import 'widgets/corner_toast_overlay.dart';

class DauverseExecutiveShell extends StatefulWidget {
  final Widget Function(BuildContext)? classicRustDeskBuilder;
  final RealSessionLauncher? onLaunchRealSession;
  final List<Map<String, String>> Function()? peersProvider;
  final DauverseScreenId? overrideInitialScreen;
  final bool? overrideDarkMode;

  const DauverseExecutiveShell({
    Key? key,
    this.classicRustDeskBuilder,
    this.onLaunchRealSession,
    this.peersProvider,
    this.overrideInitialScreen,
    this.overrideDarkMode,
  }) : super(key: key);

  @override
  State<DauverseExecutiveShell> createState() => _DauverseExecutiveShellState();
}

class _DauverseExecutiveShellState extends State<DauverseExecutiveShell> {
  late final DauverseController _controller;

  static DauverseScreenId _resolveInitialScreen(DauverseScreenId? explicit) {
    if (explicit != null) return explicit;
    if (!kIsWeb) {
      final envVal = Platform.environment['DAUVERSE_INITIAL_SCREEN']?.trim().toLowerCase();
      if (envVal != null && envVal.isNotEmpty) {
        for (final s in DauverseScreenId.values) {
          if (s.name.toLowerCase() == envVal) return s;
        }
      }
    }
    return DauverseScreenId.dashboard;
  }

  static bool _resolveInitialDarkMode(bool? explicit) {
    if (explicit != null) return explicit;
    if (!kIsWeb) {
      final envTheme = Platform.environment['DAUVERSE_THEME_MODE']?.trim().toLowerCase();
      if (envTheme == 'light') return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _controller = DauverseController(
      initialScreen: _resolveInitialScreen(widget.overrideInitialScreen),
      isDarkMode: _resolveInitialDarkMode(widget.overrideDarkMode),
      onLaunchRealSession: widget.onLaunchRealSession,
      peersProvider: widget.peersProvider,
    );
    _controller.startPolling();
    if (!kIsWeb && Platform.environment['DAUVERSE_SHOW_SAMPLE_TOAST'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.sendSignedLoopbackAiProbe(
          source: 'codex_cli',
          summary: 'Sự kiện kiểm thử chữ ký HMAC-SHA256 thật qua HTTP 127.0.0.1.',
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext outerContext) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final i18n = _controller.i18n;
        // Render classic Engine Gốc using outerContext's ThemeExtensions (TabbarTheme + ColorThemeExtension)
        // so DesktopTabPage never encounters a null-check crash on Theme.of(context).extension<TabbarTheme>()!
        if (_controller.showClassicRustDeskConnector && widget.classicRustDeskBuilder != null) {
          return Stack(
            children: [
              widget.classicRustDeskBuilder!(outerContext),
              Positioned(
                right: 16,
                bottom: 16,
                child: Material(
                  color: Colors.transparent,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      elevation: 6,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _controller.selectScreen(DauverseScreenId.dashboard),
                    icon: const Icon(Icons.dashboard_customize, size: 18),
                    label: Text(
                      i18n.t(
                        'Quay lại Trung tâm Điều hành DAUVERSE',
                        'Return to DAUVERSE Command Center',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final inheritedExts = Theme.of(outerContext).extensions.values;
        final theme = DauverseTheme.buildTheme(
          _controller.isDarkMode,
          inheritedExtensions: inheritedExts,
        );
        return Theme(
          data: theme,
          child: Builder(
            builder: (innerCtx) => _buildExecutiveFrame(innerCtx),
          ),
        );
      },
    );
  }

  Widget _buildExecutiveFrame(BuildContext context) {
    final p = DauversePalette.of(context);
    final i18n = _controller.i18n;

    const navItems = <(DauverseScreenId, IconData)>[
      (DauverseScreenId.dashboard, Icons.space_dashboard_rounded),
      (DauverseScreenId.myDevices, Icons.devices_rounded),
      (DauverseScreenId.remoteSession, Icons.desktop_windows_rounded),
      (DauverseScreenId.miniControl, Icons.picture_in_picture_alt_rounded),
      (DauverseScreenId.fileTransfer, Icons.swap_horiz_rounded),
      (DauverseScreenId.clipboardSettings, Icons.content_paste_rounded),
      (DauverseScreenId.aiLiveStatus, Icons.auto_awesome_rounded),
      (DauverseScreenId.notificationCenter, Icons.notifications_active_rounded),
      (DauverseScreenId.hardwareMonitor, Icons.memory_rounded),
      (DauverseScreenId.smartPower, Icons.power_settings_new_rounded),
      (DauverseScreenId.securityCenter, Icons.shield_rounded),
      (DauverseScreenId.sessionHistory, Icons.history_rounded),
      (DauverseScreenId.networkDiagnostics, Icons.router_rounded),
      (DauverseScreenId.updateCenter, Icons.system_update_alt_rounded),
      (DauverseScreenId.settings, Icons.tune_rounded),
      (DauverseScreenId.about, Icons.info_outline_rounded),
    ];

    return LayoutBuilder(
      builder: (context, shellConstraints) {
        final shellWidth = shellConstraints.maxWidth;
        final compactRail = _controller.sidebarCollapsed || shellWidth < 1080;
        final showInlineBanner = shellWidth >= 1180 && _controller.lastActionBanner.isNotEmpty;
        final compactHeader = shellWidth < 900;

        return Scaffold(
          backgroundColor: p.bg,
          body: Stack(
            children: [
              Row(
                children: [
                  // Responsive Left Executive Navigation Rail (236px full or 68px compact icon rail)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: compactRail ? 68 : 236,
                    decoration: BoxDecoration(
                      color: p.sidebarBg,
                      border: Border(right: BorderSide(color: p.border)),
                    ),
                    child: ClipRect(
                      child: LayoutBuilder(
                        builder: (ctx, railConstraints) {
                          final renderCompact = railConstraints.maxWidth < 170;
                          return Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  renderCompact ? 10 : 14,
                                  14,
                                  renderCompact ? 10 : 10,
                                  12,
                                ),
                                child: renderCompact
                                    ? Tooltip(
                                        message: i18n.t('Mở rộng thanh điều hướng', 'Expand navigation sidebar'),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(10),
                                          onTap: _controller.toggleSidebar,
                                          child: const Center(child: DauverseEmblem(size: 34)),
                                        ),
                                      )
                                    : Row(
                                        children: [
                                          const DauverseEmblem(size: 34),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'DAUVERSE',
                                                  style: DauverseTypography.heading(p, size: 15),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  'REMOTE DESKTOP V1',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontFamily: DauverseTypography.kpiFont,
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 1.0,
                                                    color: p.cyan,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            tooltip: i18n.t('Thu gọn thanh bên', 'Collapse sidebar'),
                                            onPressed: _controller.toggleSidebar,
                                            icon: Icon(Icons.menu_open_rounded, size: 18, color: p.textSecondary),
                                          ),
                                        ],
                                      ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                  itemCount: navItems.length,
                                  itemBuilder: (ctx, idx) {
                                    final (id, icon) = navItems[idx];
                                    final selected = _controller.currentScreen == id;
                                    final label = i18n.screenTitle(id);
                                    final tile = InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _controller.selectScreen(id),
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: renderCompact ? 0 : 12,
                                          vertical: 9,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: selected
                                              ? LinearGradient(
                                                  colors: [
                                                    p.cyan.withOpacity(0.22),
                                                    p.blue.withOpacity(0.15),
                                                  ],
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(10),
                                          border: selected
                                              ? Border.all(color: p.cyan.withOpacity(0.5))
                                              : null,
                                        ),
                                        child: renderCompact
                                            ? Center(
                                                child: Icon(
                                                  icon,
                                                  size: 19,
                                                  color: selected ? p.cyan : p.textSecondary,
                                                ),
                                              )
                                            : Row(
                                                children: [
                                                  Icon(
                                                    icon,
                                                    size: 18,
                                                    color: selected ? p.cyan : p.textSecondary,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      label,
                                                      style: DauverseTypography.body(
                                                        p,
                                                        size: 12.5,
                                                        weight: selected ? FontWeight.w700 : FontWeight.w500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    );
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: renderCompact ? Tooltip(message: label, child: tile) : tile,
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  // Main Content Area
                  Expanded(
                    child: Column(
                      children: [
                        // Top Executive Status Header (Overflow-Safe Draggable Window Chrome + Controls)
                        LayoutBuilder(
                          builder: (ctx, headerBox) {
                            final hdrW = headerBox.maxWidth;
                            final tightHdr = hdrW < 580;
                            final showPerfPill = hdrW >= 540;
                            return Container(
                              height: 54,
                              padding: EdgeInsets.symmetric(horizontal: tightHdr ? 10 : (compactHeader ? 12 : 20)),
                              decoration: BoxDecoration(
                                color: p.sidebarBg,
                                border: Border(bottom: BorderSide(color: p.border)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onPanStart: (_) async {
                                        try {
                                          await windowManager.startDragging();
                                        } catch (_) {}
                                      },
                                      onDoubleTap: () async {
                                        try {
                                          if (await windowManager.isMaximized()) {
                                            await windowManager.unmaximize();
                                          } else {
                                            await windowManager.maximize();
                                          }
                                        } catch (_) {}
                                      },
                                      child: SizedBox(
                                        height: double.infinity,
                                        child: Row(
                                          children: [
                                            Flexible(
                                              flex: 3,
                                              child: Text(
                                                i18n.screenTitle(_controller.currentScreen),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: DauverseTypography.heading(
                                                  p,
                                                  size: compactHeader ? 14.5 : 16,
                                                ),
                                              ),
                                            ),
                                            if (showInlineBanner && hdrW >= 820) ...[
                                              const SizedBox(width: 12),
                                              Expanded(
                                                flex: 4,
                                                child: Text(
                                                  _controller.lastActionBanner,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: DauverseTypography.caption(p, size: 12),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (showPerfPill) ...[
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: i18n.t(
                                        'Chế độ hiệu năng luồng hình ảnh: ${_controller.performanceMode}',
                                        'Active stream performance profile: ${_controller.performanceMode}',
                                      ),
                                      child: DauverseStatusBadge(
                                        label: (compactHeader || hdrW < 760)
                                            ? i18n.performanceBadgeShort(_controller.performanceMode)
                                            : _controller.performanceMode,
                                        color: p.cyan,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 6),
                              Tooltip(
                                message: i18n.t(
                                  'Chuyển đổi ngôn ngữ Tiếng Việt / English',
                                  'Switch language Tiếng Việt / English',
                                ),
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(38, 34),
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  onPressed: _controller.toggleLanguage,
                                  child: Text(
                                    _controller.isVietnamese ? 'VI' : 'EN',
                                    style: DauverseTypography.kpi(p, size: 12, color: p.cyan),
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Dark / Light Mode',
                                onPressed: _controller.toggleTheme,
                                icon: Icon(
                                  _controller.isDarkMode
                                      ? Icons.light_mode_outlined
                                      : Icons.dark_mode_outlined,
                                  size: 18,
                                  color: p.textPrimary,
                                ),
                              ),
                              const VerticalDivider(width: 10, indent: 14, endIndent: 14),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: i18n.t('Thu nhỏ cửa sổ', 'Minimize'),
                                onPressed: () async {
                                  try {
                                    await windowManager.minimize();
                                  } catch (_) {}
                                },
                                icon: Icon(Icons.minimize, size: 16, color: p.textSecondary),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: i18n.t('Phóng to / Khôi phục', 'Maximize / Restore'),
                                onPressed: () async {
                                  try {
                                    if (await windowManager.isMaximized()) {
                                      await windowManager.unmaximize();
                                    } else {
                                      await windowManager.maximize();
                                    }
                                  } catch (_) {}
                                },
                                icon: Icon(Icons.crop_square, size: 15, color: p.textSecondary),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: i18n.t('Đóng cửa sổ', 'Close'),
                                onPressed: () async {
                                  try {
                                    await windowManager.close();
                                  } catch (_) {}
                                },
                                  icon: Icon(Icons.close, size: 17, color: p.danger),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                        if (!showInlineBanner && _controller.lastActionBanner.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: p.surfaceElevated,
                              border: Border(bottom: BorderSide(color: p.border)),
                            ),
                            child: Text(
                              _controller.lastActionBanner,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DauverseTypography.caption(p, size: 11.5, color: p.cyan),
                            ),
                          ),
                        if (!_controller.backendAvailable)
                          Container(
                            key: const Key('dauverse-ffi-fail-closed-banner'),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: p.danger,
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    i18n.t(
                                      'CẢNH BÁO AN TOÀN (FAIL-CLOSED): Backend gốc librustdesk không khả dụng — mọi thao tác cấu hình & bảo mật đã bị từ chối (${_controller.backendError}).',
                                      'SECURITY FAIL-CLOSED: Native librustdesk backend is unavailable — privileged operations are refused (${_controller.backendError}).',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(child: _buildActiveScreen()),
                      ],
                    ),
                  ),
                ],
              ),
              DauverseCornerToastOverlay(controller: _controller),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveScreen() {
    switch (_controller.currentScreen) {
      case DauverseScreenId.dashboard:
        return DauverseDashboardScreen(controller: _controller);
      case DauverseScreenId.myDevices:
        return DauverseMyDevicesScreen(controller: _controller);
      case DauverseScreenId.remoteSession:
        return DauverseRemoteSessionScreen(controller: _controller);
      case DauverseScreenId.miniControl:
        return DauverseMiniControlScreen(controller: _controller);
      case DauverseScreenId.fileTransfer:
        return DauverseFileTransferScreen(controller: _controller);
      case DauverseScreenId.clipboardSettings:
        return DauverseClipboardSettingsScreen(controller: _controller);
      case DauverseScreenId.aiLiveStatus:
        return DauverseAiLiveStatusScreen(controller: _controller);
      case DauverseScreenId.notificationCenter:
        return DauverseNotificationCenterScreen(controller: _controller);
      case DauverseScreenId.hardwareMonitor:
        return DauverseHardwareMonitorScreen(controller: _controller);
      case DauverseScreenId.smartPower:
        return DauverseSmartPowerScreen(controller: _controller);
      case DauverseScreenId.securityCenter:
        return DauverseSecurityCenterScreen(controller: _controller);
      case DauverseScreenId.sessionHistory:
        return DauverseSessionHistoryScreen(controller: _controller);
      case DauverseScreenId.networkDiagnostics:
        return DauverseNetworkDiagnosticsScreen(controller: _controller);
      case DauverseScreenId.updateCenter:
        return DauverseUpdateCenterScreen(controller: _controller);
      case DauverseScreenId.settings:
        return DauverseSettingsScreen(controller: _controller);
      case DauverseScreenId.about:
        return DauverseAboutScreen(controller: _controller);
    }
  }
}
