import 'dart:math' as math;
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
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t('Thiết bị tin cậy & Kết nối một chạm', 'Trusted Devices & One-Touch Access'),
                      style: DauverseTypography.heading(p, size: 19),
                    ),
                    Text(
                      i18n.t(
                        'Đồng bộ trực tiếp với danh bạ phiên bản cục bộ • Mọi Unattended Access đều có kiểm toán và thu hồi tức thì.',
                        'Backed directly by native peer cache • Enforces mutual auth, audit logging, and instant revocation.',
                      ),
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: c.openClassicRustDeskView,
                icon: Icon(Icons.grid_view_rounded, size: 16, color: p.cyan),
                label: Text(
                  i18n.t('Mở danh bạ Engine Gốc', 'Open Native Peer Grid'),
                  style: TextStyle(color: p.cyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
                  child: TextField(
                    controller: _peerCtrl,
                    onChanged: (v) => c.targetPeerId = DauverseController.normalizePeerTarget(v),
                    onSubmitted: (v) => c.launchRealRemoteSession(context, v),
                    style: DauverseTypography.kpi(p, size: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: i18n.t('ID / IP thiết bị đích', 'Target Device ID / IP'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final txt = await c.pasteFromClipboard();
                    if (txt.isNotEmpty) {
                      setState(() => _peerCtrl.text = txt);
                    }
                  },
                  icon: Icon(Icons.content_paste_rounded, size: 16, color: p.cyan),
                  label: Text(i18n.t('Dán', 'Paste'), style: TextStyle(color: p.cyan)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                  onPressed: () => c.launchRealRemoteSession(context, _peerCtrl.text),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(i18n.t('KẾT NỐI NGAY', 'CONNECT NOW')),
                ),
                OutlinedButton.icon(
                  onPressed: () => c.launchRealFileTransfer(context, _peerCtrl.text),
                  icon: Icon(Icons.swap_horiz_rounded, size: 16, color: p.purple),
                  label: Text(
                    i18n.t('Truyền File hai chiều', 'Dual-Pane Transfer'),
                    style: TextStyle(color: p.purple),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    c.targetPeerId = DauverseController.normalizePeerTarget(_peerCtrl.text);
                    c.selectScreen(DauverseScreenId.miniControl);
                  },
                  icon: Icon(Icons.picture_in_picture_alt_rounded, size: 16, color: p.cyan),
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
                  'Danh sách thiết bị cục bộ hiện trống (0 peer đã lưu). Không hiển thị thiết bị mẫu giả mạo — nhập ID hoặc IP thật phía trên để kết nối và tự động lưu.',
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
                name: (peer['alias'] ?? '').isNotEmpty
                    ? peer['alias']!
                    : (peer['hostname'] ?? peer['id'] ?? 'Workstation'),
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
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DauverseStatusBadge(label: 'SAVED PEER', color: p.cyan),
                    Text(
                      name,
                      style: DauverseTypography.heading(p, size: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SelectableText(
                      'ID: $id',
                      style: DauverseTypography.kpi(p, size: 13.5, color: p.cyan),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '$os • User: $user',
                  style: DauverseTypography.caption(p, size: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => c.copyToClipboardWithFeedback(
                  context,
                  id,
                  keyTag: 'peer_$id',
                  displayLabel: 'ID $id',
                ),
                icon: Icon(Icons.copy_rounded, size: 15, color: p.cyan),
                label: Text(i18n.t('Sao chép ID', 'Copy ID'), style: TextStyle(color: p.cyan)),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  c.targetPeerId = id;
                  c.selectScreen(DauverseScreenId.miniControl);
                },
                icon: Icon(Icons.picture_in_picture_alt_rounded, size: 16, color: p.cyan),
                label: Text('Mini Control', style: TextStyle(color: p.cyan)),
              ),
              OutlinedButton.icon(
                onPressed: () => c.launchRealFileTransfer(context, id),
                icon: Icon(Icons.swap_horiz_rounded, size: 16, color: p.purple),
                label: Text(i18n.t('Truyền File', 'Transfer'), style: TextStyle(color: p.purple)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                onPressed: () => c.launchRealRemoteSession(context, id),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(i18n.t('Kết nối ngay', 'Connect Now')),
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

    return LayoutBuilder(
      builder: (context, constraints) {
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
                  border: Border.all(
                    color: c.recordingActive ? p.danger : p.cyan.withOpacity(0.45),
                    width: 1.5,
                  ),
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
                            Flexible(
                              child: Text(
                                i18n.t(
                                  'CHỈ BÁO BẮT BUỘC: ĐÃ BẬT CỜ GHI HÌNH CÔNG KHAI (KHÔNG GHI HÌNH BÍ MẬT)',
                                  'MANDATORY INDICATOR: EXPLICIT RECORDING FLAG ARMED',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const DauverseEmblem(size: 52),
                                const SizedBox(height: 14),
                                Text(
                                  c.targetPeerId.isNotEmpty
                                      ? 'Target Peer: ${c.targetPeerId}  •  Preset: ${c.selectedResolutionPreset}'
                                      : i18n.t(
                                          'Khởi chạy cửa sổ Phiên điều khiển từ xa — Nhập ID / IP bên dưới',
                                          'Launch Remote Control Session — Enter Target ID / IP Below',
                                        ),
                                  textAlign: TextAlign.center,
                                  style: DauverseTypography.heading(DauversePalette.dark, size: 17.5),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Profile: ${c.performanceMode}  •  Graphics: ${c.graphicsFallbackMode}  •  Audio: ${c.audioEnabled ? "ON" : "MUTED"}',
                                  textAlign: TextAlign.center,
                                  style: DauverseTypography.kpi(DauversePalette.dark, size: 12.5, color: p.cyan),
                                ),
                                const SizedBox(height: 16),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 340),
                                  child: TextField(
                                    controller: _sessionPeerCtrl,
                                    onChanged: (v) => c.targetPeerId = DauverseController.normalizePeerTarget(v),
                                    onSubmitted: (v) => c.launchRealRemoteSession(context, v),
                                    style: DauverseTypography.kpi(DauversePalette.dark, size: 16),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      filled: true,
                                      fillColor: const Color(0xFF0F172A),
                                      hintText: i18n.t('Nhập ID / IP đích...', 'Enter Remote ID / IP...'),
                                      hintStyle: const TextStyle(color: Colors.white54),
                                      suffixIcon: IconButton(
                                        tooltip: i18n.t('Dán từ Clipboard', 'Paste'),
                                        icon: Icon(Icons.content_paste_rounded, size: 18, color: p.cyan),
                                        onPressed: () async {
                                          final txt = await c.pasteFromClipboard();
                                          if (txt.isNotEmpty) {
                                            setState(() => _sessionPeerCtrl.text = txt);
                                          }
                                        },
                                      ),
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
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: p.blue,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => c.launchRealRemoteSession(context, _sessionPeerCtrl.text),
                                      icon: const Icon(Icons.bolt_rounded, size: 18),
                                      label: Text(i18n.t('KẾT NỐI NGAY', 'CONNECT NOW')),
                                    ),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: p.cyan,
                                        side: BorderSide(color: p.cyan),
                                      ),
                                      onPressed: c.openClassicRustDeskView,
                                      icon: const Icon(Icons.tab_rounded, size: 18),
                                      label: Text(i18n.t('Mở Engine Gốc', 'Open Native Tab View')),
                                    ),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: p.purple,
                                        side: BorderSide(color: p.purple),
                                      ),
                                      onPressed: () => c.selectScreen(DauverseScreenId.miniControl),
                                      icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 18),
                                      label: Text(i18n.t('Chuyển sang Mini Control', 'Switch to Mini Control')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
                                  ? '${perf['connection_route']}  |  ${perf['measured_fps'] != null ? "FPS: ${perf['measured_fps']}" : "Target ${perf['configured_target_fps'] ?? 60} FPS"}  |  RTT: ${perf['ping_rtt_ms']} ms  |  ${perf['codec']}'
                                  : 'STANDBY (0 Active Streams)  |  Codec: ${perf['codec'] ?? "H265"} (${perf['encoder'] ?? "NVENC"})  |  Render: ${c.graphicsFallbackMode}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DauverseTypography.kpi(
                                DauversePalette.dark,
                                size: 12,
                                color: const Color(0xFF38BDF8),
                              ),
                            ),
                          ),
                          if (constraints.maxWidth >= 680) ...[
                            const SizedBox(width: 12),
                            Text(
                              i18n.t('Đa màn hình • High DPI • UAC Ready', 'Multi-monitor • High DPI • UAC Ready'),
                              style: DauverseTypography.caption(DauversePalette.dark, size: 11),
                            ),
                          ],
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
      },
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
          c.miniControlCollapsedStrip ? const Size(480, 88) : const Size(460, 320),
        );
        await windowManager.setAlignment(_snapCorner);
      } else {
        await windowManager.setOpacity(1.0);
        await windowManager.setSize(const Size(1280, 780));
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardW = math.max(240.0, math.min(c.miniControlCollapsedStrip ? 520.0 : 440.0, constraints.maxWidth - 64));
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i18n.t(
                            'Mini Control — Cửa sổ nổi chuyên dụng cho máy công ty',
                            'Mini Control — Non-Intrusive Always-On-Top PiP',
                          ),
                          style: DauverseTypography.heading(p, size: 19),
                        ),
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
                  Wrap(
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(i18n.t('Độ trong suốt:', 'Opacity:'), style: DauverseTypography.caption(p)),
                      SizedBox(
                        width: 120,
                        child: Slider(
                          min: 0.45,
                          max: 1.0,
                          value: c.miniControlOpacity,
                          onChanged: _applyWindowOpacity,
                        ),
                      ),
                    ],
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
                      avatar: Icon(Icons.crop_free_rounded, size: 16, color: p.cyan),
                      label: Text(i18n.t('Snap góc', 'Snap Corner')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 290),
                decoration: BoxDecoration(
                  color: p.surfaceElevated.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.border),
                ),
                padding: const EdgeInsets.all(16),
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
                          width: maxCardW,
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
                                            : 'LOCAL MONITOR • STANDBY',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: DauverseTypography.kpi(DauversePalette.dark, size: 12, color: p.cyan),
                                      ),
                                    ),
                                    Text(
                                      'Run:${ai['running'] ?? 0} | Unread:${notif['unread_count'] ?? 0}',
                                      style: DauverseTypography.kpi(DauversePalette.dark, size: 11, color: p.cyan),
                                    ),
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: i18n.t('Mở rộng Mini Control', 'Expand Mini Control'),
                                      child: InkWell(
                                        onTap: () => setState(() => c.miniControlCollapsedStrip = false),
                                        child: Icon(Icons.open_in_full_rounded, size: 16, color: p.cyan),
                                      ),
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
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: DauverseTypography.body(
                                              DauversePalette.dark,
                                              size: 12,
                                              weight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        DauverseStatusBadge(
                                          label: connected ? 'STREAM ${perf['ping_rtt_ms']}ms' : 'STANDBY',
                                          color: connected ? p.success : p.warning,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if (!c.miniControlStatusOnlyNoVideo &&
                                        (c.miniControlMode == 'PREVIEW' || c.miniControlMode == 'INTERACTIVE'))
                                      Container(
                                        height: 116,
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                                            Icon(Icons.desktop_windows_rounded, color: p.cyan, size: 26),
                                            const SizedBox(height: 6),
                                            Text(
                                              c.targetPeerId.isEmpty
                                                  ? i18n.t(
                                                      'Chưa chọn thiết bị từ xa • Nháy đúp để mở màn hình phiên',
                                                      'No Peer Selected • Double-click for Session View',
                                                    )
                                                  : i18n.t(
                                                      'Thiết bị ${c.targetPeerId} • Bấm Kết nối thực hoặc nháy đúp',
                                                      'Target ${c.targetPeerId} • Double-click for Full Session',
                                                    ),
                                              textAlign: TextAlign.center,
                                              style: DauverseTypography.caption(DauversePalette.dark, size: 11),
                                            ),
                                            if (c.targetPeerId.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: 26,
                                                child: ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: p.blue,
                                                    foregroundColor: Colors.white,
                                                    visualDensity: VisualDensity.compact,
                                                  ),
                                                  onPressed: () => c.launchRealRemoteSession(context, c.targetPeerId),
                                                  child: Text(
                                                    i18n.t('Mở luồng thực', 'Launch Stream'),
                                                    style: const TextStyle(fontSize: 11),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
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
                                            maxLines: 1,
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
            ],
          ),
        );
      },
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
