import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../bridge/dauverse_bridge.dart';
import '../l10n/dauverse_i18n.dart';
import '../theme/dauverse_theme.dart';
import '../widgets/floating_toolbar.dart';

class DauverseMyDevicesScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseMyDevicesScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final i18n = controller.i18n;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i18n.t('Thiết bị tin cậy & Kết nối một chạm', 'Trusted Devices & One-Touch Access'),
                        style: DauverseTypography.heading(p, size: 19)),
                    Text(
                      i18n.t(
                        'Mọi thiết bị Unattended Access đều phải nằm trong Allowlist, có nhật ký kiểm toán và có thể thu hồi tức thì.',
                        'All Unattended Access hosts enforce mutual auth, device allowlist, audit logging, and instant revocation.',
                      ),
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.openClassicRustDeskView,
                    icon: Icon(Icons.grid_view, size: 16, color: p.cyan),
                    label: Text(i18n.t('Mở danh bạ RustDesk Engine', 'Open Native Peer Grid'),
                        style: TextStyle(color: p.cyan)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _deviceCard(
            p,
            i18n,
            id: '892 441 109',
            name: 'BOSS-HOME-AI-RIG',
            os: 'Windows 11 Pro 64-bit • Headless IDD Ready',
            hw: 'Intel Core i5-12400F • ASUS PRIME H610M-K D4 • RTX 3060 12GB • 16GB RAM',
            route: 'Direct P2P (LAN / NAT Traversal) • 14 ms',
            online: true,
            tags: const ['Claude Code', 'Codex QA', 'Antigravity', 'ComfyUI', 'Unattended'],
            onConnect: () => controller.selectScreen(DauverseScreenId.remoteSession),
            onMini: () => controller.selectScreen(DauverseScreenId.miniControl),
            onWol: () => controller.invokePowerAction(
              'WAKE_ON_LAN',
              mac: 'AA:BB:CC:11:22:33',
              target: '127.0.0.1:9',
            ),
            onTransfer: () => controller.selectScreen(DauverseScreenId.fileTransfer),
          ),
          const SizedBox(height: 14),
          _deviceCard(
            p,
            i18n,
            id: '410 882 301',
            name: 'SECONDARY-RENDER-NODE',
            os: 'Windows 10 Pro 64-bit',
            hw: 'Standby Render / Backup Node • Wake-on-LAN Enabled',
            route: 'Relay Fallback Ready',
            online: false,
            tags: const ['Wake-on-LAN', 'View-Only Default'],
            onConnect: () => controller.selectScreen(DauverseScreenId.remoteSession),
            onMini: () => controller.selectScreen(DauverseScreenId.miniControl),
            onWol: () => controller.invokePowerAction(
              'WAKE_ON_LAN',
              mac: 'DE:AD:BE:EF:10:20',
              target: '127.0.0.1:9',
            ),
            onTransfer: () => controller.selectScreen(DauverseScreenId.fileTransfer),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(
    DauversePalette p,
    DauverseI18n i18n, {
    required String id,
    required String name,
    required String os,
    required String hw,
    required String route,
    required bool online,
    required List<String> tags,
    required VoidCallback onConnect,
    required VoidCallback onMini,
    required VoidCallback onWol,
    required VoidCallback onTransfer,
  }) {
    return DauverseCard(
      accentBorder: online ? p.cyan.withOpacity(0.45) : p.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DauverseStatusBadge(
                    label: online ? 'ONLINE' : 'OFFLINE (SLEEP / SHUTDOWN)',
                    color: online ? p.success : p.warning,
                  ),
                  const SizedBox(width: 10),
                  Text(name, style: DauverseTypography.heading(p, size: 16)),
                  const SizedBox(width: 12),
                  Text('ID: $id', style: DauverseTypography.kpi(p, size: 13, color: p.cyan)),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: onWol,
                    icon: Icon(Icons.flash_on, size: 16, color: p.warning),
                    label: Text('Wake-on-LAN', style: TextStyle(color: p.warning)),
                  ),
                  OutlinedButton.icon(
                    onPressed: onMini,
                    icon: Icon(Icons.picture_in_picture_alt, size: 16, color: p.cyan),
                    label: Text('Mini Control', style: TextStyle(color: p.cyan)),
                  ),
                  OutlinedButton.icon(
                    onPressed: onTransfer,
                    icon: Icon(Icons.swap_horiz, size: 16, color: p.purple),
                    label: Text(i18n.t('Truyền File', 'Transfer'), style: TextStyle(color: p.purple)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                    onPressed: onConnect,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(i18n.t('Kết nối một chạm', 'One-Touch Connect')),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('$os  •  $route', style: DauverseTypography.body(p, size: 12)),
          const SizedBox(height: 3),
          Text(hw, style: DauverseTypography.caption(p, size: 12)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: tags
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: p.border),
                      ),
                      child: Text(t, style: DauverseTypography.caption(p, size: 11)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class DauverseRemoteSessionScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseRemoteSessionScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = controller;
    final i18n = c.i18n;
    final monitors = [
      'Display 1: 1920x1080 @ 60Hz (NVENC H.265)',
      'Display 2: 2560x1440 @ 60Hz (Secondary)',
      'Virtual Display (IDD Headless): 1920x1080 @ 60Hz',
    ];

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF050811),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.recordingActive ? p.danger : p.cyan.withOpacity(0.45), width: 1.5),
            ),
            child: Column(
              children: [
                if (c.recordingActive)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.danger.withOpacity(0.9),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.fiber_manual_record, size: 14, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          i18n.t(
                            'CHỈ BÁO BẮT BUỘC: ĐANG GHI HÌNH PHIÊN LÀM VIỆC (KHÔNG GHI HÌNH BÍ MẬT)',
                            'MANDATORY INDICATOR: SESSION SCREEN RECORDING IS ACTIVE',
                          ),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                const DauverseEmblem(size: 56),
                const SizedBox(height: 14),
                Text(
                  'BOSS-HOME-AI-RIG • ${monitors[c.selectedMonitorIndex % monitors.length]}',
                  style: DauverseTypography.heading(p.isDark ? p : DauversePalette.dark, size: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mode: ${c.performanceMode}  •  Input: ${c.viewOnlySession ? "VIEW ONLY" : "INTERACTIVE (VN Unicode + Win Shortcuts)"}  •  Audio: ${c.audioEnabled ? "ON" : "MUTED"}',
                  style: DauverseTypography.kpi(DauversePalette.dark, size: 13, color: p.cyan),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                      onPressed: c.openClassicRustDeskView,
                      icon: const Icon(Icons.connected_tv, size: 18),
                      label: Text(i18n.t('Mở Khung truyền hình RustDesk Native', 'Launch Native RustDesk Stream Tab')),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: p.cyan, side: BorderSide(color: p.cyan)),
                      onPressed: () {
                        c.viewOnlySession = !c.viewOnlySession;
                        c.refreshSnapshot();
                      },
                      icon: Icon(c.viewOnlySession ? Icons.visibility : Icons.mouse, size: 18),
                      label: Text(c.viewOnlySession
                          ? i18n.t('Chuyển sang Tương tác', 'Switch to Interactive')
                          : i18n.t('Chuyển sang Chỉ xem', 'Switch to View Only')),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: p.purple, side: BorderSide(color: p.purple)),
                      onPressed: () => c.selectScreen(DauverseScreenId.miniControl),
                      icon: const Icon(Icons.picture_in_picture_alt, size: 18),
                      label: Text(i18n.t('Thu nhỏ sang Mini Control', 'Shrink to Mini Control')),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0B1120),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Direct P2P Encrypted  |  FPS: 60  |  RTT: 14 ms  |  Bitrate: 6.8 Mbps  |  NVENC H.265',
                          overflow: TextOverflow.ellipsis,
                          style: DauverseTypography.kpi(DauversePalette.dark, size: 12, color: const Color(0xFF38BDF8)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(i18n.t('Đa màn hình • High DPI • UAC • Lock Screen', 'Multi-monitor • High DPI • UAC Ready'),
                          style: DauverseTypography.caption(DauversePalette.dark, size: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DauverseFloatingToolbar(controller: controller),
      ],
    );
  }
}

class DauverseMiniControlScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseMiniControlScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseMiniControlScreen> createState() => _DauverseMiniControlScreenState();
}

class _DauverseMiniControlScreenState extends State<DauverseMiniControlScreen> {
  Alignment _snapCorner = Alignment.bottomRight;

  Future<void> _applyWindowAlwaysOnTop(bool val) async {
    setState(() => widget.controller.miniControlAlwaysOnTop = val);
    try {
      await windowManager.setAlwaysOnTop(val);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final hw = c.snapshot['hardware'] as Map<String, dynamic>? ?? const {};
    final ai = c.snapshot['ai_summary'] as Map<String, dynamic>? ?? const {};
    final notif = c.snapshot['notifications'] as Map<String, dynamic>? ?? const {};

    const modes = [
      ('PREVIEW', 'Preview Mode'),
      ('INTERACTIVE', 'Interactive Mode'),
      ('AI_MONITOR', 'AI Monitor Mode'),
      ('HARDWARE_MONITOR', 'Hardware Monitor Mode'),
      ('COMPACT_STATUS', 'Compact Status Mode'),
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i18n.t('Mini Control — Cửa sổ nổi chuyên dụng cho máy công ty', 'Mini Control — Non-Intrusive Always-On-Top PiP'),
                        style: DauverseTypography.heading(p, size: 19)),
                    Text(
                      i18n.t(
                        'Tự động hạ FPS xuống <=5 FPS khi không thao tác, không chiếm quyền bàn phím, nháy đúp mở toàn phiên.',
                        'Auto-throttles FPS when idle, never steals keyboard focus, double-click expands to full session.',
                      ),
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilterChip(
                      label: Text(i18n.t('Luôn nổi (Always On Top)', 'Always On Top')),
                      selected: c.miniControlAlwaysOnTop,
                      onSelected: _applyWindowAlwaysOnTop,
                    ),
                    FilterChip(
                      label: Text(i18n.t('Chỉ hiện trạng thái (Tắt truyền hình)', 'Status-Only (No Video Stream)')),
                      selected: c.miniControlStatusOnlyNoVideo,
                      onSelected: (v) => setState(() => c.miniControlStatusOnlyNoVideo = v),
                    ),
                    FilterChip(
                      label: Text(i18n.t('Thu thành thanh mảnh', 'Collapse to Strip')),
                      selected: c.miniControlCollapsedStrip,
                      onSelected: (v) => setState(() => c.miniControlCollapsedStrip = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final m in modes)
                ChoiceChip(
                  label: Text(m.$2),
                  selected: c.miniControlMode == m.$1,
                  onSelected: (_) => setState(() => c.miniControlMode = m.$1),
                ),
              const SizedBox(width: 12),
              Text(i18n.t('Độ trong suốt:', 'Opacity:'), style: DauverseTypography.caption(p)),
              SizedBox(
                width: 130,
                child: Slider(
                  min: 0.45,
                  max: 1.0,
                  value: c.miniControlOpacity,
                  onChanged: (v) => setState(() => c.miniControlOpacity = v),
                ),
              ),
              PopupMenuButton<Alignment>(
                tooltip: i18n.t('Snap góc màn hình', 'Snap to screen corner'),
                onSelected: (al) => setState(() => _snapCorner = al),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: Alignment.topLeft, child: Text('Snap: Top-Left')),
                  PopupMenuItem(value: Alignment.topRight, child: Text('Snap: Top-Right')),
                  PopupMenuItem(value: Alignment.bottomLeft, child: Text('Snap: Bottom-Left')),
                  PopupMenuItem(value: Alignment.bottomRight, child: Text('Snap: Bottom-Right')),
                ],
                child: Chip(
                  avatar: Icon(Icons.crop_free, size: 16, color: p.cyan),
                  label: Text(i18n.t('Snap góc', 'Snap Corner')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: p.surfaceElevated.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.border),
              ),
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: _snapCorner,
                child: Opacity(
                  opacity: c.miniControlOpacity,
                  child: FocusScope(
                    canRequestFocus: c.miniControlMode == 'INTERACTIVE',
                    child: GestureDetector(
                      onDoubleTap: () => c.selectScreen(DauverseScreenId.remoteSession),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: c.miniControlCollapsedStrip ? 520 : 440,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1120),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p.cyan, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: c.miniControlCollapsedStrip
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const DauverseEmblem(size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text('HOME-RTX3060 • ONLINE • 14ms',
                                        overflow: TextOverflow.ellipsis,
                                        style: DauverseTypography.kpi(DauversePalette.dark, size: 12, color: p.success)),
                                  ),
                                  Text(
                                    'Run:${ai['running'] ?? 0} | Unread:${notif['unread_count'] ?? 0}',
                                    style: DauverseTypography.kpi(DauversePalette.dark, size: 11, color: p.cyan),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => setState(() => c.miniControlCollapsedStrip = false),
                                    child: Icon(Icons.open_in_full, size: 16, color: p.cyan),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const DauverseEmblem(size: 22),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'BOSS-HOME-AI-RIG  •  ${c.miniControlMode}',
                                          style: DauverseTypography.body(DauversePalette.dark,
                                              size: 12, weight: FontWeight.w700),
                                        ),
                                      ),
                                      DauverseStatusBadge(label: 'ONLINE • 14ms', color: p.success),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (!c.miniControlStatusOnlyNoVideo &&
                                      (c.miniControlMode == 'PREVIEW' || c.miniControlMode == 'INTERACTIVE'))
                                    Container(
                                      height: 138,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF070B14), Color(0xFF172554)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFF1E3A8A)),
                                      ),
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.desktop_windows, color: p.cyan, size: 30),
                                          const SizedBox(height: 6),
                                          Text(
                                            i18n.t(
                                              'Nháy đúp để mở toàn màn hình • Tự giảm <=12 FPS khi rảnh',
                                              'Double-click for Full Session • Idle FPS Throttle Active',
                                            ),
                                            style: DauverseTypography.caption(DauversePalette.dark, size: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 6,
                                    children: [
                                      _miniStat('CPU', '${(hw['cpu_usage_pct'] as num?)?.toStringAsFixed(1) ?? "0"}%', p.cyan),
                                      _miniStat('RAM', '${(hw['ram_used_gb'] as num?)?.toStringAsFixed(1) ?? "0"}GB', p.blue),
                                      _miniStat('GPU', hw['gpu_usage_pct'] != null ? '${hw['gpu_usage_pct']}%' : 'N/A', p.purple),
                                      _miniStat('VRAM', hw['vram_used_mb'] != null ? '${hw['vram_used_mb']}MB' : 'N/A', p.purple),
                                      _miniStat('Temp', hw['gpu_temp_c'] != null ? '${hw['gpu_temp_c']}°C' : 'N/A', p.warning),
                                    ],
                                  ),
                                  const Divider(color: Color(0xFF1E293B), height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'AI Run: ${ai['running'] ?? 0} • Done: ${ai['completed'] ?? 0} • Approval: ${ai['waiting_approval'] ?? 0}',
                                          overflow: TextOverflow.ellipsis,
                                          style: DauverseTypography.kpi(DauversePalette.dark, size: 11, color: p.success),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      DauverseStatusBadge(
                                        label: '${notif['unread_count'] ?? 0} Unread',
                                        color: p.warning,
                                      ),
                                    ],
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
        ],
      ),
    );
  }

  Widget _miniStat(String k, String v, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$k: $v', style: DauverseTypography.kpi(DauversePalette.dark, size: 11, color: c)),
    );
  }
}
