import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final visibleOpacity = (c.toolbarAutoHide && !_hovered) ? 0.22 : 1.0;

    return FocusScope(
      canRequestFocus: false,
      child: Stack(
        children: [
          Positioned(
            top: _dragOffset.dy.clamp(4.0, 420.0),
            left: c.toolbarPinnedTop ? null : _dragOffset.dx.clamp(8.0, 900.0),
            right: c.toolbarPinnedTop ? null : null,
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
                                    onTap: () => setState(() => _fullScreen = true)),
                                _btn(p, Icons.fullscreen_exit, i18n.t('Cửa sổ', 'Window Mode'),
                                    active: !_fullScreen,
                                    onTap: () => setState(() => _fullScreen = false)),
                                _btn(p, Icons.picture_in_picture_alt, 'Mini Control',
                                    onTap: () => c.selectScreen(DauverseScreenId.miniControl)),
                                _btn(p, Icons.push_pin_outlined, i18n.t('Ghim cửa sổ', 'Pin Window'),
                                    active: _pinnedWindow,
                                    onTap: () => setState(() => _pinnedWindow = !_pinnedWindow)),
                                _btn(p, Icons.content_paste, 'Clipboard',
                                    onTap: () => c.selectScreen(DauverseScreenId.clipboardSettings)),
                                _btn(p, Icons.swap_horiz, i18n.t('Truyền file', 'File Transfer'),
                                    onTap: () => c.selectScreen(DauverseScreenId.fileTransfer)),
                                _btn(
                                    p,
                                    c.audioEnabled ? Icons.volume_up : Icons.volume_off,
                                    i18n.t('Âm thanh', 'Audio'),
                                    active: c.audioEnabled,
                                    onTap: () => setState(() => c.audioEnabled = !c.audioEnabled)),
                                _btn(p, Icons.monitor, i18n.t('Chuyển màn hình', 'Monitor Switch'),
                                    onTap: () => setState(
                                        () => c.selectedMonitorIndex = (c.selectedMonitorIndex + 1) % 3)),
                                _btn(p, Icons.aspect_ratio, i18n.t('Độ phân giải', 'Resolution'),
                                    onTap: () {}),
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
                                  c.triggerCornerToastPreview(
                                    title: i18n.t('Đã chụp ảnh màn hình phiên', 'Session Screenshot Saved'),
                                    aiSource: 'SessionTools',
                                    project: 'HOME-RTX3060',
                                    body: 'capture_${DateTime.now().millisecondsSinceEpoch}.png',
                                  );
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
                                  c.triggerCornerToastPreview(
                                    title: 'SAS Ctrl+Alt+Del',
                                    aiSource: 'WindowsService',
                                    project: 'HOME-RTX3060',
                                    body: i18n.t('Đã gửi tín hiệu SAS hợp lệ qua Windows Service.',
                                        'Dispatched OS-supported SAS via Windows Service.'),
                                  );
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
                                    onTap: () => c.selectScreen(DauverseScreenId.dashboard)),
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
                  'Codec: H265 (NVENC)  |  60 FPS  |  RTT: 14 ms  |  6.8 Mbps  |  Loss: 0.0%  |  Direct P2P',
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
