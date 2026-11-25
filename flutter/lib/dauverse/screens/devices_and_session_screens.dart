import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../bridge/dauverse_bridge.dart';
import '../l10n/dauverse_i18n.dart';
import '../theme/dauverse_theme.dart';
import '../widgets/floating_toolbar.dart';

class DauverseMyDevicesScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseMyDevicesScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseMyDevicesScreen> createState() => _DauverseMyDevicesScreenState();
}

class _DauverseMyDevicesScreenState extends State<DauverseMyDevicesScreen> {
  late final TextEditingController _peerCtrl;

  @override
  void initState() {
    super.initState();
    _peerCtrl = TextEditingController(text: widget.controller.targetPeerId);
  }

  @override
  void dispose() {
    _peerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final peers = c.peersProvider?.call() ?? const <Map<String, String>>[];

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
                        'Đồng bộ trực tiếp với danh bạ RustDesk Engine • Mọi Unattended Access đều có kiểm toán và thu hồi tức thì.',
                        'Backed directly by RustDesk Engine peer cache • Enforces mutual auth, audit logging, and instant revocation.',
                      ),
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: c.openClassicRustDeskView,
                icon: Icon(Icons.grid_view, size: 16, color: p.cyan),
                label: Text(i18n.t('Mở danh bạ RustDesk Engine', 'Open Native Peer Grid'),
                    style: TextStyle(color: p.cyan)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _peerCtrl,
                    onChanged: (v) => c.targetPeerId = v.trim(),
                    style: DauverseTypography.kpi(p, size: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: i18n.t('Peer ID / IP đích', 'Target Peer ID / IP'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                  onPressed: () => c.launchRealRemoteSession(context, _peerCtrl.text),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(i18n.t('Kết nối Phiên Thực', 'Connect Live Session')),
                ),
                OutlinedButton.icon(
                  onPressed: () => c.launchRealFileTransfer(context, _peerCtrl.text),
                  icon: Icon(Icons.swap_horiz, size: 16, color: p.purple),
                  label: Text(i18n.t('Truyền File hai chiều', 'Dual-Pane Transfer'),
                      style: TextStyle(color: p.purple)),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    c.targetPeerId = _peerCtrl.text.trim();
                    c.selectScreen(DauverseScreenId.miniControl);
                  },
                  icon: Icon(Icons.picture_in_picture_alt, size: 16, color: p.cyan),
                  label: Text('Mini Control', style: TextStyle(color: p.cyan)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (peers.isEmpty)
            DauverseCard(
              child: Text(
                i18n.t(
                  'Danh sách thiết bị cục bộ hiện trống (0 peer đã lưu). Không hiển thị thiết bị mẫu giả mạo — nhập Peer ID thật phía trên để kết nối và tự động lưu vào danh bạ Engine.',
                  'Local peer list is currently empty (0 saved peers). Zero fake placeholder devices shown — connect to a real Peer ID above to populate the native peer cache.',
                ),
                style: DauverseTypography.body(p, size: 13),
              ),
            )
          else
            for (final peer in peers) ...[
              _deviceCard(
                context,
                p,
                i18n,
                id: peer['id'] ?? '',
                name: (peer['alias'] ?? '').isNotEmpty ? peer['alias']! : (peer['hostname'] ?? peer['id'] ?? 'Peer'),
                os: peer['platform'] ?? 'Desktop',
                user: peer['username'] ?? '-',
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _deviceCard(
    BuildContext context,
    DauversePalette p,
    DauverseI18n i18n, {
    required String id,
    required String name,
    required String os,
    required String user,
  }) {
    final c = widget.controller;
    return DauverseCard(
      accentBorder: p.cyan.withOpacity(0.45),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DauverseStatusBadge(label: 'SAVED PEER', color: p.cyan),
                  const SizedBox(width: 10),
                  Text(name, style: DauverseTypography.heading(p, size: 16)),
                  const SizedBox(width: 12),
                  Text('ID: $id', style: DauverseTypography.kpi(p, size: 13, color: p.cyan)),
                ],
              ),
              const SizedBox(height: 6),
              Text('$os • User: $user', style: DauverseTypography.caption(p, size: 12)),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  c.targetPeerId = id;
                  c.selectScreen(DauverseScreenId.miniControl);
                },
                icon: Icon(Icons.picture_in_picture_alt, size: 16, color: p.cyan),
                label: Text('Mini Control', style: TextStyle(color: p.cyan)),
              ),
              OutlinedButton.icon(
                onPressed: () => c.launchRealFileTransfer(context, id),
                icon: Icon(Icons.swap_horiz, size: 16, color: p.purple),
                label: Text(i18n.t('Truyền File', 'Transfer'), style: TextStyle(color: p.purple)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                onPressed: () => c.launchRealRemoteSession(context, id),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(i18n.t('Kết nối một chạm', 'One-Touch Connect')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DauverseRemoteSessionScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseRemoteSessionScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseRemoteSessionScreen> createState() => _DauverseRemoteSessionScreenState();
}

class _DauverseRemoteSessionScreenState extends State<DauverseRemoteSessionScreen> {
  late final TextEditingController _sessionPeerCtrl;

  @override
  void initState() {
    super.initState();
    _sessionPeerCtrl = TextEditingController(text: widget.controller.targetPeerId);
  }

  @override
  void dispose() {
    _sessionPeerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final perf = c.snapshot['performance'] as Map<String, dynamic>? ?? const {};
    final connected = perf['session_connected'] == true;

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
                            'CHỈ BÁO BẮT BUỘC: ĐÃ BẬT CỜ GHI HÌNH CÔNG KHAI (KHÔNG GHI HÌNH BÍ MẬT)',
                            'MANDATORY INDICATOR: EXPLICIT RECORDING FLAG ARMED',
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
                  c.targetPeerId.isNotEmpty
                      ? 'Target Peer: ${c.targetPeerId}  •  Preset: ${c.selectedResolutionPreset}'
                      : i18n.t('Chưa có phiên truyền hình đang mở — Nhập Peer ID bên dưới',
                          'No Active Remote Stream — Enter Target Peer ID Below'),
                  style: DauverseTypography.heading(DauversePalette.dark, size: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  'Profile: ${c.performanceMode}  •  Input: ${c.viewOnlySession ? "VIEW ONLY" : "INTERACTIVE"}  •  Audio: ${c.audioEnabled ? "ON" : "MUTED"}',
                  style: DauverseTypography.kpi(DauversePalette.dark, size: 13, color: p.cyan),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _sessionPeerCtrl,
                    onChanged: (v) => c.targetPeerId = v.trim(),
                    style: DauverseTypography.kpi(DauversePalette.dark, size: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      hintText: i18n.t('Nhập Peer ID đích...', 'Enter Remote Peer ID...'),
                      hintStyle: const TextStyle(color: Colors.white54),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                      onPressed: () => c.launchRealRemoteSession(context, _sessionPeerCtrl.text),
                      icon: const Icon(Icons.connected_tv, size: 18),
                      label: Text(i18n.t('Khởi chạy Phiên RustDesk Thực', 'Connect Native RustDesk Session')),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: p.cyan, side: BorderSide(color: p.cyan)),
                      onPressed: c.openClassicRustDeskView,
                      icon: const Icon(Icons.tab, size: 18),
                      label: Text(i18n.t('Mở giao diện Tab gốc', 'Open Native Tab View')),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: p.purple, side: BorderSide(color: p.purple)),
                      onPressed: () => c.selectScreen(DauverseScreenId.miniControl),
                      icon: const Icon(Icons.picture_in_picture_alt, size: 18),
                      label: Text(i18n.t('Chuyển sang Mini Control', 'Switch to Mini Control')),
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
                          connected
                              ? '${perf['connection_route']}  |  FPS: ${perf['fps']}  |  RTT: ${perf['ping_rtt_ms']} ms  |  Bitrate: ${perf['bitrate_kbps']} kbps  |  ${perf['codec']}'
                              : 'DISCONNECTED (0 Active Streams)  |  Configured Codec: ${perf['codec'] ?? "H265"} (${perf['encoder'] ?? "NVENC"})',
                          overflow: TextOverflow.ellipsis,
                          style: DauverseTypography.kpi(DauversePalette.dark, size: 12, color: const Color(0xFF38BDF8)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(i18n.t('Đa màn hình • High DPI • UAC Ready', 'Multi-monitor • High DPI • UAC Ready'),
                          style: DauverseTypography.caption(DauversePalette.dark, size: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DauverseFloatingToolbar(controller: c),
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

  Future<void> _applyWindowOpacity(double val) async {
    setState(() => widget.controller.miniControlOpacity = val);
    try {
      await windowManager.setOpacity(val);
    } catch (_) {}
  }

  Future<void> _applySnapCorner(Alignment al) async {
    setState(() => _snapCorner = al);
    if (widget.controller.miniControlWindowDetached) {
      try {
        await windowManager.setAlignment(al);
      } catch (_) {}
    }
  }

  Future<void> _toggleDetachedMiniWindow(bool detach) async {
    final c = widget.controller;
    setState(() => c.miniControlWindowDetached = detach);
    c.syncMiniControlEngineState(
      minimized: detach && c.miniControlCollapsedStrip,
      idle: detach && c.miniControlMode != 'INTERACTIVE',
    );
    try {
      if (detach) {
        await windowManager.setAlwaysOnTop(c.miniControlAlwaysOnTop);
        await windowManager.setSize(
          c.miniControlCollapsedStrip ? const Size(520, 88) : const Size(480, 320),
        );
        await windowManager.setAlignment(_snapCorner);
      } else {
        await windowManager.setOpacity(1.0);
        await windowManager.setSize(const Size(1440, 900));
        await windowManager.setAlignment(Alignment.center);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final hw = c.snapshot['hardware'] as Map<String, dynamic>? ?? const {};
    final perf = c.snapshot['performance'] as Map<String, dynamic>? ?? const {};
    final ai = c.snapshot['ai_summary'] as Map<String, dynamic>? ?? const {};
    final notif = c.snapshot['notifications'] as Map<String, dynamic>? ?? const {};
    final connected = perf['session_connected'] == true;

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
                        'Điều khiển kích thước cửa sổ OS thật (windowManager), hạ FPS khi rảnh, không chiếm quyền bàn phím.',
                        'Drives real OS window geometry/opacity/Always-On-Top via windowManager and syncs idle FPS throttle to Rust.',
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
                      label: Text(i18n.t('Thu nhỏ cửa sổ OS thật (PiP)', 'Resize OS Window to PiP')),
                      selected: c.miniControlWindowDetached,
                      onSelected: _toggleDetachedMiniWindow,
                    ),
                    FilterChip(
                      label: Text(i18n.t('Luôn nổi (Always On Top)', 'Always On Top')),
                      selected: c.miniControlAlwaysOnTop,
                      onSelected: _applyWindowAlwaysOnTop,
                    ),
                    FilterChip(
                      label: Text(i18n.t('Chỉ hiện trạng thái (Tắt Video)', 'Status-Only (No Video)')),
                      selected: c.miniControlStatusOnlyNoVideo,
                      onSelected: (v) {
                        setState(() => c.miniControlStatusOnlyNoVideo = v);
                        c.syncMiniControlEngineState(minimized: v, idle: true);
                      },
                    ),
                    FilterChip(
                      label: Text(i18n.t('Thu thành thanh mảnh', 'Collapse to Strip')),
                      selected: c.miniControlCollapsedStrip,
                      onSelected: (v) {
                        setState(() => c.miniControlCollapsedStrip = v);
                        c.syncMiniControlEngineState(minimized: v);
                      },
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
                  onSelected: (_) {
                    setState(() => c.miniControlMode = m.$1);
                    c.syncMiniControlEngineState(idle: m.$1 != 'INTERACTIVE');
                  },
                ),
              const SizedBox(width: 12),
              Text(i18n.t('Độ trong suốt:', 'Opacity:'), style: DauverseTypography.caption(p)),
              SizedBox(
                width: 130,
                child: Slider(
                  min: 0.45,
                  max: 1.0,
                  value: c.miniControlOpacity,
                  onChanged: _applyWindowOpacity,
                ),
              ),
              PopupMenuButton<Alignment>(
                tooltip: i18n.t('Snap góc màn hình', 'Snap to screen corner'),
                onSelected: _applySnapCorner,
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
                      onDoubleTap: () async {
                        await _toggleDetachedMiniWindow(false);
                        c.selectScreen(DauverseScreenId.remoteSession);
                      },
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
                                    child: Text(
                                      connected
                                          ? '${c.targetPeerId} • CONNECTED • ${perf['ping_rtt_ms']}ms'
                                          : 'LOCAL MONITOR • NO STREAM',
                                      overflow: TextOverflow.ellipsis,
                                      style: DauverseTypography.kpi(DauversePalette.dark, size: 12, color: p.cyan),
                                    ),
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
                                          '${c.targetPeerId.isEmpty ? "LOCAL HOST" : c.targetPeerId}  •  ${c.miniControlMode}',
                                          style: DauverseTypography.body(DauversePalette.dark,
                                              size: 12, weight: FontWeight.w700),
                                        ),
                                      ),
                                      DauverseStatusBadge(
                                        label: connected ? 'STREAM ${perf['ping_rtt_ms']}ms' : 'NO STREAM',
                                        color: connected ? p.success : p.warning,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (!c.miniControlStatusOnlyNoVideo &&
                                      (c.miniControlMode == 'PREVIEW' || c.miniControlMode == 'INTERACTIVE'))
                                    Container(
                                      height: 128,
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
                                          Icon(Icons.desktop_windows, color: p.cyan, size: 28),
                                          const SizedBox(height: 6),
                                          Text(
                                            c.targetPeerId.isEmpty
                                                ? i18n.t('Chưa gắn Peer ID • Nháy đúp để mở màn hình phiên',
                                                    'No Peer Selected • Double-click for Session View')
                                                : i18n.t('Peer ${c.targetPeerId} • Nhấn Kết nối thực hoặc nháy đúp',
                                                    'Target ${c.targetPeerId} • Double-click for Full Session'),
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
