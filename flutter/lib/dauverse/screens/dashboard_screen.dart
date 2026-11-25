import 'package:flutter/material.dart';
import '../bridge/dauverse_bridge.dart';
import '../l10n/dauverse_i18n.dart';
import '../theme/dauverse_theme.dart';

class DauverseDashboardScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseDashboardScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseDashboardScreen> createState() => _DauverseDashboardScreenState();
}

class _DauverseDashboardScreenState extends State<DauverseDashboardScreen> {
  late final TextEditingController _peerIdCtrl;

  @override
  void initState() {
    super.initState();
    _peerIdCtrl = TextEditingController(text: widget.controller.targetPeerId);
  }

  @override
  void dispose() {
    _peerIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final snap = c.snapshot;
    final hw = snap['hardware'] as Map<String, dynamic>? ?? const {};
    final perf = snap['performance'] as Map<String, dynamic>? ?? const {};
    final ai = snap['ai_summary'] as Map<String, dynamic>? ?? const {};
    final notif = snap['notifications'] as Map<String, dynamic>? ?? const {};
    final secWrap = snap['security'] as Map<String, dynamic>? ?? const {};
    final sec = secWrap['summary'] as Map<String, dynamic>? ?? secWrap;

    final localId = snap['local_peer_id']?.toString() ?? '';
    final bridgeUrl = snap['bridge_endpoint']?.toString() ?? 'http://127.0.0.1:21188/v1/events';
    final sessionConnected = perf['session_connected'] == true;
    final cpuPct = (hw['cpu_usage_pct'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final ramUsed = (hw['ram_used_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final ramTotal = (hw['ram_total_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final pingLabel = sessionConnected ? '${perf['ping_rtt_ms']} ms' : 'IDLE';
    final routeLabel = perf['connection_route']?.toString() ?? 'DISCONNECTED';
    final aiRunning = ai['running']?.toString() ?? '0';
    final aiCompleted = ai['completed']?.toString() ?? '0';
    final unread = notif['unread_count']?.toString() ?? '0';
    final cachedPeers = c.peersProvider?.call() ?? const <Map<String, String>>[];
    final trustedCount = (sec['trusted_devices_count'] as num?)?.toInt() ?? cachedPeers.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  p.cyan.withOpacity(p.isDark ? 0.18 : 0.10),
                  p.blue.withOpacity(p.isDark ? 0.16 : 0.08),
                  p.purple.withOpacity(p.isDark ? 0.18 : 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.cyan.withOpacity(0.45)),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 14,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        DauverseStatusBadge(
                          label: localId.isNotEmpty ? 'LOCAL ID: $localId' : 'ENGINE READY',
                          color: p.success,
                        ),
                        DauverseStatusBadge(
                          label: 'AI BRIDGE: $bridgeUrl',
                          color: p.cyan,
                        ),
                        DauverseStatusBadge(
                          label: 'AGPL-3.0 • V1.0 RC1',
                          color: p.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      i18n.t(
                        'Trung tâm Điều khiển Máy tính AI từ xa — DAUVERSE REMOTE',
                        'Remote AI Workstation Command Center — DAUVERSE REMOTE',
                      ),
                      style: DauverseTypography.heading(p, size: 20),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      i18n.t(
                        'Nhập Peer ID thực tế để khởi chạy phiên kết nối P2P/Relay gốc hoặc truyền file hai chiều trực tiếp.',
                        'Enter a real Peer ID to launch native P2P/Relay remote control or dual-pane file transfer.',
                      ),
                      style: DauverseTypography.caption(p, size: 13),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _peerIdCtrl,
                        onChanged: (v) => c.targetPeerId = v.trim(),
                        style: DauverseTypography.kpi(p, size: 15),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: p.surface,
                          prefixIcon: Icon(Icons.desktop_windows, size: 18, color: p.cyan),
                          hintText: i18n.t('Nhập Peer ID / IP...', 'Enter Peer ID / IP...'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: p.border),
                          ),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => c.launchRealRemoteSession(context, _peerIdCtrl.text),
                      icon: const Icon(Icons.bolt, size: 18),
                      label: Text(i18n.t('Kết nối nhanh', 'Quick Connect')),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.cyan,
                        side: BorderSide(color: p.cyan),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => c.launchRealFileTransfer(context, _peerIdCtrl.text),
                      icon: const Icon(Icons.folder_open, size: 17),
                      label: Text(i18n.t('Truyền File', 'File Transfer')),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.purple,
                        side: BorderSide(color: p.purple),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: c.openClassicRustDeskView,
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: Text(i18n.t('Engine Gốc', 'Native Connector')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 1100 ? 6 : (constraints.maxWidth > 700 ? 3 : 2);
              final itemW = (constraints.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _kpiTile(p, itemW, i18n.t('Thiết bị đã lưu', 'Saved Peers'), '$trustedCount Peers',
                      cachedPeers.isEmpty ? i18n.t('Chưa lưu thiết bị', 'No saved peers yet') : cachedPeers.first['id'] ?? '',
                      Icons.devices, p.success,
                      onTap: () => c.selectScreen(DauverseScreenId.myDevices)),
                  _kpiTile(p, itemW, 'Session RTT', pingLabel,
                      routeLabel, Icons.network_check, p.cyan,
                      onTap: () => c.selectScreen(DauverseScreenId.networkDiagnostics)),
                  _kpiTile(p, itemW, i18n.t('Phần cứng máy này', 'Local Host Sensors'), 'CPU $cpuPct%',
                      'RAM $ramUsed / $ramTotal GB', Icons.memory, p.blue,
                      onTap: () => c.selectScreen(DauverseScreenId.hardwareMonitor)),
                  _kpiTile(p, itemW, 'AI Running', aiRunning,
                      i18n.t('Sự kiện thực qua HTTP 21188', 'Verified Bridge Events'), Icons.auto_awesome, p.purple,
                      onTap: () => c.selectScreen(DauverseScreenId.aiLiveStatus)),
                  _kpiTile(p, itemW, 'AI Completed', aiCompleted,
                      i18n.t('Chỉ tính có chứng cứ xác thực', 'Verified evidence only'), Icons.verified, p.success,
                      onTap: () => c.selectScreen(DauverseScreenId.aiLiveStatus)),
                  _kpiTile(p, itemW, i18n.t('Thông báo & Bảo mật', 'Alerts & Shield'), '$unread Unread',
                      sec['allowlist_enforced'] == true ? 'Shield: ENFORCED' : 'Shield: OPEN', Icons.shield, p.warning,
                      onTap: () => c.selectScreen(DauverseScreenId.securityCenter)),
                ],
              );
            },
          ),
          const SizedBox(height: 18),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: DauverseCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              i18n.t('Danh bạ Thiết bị thực tế (RustDesk Engine)', 'Live Peer Directory (RustDesk Engine)'),
                              style: DauverseTypography.heading(p, size: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => c.selectScreen(DauverseScreenId.miniControl),
                            icon: Icon(Icons.picture_in_picture_alt, size: 16, color: p.cyan),
                            label: Text('Mini Control', style: TextStyle(color: p.cyan)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (cachedPeers.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: p.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: p.border),
                          ),
                          child: Text(
                            i18n.t(
                              'Chưa có thiết bị nào trong lịch sử kết nối cục bộ. Nhập Peer ID vào ô Kết nối nhanh phía trên hoặc mở Engine Gốc để thêm máy ở nhà.',
                              'No peers saved in local connection cache yet. Enter a Peer ID above or open Native Connector to pair your home workstation.',
                            ),
                            style: DauverseTypography.body(p, size: 13),
                          ),
                        )
                      else
                        for (var i = 0; i < cachedPeers.take(4).length; i++) ...[
                          _workstationRow(
                            p,
                            i18n,
                            name: cachedPeers[i]['alias']?.isNotEmpty == true
                                ? cachedPeers[i]['alias']!
                                : '${cachedPeers[i]['hostname'] ?? 'Peer'} (${cachedPeers[i]['id']})',
                            spec: '${cachedPeers[i]['platform'] ?? 'Desktop'} • User: ${cachedPeers[i]['username'] ?? '-'}',
                            id: cachedPeers[i]['id'] ?? '',
                            onConnect: () => c.launchRealRemoteSession(context, cachedPeers[i]['id'] ?? ''),
                            onMini: () {
                              c.targetPeerId = cachedPeers[i]['id'] ?? '';
                              c.selectScreen(DauverseScreenId.miniControl);
                            },
                            onPower: () => c.selectScreen(DauverseScreenId.smartPower),
                          ),
                          if (i + 1 < cachedPeers.take(4).length) const Divider(height: 20),
                        ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: DauverseCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              i18n.t('Biểu đồ Tài nguyên Cục bộ & Kiểm thử AI Bridge', 'Local Host Telemetry & Live AI Bridge Probe'),
                              style: DauverseTypography.heading(p, size: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: p.purple,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => c.sendSignedLoopbackAiProbe(),
                            child: Text(
                              i18n.t('Gửi Probe HMAC thật', 'Send Signed Probe'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Local CPU Telemetry ($cpuPct%)', style: DauverseTypography.caption(p)),
                      const SizedBox(height: 6),
                      DauverseSparkline(values: c.cpuHistory.isEmpty ? const [0, 0] : c.cpuHistory, color: p.cyan),
                      const SizedBox(height: 12),
                      Text('Local RAM Telemetry ($ramUsed / $ramTotal GB)', style: DauverseTypography.caption(p)),
                      const SizedBox(height: 6),
                      DauverseSparkline(values: c.ramHistory.isEmpty ? const [0, 0] : c.ramHistory, color: p.purple),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiTile(
    DauversePalette p,
    double width,
    String title,
    String value,
    String sub,
    IconData icon,
    Color accent, {
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: DauverseCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(title, style: DauverseTypography.caption(p, size: 11), overflow: TextOverflow.ellipsis),
                  ),
                  Icon(icon, size: 18, color: accent),
                ],
              ),
              const SizedBox(height: 8),
              Text(value, style: DauverseTypography.kpi(p, size: 20, color: accent)),
              const SizedBox(height: 4),
              Text(sub, style: DauverseTypography.caption(p, size: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workstationRow(
    DauversePalette p,
    DauverseI18n i18n, {
    required String name,
    required String spec,
    required String id,
    required VoidCallback onConnect,
    required VoidCallback onMini,
    required VoidCallback onPower,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: p.cyan.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.computer, color: p.cyan),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(name, style: DauverseTypography.body(p, size: 14, weight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  DauverseStatusBadge(label: 'ID: $id', color: p.cyan),
                ],
              ),
              const SizedBox(height: 3),
              Text(spec, style: DauverseTypography.caption(p, size: 12)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Mini Control',
          onPressed: onMini,
          icon: Icon(Icons.picture_in_picture_alt, color: p.cyan, size: 20),
        ),
        IconButton(
          tooltip: 'Smart Power',
          onPressed: onPower,
          icon: Icon(Icons.power_settings_new, color: p.warning, size: 20),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: p.blue,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onConnect,
          child: Text(i18n.t('Điều khiển', 'Connect')),
        ),
      ],
    );
  }
}
