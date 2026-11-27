import 'dart:math' as math;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = math.max(240.0, constraints.maxWidth - 28);
        final maxDragX = math.max(8.0, constraints.maxWidth - 220);
        final maxDragY = math.max(10.0, constraints.maxHeight - 90);

        return FocusScope(
          canRequestFocus: false,
          child: Stack(
            children: [
              Positioned(
                top: _dragOffset.dy.clamp(4.0, maxDragY),
                left: c.toolbarPinnedTop ? 14 : _dragOffset.dx.clamp(8.0, maxDragX),
                right: c.toolbarPinnedTop ? 14 : null,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
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
                                        icon: Icon(Icons.unfold_more_rounded, size: 16, color: p.cyan),
                                        onPressed: () => setState(() => c.toolbarCollapsed = false),
                                      ),
                                    ],
                                  )
                                : Wrap(
                                    spacing: 2,
                                    runSpacing: 2,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      _btn(
                                        p,
                                        Icons.fullscreen_rounded,
                                        i18n.t('Toàn màn hình', 'Full Screen'),
                                        active: _fullScreen,
                                        onTap: () => _setFullScreen(true),
                                      ),
                                      _btn(
                                        p,
                                        Icons.fullscreen_exit_rounded,
                                        i18n.t('Cửa sổ', 'Window Mode'),
                                        active: !_fullScreen,
                                        onTap: () => _setFullScreen(false),
                                      ),
                                      _btn(
                                        p,
                                        Icons.picture_in_picture_alt_rounded,
                                        'Mini Control',
                                        onTap: () => c.selectScreen(DauverseScreenId.miniControl),
                                      ),
                                      _btn(
                                        p,
                                        Icons.push_pin_outlined,
                                        i18n.t('Ghim cửa sổ luôn nổi', 'Pin Window Always-on-Top'),
                                        active: _pinnedWindow,
                                        onTap: _togglePinWindow,
                                      ),
                                      _btn(
                                        p,
                                        Icons.content_paste_rounded,
                                        'Smart Clipboard',
                                        onTap: () => c.selectScreen(DauverseScreenId.clipboardSettings),
                                      ),
                                      _btn(
                                        p,
                                        Icons.swap_horiz_rounded,
                                        i18n.t('Truyền file hai chiều', 'File Transfer'),
                                        onTap: () => c.launchRealFileTransfer(context, c.targetPeerId),
                                      ),
                                      _btn(
                                        p,
                                        c.audioEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                        i18n.t('Âm thanh phiên mặc định', 'Default Session Audio'),
                                        active: c.audioEnabled,
                                        onTap: () {
                                          setState(() => c.audioEnabled = !c.audioEnabled);
                                          c.lastActionBanner = c.audioEnabled
                                              ? i18n.t('Đã bật âm thanh cho phiên kết nối.', 'Session audio enabled.')
                                              : i18n.t('Đã tắt tiếng phiên kết nối.', 'Session audio muted.');
                                          c.refreshSnapshot(preserveActionBanner: true);
                                        },
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: i18n.t('Độ phân giải màn hình ảo / phiên', 'Display Resolution Preset'),
                                        onSelected: (preset) {
                                          setState(() => c.selectedResolutionPreset = preset);
                                          c.lastActionBanner = i18n.t(
                                            'Đã chọn cấu hình độ phân giải: $preset',
                                            'Selected resolution preset: $preset',
                                          );
                                          c.refreshSnapshot(preserveActionBanner: true);
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: '1920x1080@60', child: Text('1920×1080 @ 60Hz (FHD)')),
                                          PopupMenuItem(value: '2560x1440@60', child: Text('2560×1440 @ 60Hz (2K)')),
                                          PopupMenuItem(value: '3840x2160@60', child: Text('3840×2160 @ 60Hz (4K)')),
                                        ],
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Icon(Icons.aspect_ratio_rounded, size: 17, color: p.textPrimary),
                                        ),
                                      ),
                                      _btn(
                                        p,
                                        Icons.speed_rounded,
                                        i18n.t('Chế độ Hiệu năng', 'Performance Mode'),
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
                                        },
                                      ),
                                      _btn(
                                        p,
                                        Icons.display_settings_rounded,
                                        i18n.t('Chế độ Kết xuất Đồ họa', 'Graphics Fallback Mode'),
                                        onTap: () {
                                          const gfxModes = [
                                            'PIXEL_BUFFER_SAFE',
                                            'SOFTWARE_CANVAS_FALLBACK',
                                            'GPU_D3D11_ZERO_COPY',
                                          ];
                                          final idx = gfxModes.indexOf(c.graphicsFallbackMode);
                                          c.setGraphicsFallbackMode(
                                            gfxModes[(idx + 1) % gfxModes.length],
                                            restoreHwcodec: true,
                                          );
                                        },
                                      ),
                                      _btn(
                                        p,
                                        Icons.fiber_manual_record_rounded,
                                        i18n.t('Ghi hình phiên (Có cảnh báo công khai)', 'Explicit Session Recording'),
                                        active: c.recordingActive,
                                        danger: c.recordingActive,
                                        onTap: () => c.toggleExplicitRecording(!c.recordingActive),
                                      ),
                                      _btn(
                                        p,
                                        Icons.keyboard_alt_outlined,
                                        i18n.t('Cài đặt & Phím tắt', 'Settings & Shortcuts'),
                                        onTap: () => c.selectScreen(DauverseScreenId.settings),
                                      ),
                                      _btn(
                                        p,
                                        Icons.security_update_warning_rounded,
                                        'Ctrl+Alt+Del (SAS)',
                                        onTap: () {
                                          c.lastActionBanner = i18n.t(
                                            'Ctrl+Alt+Del (SAS) thực thi trực tiếp trong cửa sổ phiên kết nối thực tới máy đã chạy Windows Service.',
                                            'Ctrl+Alt+Del SAS executes inside active native sessions connected to an authorized Windows Service.',
                                          );
                                          c.refreshSnapshot(preserveActionBanner: true);
                                        },
                                      ),
                                      _btn(
                                        p,
                                        Icons.auto_awesome_rounded,
                                        'AI Live Status',
                                        onTap: () => c.selectScreen(DauverseScreenId.aiLiveStatus),
                                      ),
                                      _btn(
                                        p,
                                        Icons.analytics_outlined,
                                        i18n.t('Thống kê luồng', 'Stream Diagnostics'),
                                        active: _showStatsPopup,
                                        onTap: () => setState(() => _showStatsPopup = !_showStatsPopup),
                                      ),
                                      _btn(
                                        p,
                                        Icons.power_settings_new_rounded,
                                        'Smart Power',
                                        onTap: () => c.selectScreen(DauverseScreenId.smartPower),
                                      ),
                                      _btn(
                                        p,
                                        Icons.call_end_rounded,
                                        i18n.t('Đóng / Về Dashboard', 'Return to Dashboard'),
                                        danger: true,
                                        onTap: () {
                                          c.targetPeerId = '';
                                          c.selectScreen(DauverseScreenId.dashboard);
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      _btn(
                                        p,
                                        Icons.vertical_align_top_rounded,
                                        i18n.t('Ghim cạnh trên', 'Pin Top Edge'),
                                        active: c.toolbarPinnedTop,
                                        onTap: () => setState(() {
                                          c.toolbarPinnedTop = true;
                                          _dragOffset = const Offset(0, 10);
                                        }),
                                      ),
                                      _btn(
                                        p,
                                        Icons.visibility_off_outlined,
                                        i18n.t('Tự làm mờ khi rời chuột', 'Auto-fade'),
                                        active: c.toolbarAutoHide,
                                        onTap: () => setState(() => c.toolbarAutoHide = !c.toolbarAutoHide),
                                      ),
                                      _btn(
                                        p,
                                        Icons.unfold_less_rounded,
                                        i18n.t('Thu gọn', 'Collapse'),
                                        onTap: () => setState(() => c.toolbarCollapsed = true),
                                      ),
                                    ],
                                  ),
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
                  left: 20,
                  right: 20,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxW),
                      child: DauverseCard(
                        padding: const EdgeInsets.all(12),
                        accentBorder: p.cyan,
                        child: Text(
                          connected
                              ? 'Codec: ${perf['codec']} (${perf['encoder']})  |  ${perf['measured_fps'] != null ? "${perf['measured_fps']} FPS" : "Target ${perf['configured_target_fps'] ?? 60} FPS"}  |  RTT: ${perf['ping_rtt_ms']} ms  |  Render: ${c.graphicsFallbackMode}'
                              : 'Session: STANDBY  |  Profile: ${perf['active_mode'] ?? c.performanceMode}  |  Preferred Codec: ${perf['codec'] ?? "H265"}  |  Render: ${c.graphicsFallbackMode}',
                          style: DauverseTypography.kpi(p, size: 12, color: p.cyan),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
