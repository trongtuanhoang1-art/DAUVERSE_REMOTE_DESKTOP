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
  final TextEditingController _peerIdCtrl = TextEditingController(text: '892 441 109');

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
    final sec = snap['security'] as Map<String, dynamic>? ?? const {};

    final cpuPct = (hw['cpu_usage_pct'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final ramUsed = (hw['ram_used_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final ramTotal = (hw['ram_total_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final pingMs = perf['ping_rtt_ms']?.toString() ?? '14';
    final aiRunning = ai['running']?.toString() ?? '0';
    final aiCompleted = ai['completed']?.toString() ?? '0';
    final unread = notif['unread_count']?.toString() ?? '0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Executive Quick Connect Hero Banner
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DauverseStatusBadge(
                          label: i18n.t('SẴN SÀNG KẾT NỐI P2P', 'DIRECT P2P READY'),
                          color: p.success,
                        ),
                        const SizedBox(width: 10),
                        DauverseStatusBadge(
                          label: 'AGPL-3.0 • V1.0',
                          color: p.cyan,
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
                        'Kết nối một chạm, truyền hình ảnh mượt 60 FPS, Mini Control không gián đoạn và cầu nối thông báo AI thời gian thực.',
                        'One-touch remote control, low-latency 60 FPS streaming, non-intrusive Mini Control, and live AI Event Bridge.',
                      ),
                      style: DauverseTypography.caption(p, size: 13),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 210,
                      child: TextField(
                        controller: _peerIdCtrl,
                        style: DauverseTypography.kpi(p, size: 15),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: p.surface,
                          prefixIcon: Icon(Icons.desktop_windows, size: 18, color: p.cyan),
                          hintText: 'Remote ID / Host',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: p.border),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => c.selectScreen(DauverseScreenId.remoteSession),
                      icon: const Icon(Icons.bolt, size: 18),
                      label: Text(i18n.t('Kết nối nhanh', 'Quick Connect')),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.cyan,
                        side: BorderSide(color: p.cyan),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => c.selectScreen(DauverseScreenId.fileTransfer),
                      icon: const Icon(Icons.folder_open, size: 17),
                      label: Text(i18n.t('Truyền File', 'File Transfer')),
                    ),
                    const SizedBox(width: 8),
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

          // 6 KPI Executive Strip
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 1100 ? 6 : (constraints.maxWidth > 700 ? 3 : 2);
              final itemW = (constraints.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _kpiTile(p, itemW, i18n.t('Thiết bị tin cậy', 'Trusted Devices'), '2 Online',
                      'HOME-RTX3060 • LAN/P2P', Icons.devices, p.success,
                      onTap: () => c.selectScreen(DauverseScreenId.myDevices)),
                  _kpiTile(p, itemW, 'Ping / RTT', '$pingMs ms',
                      '${perf['connection_route'] ?? 'Direct P2P'} • 60 FPS', Icons.network_check, p.cyan,
                      onTap: () => c.selectScreen(DauverseScreenId.networkDiagnostics)),
                  _kpiTile(p, itemW, i18n.t('Phần cứng (Host)', 'Hardware Status'), 'CPU $cpuPct%',
                      'RAM $ramUsed / $ramTotal GB', Icons.memory, p.blue,
                      onTap: () => c.selectScreen(DauverseScreenId.hardwareMonitor)),
                  _kpiTile(p, itemW, 'AI Running', aiRunning,
                      i18n.t('Claude • Codex • AGY • ComfyUI', 'Active AI Pipelines'), Icons.auto_awesome, p.purple,
                      onTap: () => c.selectScreen(DauverseScreenId.aiLiveStatus)),
                  _kpiTile(p, itemW, 'AI Completed', aiCompleted,
                      i18n.t('Chỉ tính có bằng chứng xác thực', 'Verified evidence only'), Icons.verified, p.success,
                      onTap: () => c.selectScreen(DauverseScreenId.aiLiveStatus)),
                  _kpiTile(p, itemW, i18n.t('Thông báo & Bảo mật', 'Alerts & Shield'), '$unread Unread',
                      sec['allowlist_enforced'] == true ? 'Shield: ENFORCED' : 'Shield: OPEN', Icons.shield, p.warning,
                      onTap: () => c.selectScreen(DauverseScreenId.securityCenter)),
                ],
              );
            },
          ),
          const SizedBox(height: 18),

          // Main 2-column executive workspace
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
                              i18n.t('Máy tính AI được cấp quyền', 'Authorized AI Workstations'),
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
                      _workstationRow(
                        p,
                        i18n,
                        name: 'BOSS-HOME-AI-RIG (Windows 11 Pro)',
                        spec: 'Intel Core i5-12400F • NVIDIA RTX 3060 12GB • 16GB DDR4 • LAN',
                        online: true,
                        ping: '$pingMs ms',
                        onConnect: () => c.selectScreen(DauverseScreenId.remoteSession),
                        onMini: () => c.selectScreen(DauverseScreenId.miniControl),
                        onPower: () => c.selectScreen(DauverseScreenId.smartPower),
                      ),
                      const Divider(height: 22),
                      _workstationRow(
                        p,
                        i18n,
                        name: 'OFFICE-CLIENT-WORKSTATION',
                        spec: 'Windows 11 Enterprise • Receiver & Mini Control Host',
                        online: true,
                        ping: '1 ms (Local)',
                        onConnect: () => c.selectScreen(DauverseScreenId.myDevices),
                        onMini: () => c.selectScreen(DauverseScreenId.notificationCenter),
                        onPower: () => c.selectScreen(DauverseScreenId.securityCenter),
                      ),
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
                              i18n.t('Biểu đồ Tài nguyên & Sự kiện AI', 'Live Telemetry & AI Event Bridge'),
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
                            onPressed: () {
                              c.triggerCornerToastPreview(
                                title: 'Antigravity đã hoàn thành nhiệm vụ',
                                aiSource: 'Antigravity',
                                project: 'DAUVERSE FT004',
                                body: 'Build & Regression Verification hoàn tất an toàn.',
                                verifiedEvidence: '128/128 tests PASS',
                              );
                            },
                            child: Text(i18n.t('Thử Toast AI', 'Test AI Toast'), style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('CPU Telemetry ($cpuPct%)', style: DauverseTypography.caption(p)),
                      const SizedBox(height: 6),
                      DauverseSparkline(values: c.cpuHistory, color: p.cyan),
                      const SizedBox(height: 12),
                      Text('RAM Telemetry ($ramUsed / $ramTotal GB)', style: DauverseTypography.caption(p)),
                      const SizedBox(height: 6),
                      DauverseSparkline(values: c.ramHistory, color: p.purple),
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
    required bool online,
    required String ping,
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
                  DauverseStatusBadge(label: online ? 'ONLINE • $ping' : 'OFFLINE', color: online ? p.success : p.danger),
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
