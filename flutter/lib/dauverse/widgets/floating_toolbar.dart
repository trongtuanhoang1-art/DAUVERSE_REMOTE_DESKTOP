import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../bridge/dauverse_bridge.dart';
import '../l10n/dauverse_i18n.dart';
import '../theme/dauverse_theme.dart';

class DauverseFloatingToolbar extends StatefulWidget {
  final DauverseController controller;
  const DauverseFloatingToolbar({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseFloatingToolbar> createState() => _DauverseFloatingToolbarState();
}

class _DauverseFloatingToolbarState extends State<DauverseFloatingToolbar> {
  Offset _dragOffset = const Offset(0, 10);
  bool _hovered = true;
  bool _pinnedWindow = false;
  bool _fullScreen = false;
  bool _showStatsPopup = false;

  Future<void> _setFullScreen(bool enable) async {
    setState(() => _fullScreen = enable);
    try {
      await windowManager.setFullScreen(enable);
    } catch (_) {}
  }

  Future<void> _togglePinWindow() async {
    final next = !_pinnedWindow;
    setState(() => _pinnedWindow = next);
    try {
      await windowManager.setAlwaysOnTop(next);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final visibleOpacity = (c.toolbarAutoHide && !_hovered) ? 0.22 : 1.0;
    final perf = c.snapshot['performance'] as Map<String, dynamic>? ?? const {};
    final connected = perf['session_connected'] == true;

    return FocusScope(
      canRequestFocus: false,
      child: Stack(
        children: [
          Positioned(
            top: _dragOffset.dy.clamp(4.0, 420.0),
            left: c.toolbarPinnedTop ? null : _dragOffset.dx.clamp(8.0, 900.0),
            right: null,
            child: Align(
              alignment: Alignment.topCenter,
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      c.toolbarPinnedTop = false;
                      _dragOffset += details.delta;
                    });
                  },
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: visibleOpacity,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.sidebarBg.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.cyan.withOpacity(0.55)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: c.toolbarCollapsed
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const DauverseEmblem(size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'DAUVERSE',
                                  style: DauverseTypography.body(p, size: 11, weight: FontWeight.w700),
                                ),
                                if (c.recordingActive) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle),
                                  ),
                                ],
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: i18n.t('Mở rộng thanh công cụ', 'Expand toolbar'),
                                  icon: Icon(Icons.unfold_more, size: 16, color: p.cyan),
                                  onPressed: () => setState(() => c.toolbarCollapsed = false),
                                ),
                              ],
                            )
                          : Wrap(
                              spacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _btn(p, Icons.fullscreen, i18n.t('Toàn màn hình', 'Full Screen'),
                                    active: _fullScreen,
                                    onTap: () => _setFullScreen(true)),
                                _btn(p, Icons.fullscreen_exit, i18n.t('Cửa sổ', 'Window Mode'),
                                    active: !_fullScreen,
                                    onTap: () => _setFullScreen(false)),
                                _btn(p, Icons.picture_in_picture_alt, 'Mini Control',
                                    onTap: () => c.selectScreen(DauverseScreenId.miniControl)),
                                _btn(p, Icons.push_pin_outlined, i18n.t('Ghim cửa sổ', 'Pin Window'),
                                    active: _pinnedWindow,
                                    onTap: _togglePinWindow),
                                _btn(p, Icons.content_paste, 'Clipboard',
                                    onTap: () => c.selectScreen(DauverseScreenId.clipboardSettings)),
                                _btn(p, Icons.swap_horiz, i18n.t('Truyền file', 'File Transfer'),
                                    onTap: () => c.launchRealFileTransfer(context, c.targetPeerId)),
                                _btn(
                                    p,
                                    c.audioEnabled ? Icons.volume_up : Icons.volume_off,
                                    i18n.t('Âm thanh', 'Audio'),
                                    active: c.audioEnabled,
                                    onTap: () => setState(() => c.audioEnabled = !c.audioEnabled)),
                                _btn(p, Icons.monitor, i18n.t('Chuyển màn hình', 'Monitor Switch'),
                                    onTap: () => setState(
                                        () => c.selectedMonitorIndex = (c.selectedMonitorIndex + 1) % 3)),
                                PopupMenuButton<String>(
                                  tooltip: i18n.t('Độ phân giải', 'Resolution Preset'),
                                  onSelected: (preset) {
                                    setState(() => c.selectedResolutionPreset = preset);
                                    c.lastActionBanner = 'Resolution preset: $preset';
                                    c.refreshSnapshot();
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: '1920x1080@60', child: Text('1920x1080 @ 60Hz (FHD)')),
                                    PopupMenuItem(value: '2560x1440@60', child: Text('2560x1440 @ 60Hz (2K)')),
                                    PopupMenuItem(value: '3840x2160@60', child: Text('3840x2160 @ 60Hz (4K)')),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(Icons.aspect_ratio, size: 17, color: p.textPrimary),
                                  ),
                                ),
                                _btn(p, Icons.speed, i18n.t('Hiệu năng', 'Performance Mode'),
                                    onTap: () {
                                  const modes = [
                                    'AUTO_ADAPTIVE',
                                    'ULTRA_LOW_LATENCY',
                                    'BALANCED',
                                    'HIGH_QUALITY',
                                    'LOW_BANDWIDTH',
                                    'AI_WORKLOAD_PRIORITY',
                                  ];
                                  final idx = modes.indexOf(c.performanceMode);
                                  c.setPerformanceProfile(modes[(idx + 1) % modes.length]);
                                }),
                                _btn(p, Icons.camera_alt_outlined, 'Screenshot', onTap: () {
                                  if (c.targetPeerId.isNotEmpty && c.onLaunchRealSession != null) {
                                    c.launchRealRemoteSession(context, c.targetPeerId);
                                  } else {
                                    c.lastActionBanner = i18n.t(
                                      'NO_ACTIVE_REMOTE_SESSION: Mở phiên kết nối thực tới máy đích trước khi chụp ảnh khung hình.',
                                      'NO_ACTIVE_REMOTE_SESSION: Connect to a live remote peer before capturing stream frames.',
                                    );
                                    c.refreshSnapshot();
                                  }
                                }),
                                _btn(
                                    p,
                                    Icons.fiber_manual_record,
                                    i18n.t('Ghi hình', 'Recording'),
                                    active: c.recordingActive,
                                    danger: c.recordingActive,
                                    onTap: () => c.toggleExplicitRecording(!c.recordingActive)),
                                _btn(p, Icons.keyboard_alt_outlined, i18n.t('Phím tắt', 'Shortcuts'),
                                    onTap: () => c.selectScreen(DauverseScreenId.settings)),
                                _btn(p, Icons.security_update_warning, 'Ctrl+Alt+Del', onTap: () {
                                  c.lastActionBanner = i18n.t(
                                    'Ctrl+Alt+Del SAS chỉ khả dụng trong cửa sổ phiên kết nối thực tới Windows Service đã cấp quyền.',
                                    'Ctrl+Alt+Del SAS requires an active native session connected to an authorized Windows Service.',
                                  );
                                  c.refreshSnapshot();
                                }),
                                _btn(p, Icons.auto_awesome, 'AI Status',
                                    onTap: () => c.selectScreen(DauverseScreenId.aiLiveStatus)),
                                _btn(p, Icons.analytics_outlined,
                                    i18n.t('Thống kê kết nối', 'Connection Stats'),
                                    active: _showStatsPopup,
                                    onTap: () => setState(() => _showStatsPopup = !_showStatsPopup)),
                                _btn(p, Icons.power_settings_new, 'Smart Power',
                                    onTap: () => c.selectScreen(DauverseScreenId.smartPower)),
                                _btn(p, Icons.call_end, i18n.t('Ngắt kết nối', 'Disconnect'),
                                    danger: true,
                                    onTap: () {
                                      c.targetPeerId = '';
                                      c.selectScreen(DauverseScreenId.dashboard);
                                    }),
                                const SizedBox(width: 4),
                                _btn(p, Icons.vertical_align_top, i18n.t('Ghim cạnh trên', 'Pin Edge'),
                                    active: c.toolbarPinnedTop,
                                    onTap: () => setState(() {
                                          c.toolbarPinnedTop = true;
                                          _dragOffset = const Offset(0, 10);
                                        })),
                                _btn(p, Icons.visibility_off_outlined, i18n.t('Tự ẩn', 'Auto-hide'),
                                    active: c.toolbarAutoHide,
                                    onTap: () => setState(() => c.toolbarAutoHide = !c.toolbarAutoHide)),
                                _btn(p, Icons.unfold_less, i18n.t('Thu gọn', 'Collapse'),
                                    onTap: () => setState(() => c.toolbarCollapsed = true)),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_showStatsPopup)
            Positioned(
              top: 66,
              right: 20,
              child: DauverseCard(
                padding: const EdgeInsets.all(12),
                accentBorder: p.cyan,
                child: Text(
                  connected
                      ? 'Codec: ${perf['codec']} (${perf['encoder']})  |  ${perf['measured_fps'] != null ? "${perf['measured_fps']} FPS" : "FPS: N/A (Target ${perf['configured_target_fps'] ?? 0})"}  |  RTT: ${perf['ping_rtt_ms']} ms  |  ${perf['measured_bitrate_kbps'] != null ? "${perf['measured_bitrate_kbps']} kbps" : "Bitrate: N/A (Cap ${perf['estimated_bitrate_cap_kbps'] ?? 0} kbps)"}  |  ${perf['connection_route']}'
                      : 'Session: DISCONNECTED  |  Profile: ${perf['active_mode'] ?? c.performanceMode}  |  Preferred Codec: ${perf['codec'] ?? "H265"} (${perf['encoder'] ?? "NVENC"})',
                  style: DauverseTypography.kpi(p, size: 12, color: p.cyan),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _btn(
    DauversePalette p,
    IconData icon,
    String tooltip, {
    required VoidCallback onTap,
    bool active = false,
    bool danger = false,
  }) {
    final fg = danger
        ? p.danger
        : active
            ? p.cyan
            : p.textPrimary;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        canRequestFocus: false,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: active ? p.cyan.withOpacity(0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: fg),
        ),
      ),
    );
  }
}
