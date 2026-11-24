import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  final DauverseScreenId? overrideInitialScreen;
  final bool? overrideDarkMode;

  const DauverseExecutiveShell({
    Key? key,
    this.classicRustDeskBuilder,
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
    );
    _controller.startPolling();
    if (!kIsWeb && Platform.environment['DAUVERSE_SHOW_SAMPLE_TOAST'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.triggerCornerToastPreview(
          title: 'Antigravity đã hoàn thành nhiệm vụ',
          aiSource: 'Antigravity',
          project: 'DAUVERSE FT004',
          body: 'Kiểm thử tự động hoàn tất với đầy đủ bằng chứng xác thực.',
          verifiedEvidence: '128/128 tests PASS',
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final theme = DauverseTheme.buildTheme(_controller.isDarkMode);
        return Theme(
          data: theme,
          child: Builder(
            builder: (innerCtx) {
              if (_controller.showClassicRustDeskConnector && widget.classicRustDeskBuilder != null) {
                return Stack(
                  children: [
                    widget.classicRustDeskBuilder!(innerCtx),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF06B6D4),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _controller.selectScreen(DauverseScreenId.dashboard),
                        icon: const Icon(Icons.dashboard_customize, size: 18),
                        label: const Text('Return to DAUVERSE Command Center'),
                      ),
                    ),
                  ],
                );
              }
              return _buildExecutiveFrame(innerCtx);
            },
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

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          Row(
            children: [
              // Left Executive Navigation Rail
              Container(
                width: 248,
                decoration: BoxDecoration(
                  color: p.sidebarBg,
                  border: Border(right: BorderSide(color: p.border)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Row(
                        children: [
                          const DauverseEmblem(size: 36),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('DAUVERSE', style: DauverseTypography.heading(p, size: 15)),
                                Text('REMOTE DESKTOP V1',
                                    style: TextStyle(
                                      fontFamily: DauverseTypography.kpiFont,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      color: p.cyan,
                                    )),
                              ],
                            ),
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
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _controller.selectScreen(id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: selected
                                      ? LinearGradient(
                                          colors: [p.cyan.withOpacity(0.22), p.blue.withOpacity(0.16)],
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(10),
                                  border: selected ? Border.all(color: p.cyan.withOpacity(0.5)) : null,
                                ),
                                child: Row(
                                  children: [
                                    Icon(icon, size: 18, color: selected ? p.cyan : p.textSecondary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        i18n.screenTitle(id),
                                        style: DauverseTypography.body(
                                          p,
                                          size: 12.5,
                                          weight: selected ? FontWeight.w700 : FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Main Content Area
              Expanded(
                child: Column(
                  children: [
                    // Top Executive Status Header
                    Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: p.sidebarBg,
                        border: Border(bottom: BorderSide(color: p.border)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            i18n.screenTitle(_controller.currentScreen),
                            style: DauverseTypography.heading(p, size: 16),
                          ),
                          const SizedBox(width: 14),
                          if (_controller.lastActionBanner.isNotEmpty)
                            Expanded(
                              child: Text(
                                _controller.lastActionBanner,
                                style: DauverseTypography.caption(p, size: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          else
                            const Spacer(),
                          DauverseStatusBadge(
                            label: _controller.performanceMode,
                            color: p.cyan,
                          ),
                          const SizedBox(width: 10),
                          TextButton(
                            onPressed: _controller.toggleLanguage,
                            child: Text(_controller.isVietnamese ? 'VI' : 'EN',
                                style: DauverseTypography.kpi(p, size: 12, color: p.cyan)),
                          ),
                          IconButton(
                            tooltip: 'Dark / Light Mode',
                            onPressed: _controller.toggleTheme,
                            icon: Icon(
                              _controller.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                              size: 18,
                              color: p.textPrimary,
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
