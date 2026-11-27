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
  bool _showTempPassword = false;

  @override
  void initState() {
    super.initState();
    _peerIdCtrl = TextEditingController(text: widget.controller.targetPeerId);
  }

  @override
  void didUpdateWidget(covariant DauverseDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_peerIdCtrl.text.isEmpty && widget.controller.targetPeerId.isNotEmpty) {
      _peerIdCtrl.text = widget.controller.targetPeerId;
    }
  }

  @override
  void dispose() {
    _peerIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _openConnectionDialog(BuildContext context) async {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final dialogCtrl = TextEditingController(text: _peerIdCtrl.text);
    bool fileTransferOnly = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: p.cyan.withOpacity(0.5)),
          ),
          title: Row(
            children: [
              const DauverseEmblem(size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  i18n.t('Thiết lập Phiên Kết nối Từ xa', 'Remote Session Connection Dialog'),
                  style: DauverseTypography.heading(p, size: 17),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t(
                    'Nhập ID DAUVERSE (9–10 chữ số) hoặc địa chỉ IP LAN khi Direct IP đã được phê duyệt.',
                    'Enter target DAUVERSE ID or authorized LAN IP.',
                  ),
                  style: DauverseTypography.caption(p, size: 12.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dialogCtrl,
                  autofocus: true,
                  style: DauverseTypography.kpi(p, size: 18),
                  decoration: InputDecoration(
                    labelText: i18n.t('ID / IP Thiết bị đích', 'Remote Device ID / IP'),
                    filled: true,
                    fillColor: p.surfaceElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      tooltip: i18n.t('Dán từ Clipboard', 'Paste from Clipboard'),
                      icon: Icon(Icons.content_paste_rounded, color: p.cyan),
                      onPressed: () async {
                        final txt = await c.pasteFromClipboard();
                        if (txt.isNotEmpty) {
                          dialogCtrl.text = txt;
                          _peerIdCtrl.text = txt;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: fileTransferOnly,
                  onChanged: (v) => setModalState(() => fileTransferOnly = v ?? false),
                  title: Text(
                    i18n.t(
                      'Mở trực tiếp chế độ Truyền File hai chiều',
                      'Open directly in Dual-Pane File Transfer mode',
                    ),
                    style: DauverseTypography.body(p, size: 13),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(i18n.t('Hủy', 'Cancel')),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: p.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final target = dialogCtrl.text.trim();
                _peerIdCtrl.text = target;
                Navigator.of(ctx).pop();
                if (fileTransferOnly) {
                  c.launchRealFileTransfer(context, target);
                } else {
                  c.launchRealRemoteSession(context, target);
                }
              },
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: Text(i18n.t('KẾT NỐI NGAY', 'CONNECT NOW')),
            ),
          ],
        ),
      ),
    );
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
    final conn = snap['connection_identity'] as Map<String, dynamic>? ?? const {};
    final readiness = snap['windows_access_readiness'] as Map<String, dynamic>? ?? const {};

    final rawId = (conn['connection_id'] ?? snap['local_peer_id'] ?? '').toString().trim();
    final formattedId = (conn['formatted_id'] ?? rawId).toString().trim();
    final tempPw = (conn['temporary_password'] ?? '').toString();
    final lanIfaces = (conn['lan_interfaces'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final lanIpsFallback = (conn['lan_ips'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final publicIp = conn['public_ip']?.toString();
    final publicIpStatus = conn['public_ip_status']?.toString() ?? 'OPT_IN_NOT_QUERIED';
    final directIpEnabled = conn['direct_ip_access_enabled'] == true;
    final directIpPort = conn['direct_ip_port']?.toString() ?? '21118';
    final connStatus = (conn['connection_status'] ?? 'ONLINE').toString().toUpperCase();
    final activeSessionsCount = (conn['active_sessions_count'] as num?)?.toInt() ?? 0;

    final displayVersion = snap['display_version']?.toString() ?? kDauverseDisplayVersion;
    final bridgeUrl = snap['bridge_endpoint']?.toString() ?? 'http://127.0.0.1:21188/v1/events';
    final sessionConnected = perf['session_connected'] == true || activeSessionsCount > 0;
    final cpuPct = (hw['cpu_usage_pct'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final ramUsed = (hw['ram_used_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final ramTotal = (hw['ram_total_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final pingLabel = sessionConnected ? '${perf['ping_rtt_ms']} ms' : i18n.t('Chờ kết nối', 'Standby');
    final routeShort = sessionConnected
        ? i18n.t('Đang truyền luồng ($activeSessionsCount phiên)', 'Active Stream ($activeSessionsCount)')
        : i18n.t('0 phiên đang điều khiển', '0 Active Streams');
    final aiRunning = ai['running']?.toString() ?? '0';
    final aiCompleted = ai['completed']?.toString() ?? '0';
    final unread = notif['unread_count']?.toString() ?? '0';
    final cachedPeers = c.peersProvider?.call() ?? const <Map<String, String>>[];
    final trustedCount = (sec['trusted_devices_count'] as num?)?.toInt() ?? cachedPeers.length;
    final preloginReady = readiness['pre_login_winlogon_ready'] == true;

    return LayoutBuilder(
      builder: (context, viewport) {
        final maxW = viewport.maxWidth;
        final pad = maxW < 820 ? 14.0 : 20.0;
        final twoColumnHero = maxW >= 1020;
        final twoColumnBottom = maxW >= 980;

        return SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Command Status Strip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.cyan.withOpacity(p.isDark ? 0.16 : 0.08),
                      p.blue.withOpacity(p.isDark ? 0.14 : 0.07),
                      p.purple.withOpacity(p.isDark ? 0.14 : 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.cyan.withOpacity(0.42)),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DauverseConnectionStatusPill(
                          key: const Key('dashboard-connection-status-pill'),
                          statusCode: connStatus,
                          isVi: c.isVietnamese,
                        ),
                        DauverseStatusBadge(
                          label: 'AGPL-3.0 • $displayVersion',
                          color: p.purple,
                          icon: Icons.verified_outlined,
                        ),
                        DauverseStatusBadge(
                          label: preloginReady
                              ? i18n.t('Winlogon Pre-Login: SẴN SÀNG', 'Winlogon Pre-Login: READY')
                              : i18n.t('Chế độ Phiên Người dùng', 'User Session Mode'),
                          color: preloginReady ? p.success : p.cyan,
                          icon: Icons.shield_outlined,
                        ),
                        if (c.lastCopiedNotice.isNotEmpty)
                          DauverseStatusBadge(
                            key: const Key('copied-feedback-badge'),
                            label: c.lastCopiedNotice,
                            color: p.success,
                            icon: Icons.check_circle_rounded,
                          ),
                      ],
                    ),
                    Tooltip(
                      message: 'Loopback HMAC-SHA256 AI Event Gateway',
                      child: DauverseStatusBadge(
                        label: 'AI BRIDGE: $bridgeUrl',
                        color: p.cyan,
                        icon: Icons.hub_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // MANDATORY CONNECTION HERO: Left = Host Identity (ID 36px, LAN IP 26px, Public IP, Temp PW) | Right = Remote Connect CTA
              if (twoColumnHero)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildLocalIdentityCard(
                        context: context,
                        p: p,
                        c: c,
                        i18n: i18n,
                        rawId: rawId,
                        formattedId: formattedId,
                        tempPw: tempPw,
                        lanIfaces: lanIfaces,
                        lanIpsFallback: lanIpsFallback,
                        publicIp: publicIp,
                        publicIpStatus: publicIpStatus,
                        directIpEnabled: directIpEnabled,
                        directIpPort: directIpPort,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: _buildRemoteConnectCard(context, p, c, i18n, connStatus),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLocalIdentityCard(
                      context: context,
                      p: p,
                      c: c,
                      i18n: i18n,
                      rawId: rawId,
                      formattedId: formattedId,
                      tempPw: tempPw,
                      lanIfaces: lanIfaces,
                      lanIpsFallback: lanIpsFallback,
                      publicIp: publicIp,
                      publicIpStatus: publicIpStatus,
                      directIpEnabled: directIpEnabled,
                      directIpPort: directIpPort,
                    ),
                    const SizedBox(height: 16),
                    _buildRemoteConnectCard(context, p, c, i18n, connStatus),
                  ],
                ),

              const SizedBox(height: 18),

              // Responsive KPI Grid (Never narrower than 200px per card — zero truncated status text!)
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final cols = w >= 1260 ? 6 : (w >= 820 ? 3 : (w >= 480 ? 2 : 1));
                  final itemW = (w - (cols - 1) * 12) / cols;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _kpiTile(
                        p,
                        itemW,
                        i18n.t('Thiết bị đã lưu', 'Saved Peers'),
                        '$trustedCount Peers',
                        cachedPeers.isEmpty
                            ? i18n.t('Chưa lưu thiết bị', 'No saved peers yet')
                            : (cachedPeers.first['id'] ?? ''),
                        Icons.devices_rounded,
                        p.success,
                        onTap: () => c.selectScreen(DauverseScreenId.myDevices),
                      ),
                      _kpiTile(
                        p,
                        itemW,
                        i18n.t('Độ trễ Phiên', 'Session RTT'),
                        pingLabel,
                        routeShort,
                        Icons.network_check_rounded,
                        p.cyan,
                        onTap: () => c.selectScreen(DauverseScreenId.networkDiagnostics),
                      ),
                      _kpiTile(
                        p,
                        itemW,
                        i18n.t('Phần cứng máy này', 'Local Host Sensors'),
                        'CPU $cpuPct%',
                        'RAM $ramUsed / $ramTotal GB',
                        Icons.memory_rounded,
                        p.blue,
                        onTap: () => c.selectScreen(DauverseScreenId.hardwareMonitor),
                      ),
                      _kpiTile(
                        p,
                        itemW,
                        i18n.t('AI đang chạy', 'AI Running'),
                        aiRunning,
                        i18n.t('Cổng HTTP 21188 xác thực', 'Verified Bridge Events'),
                        Icons.auto_awesome_rounded,
                        p.purple,
                        onTap: () => c.selectScreen(DauverseScreenId.aiLiveStatus),
                      ),
                      _kpiTile(
                        p,
                        itemW,
                        i18n.t('AI hoàn tất', 'AI Completed'),
                        aiCompleted,
                        i18n.t('Có chứng cứ HMAC v3', 'Verified evidence only'),
                        Icons.verified_rounded,
                        p.success,
                        onTap: () => c.selectScreen(DauverseScreenId.aiLiveStatus),
                      ),
                      _kpiTile(
                        p,
                        itemW,
                        i18n.t('Thông báo & Bảo mật', 'Alerts & Shield'),
                        '$unread Unread',
                        sec['allowlist_enforced'] == true ? 'Shield: ENFORCED' : 'Shield: OPEN',
                        Icons.shield_rounded,
                        p.warning,
                        onTap: () => c.selectScreen(DauverseScreenId.securityCenter),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),

              // Bottom Directory & Local Telemetry (Responsive 2-column or Vertical Stack)
              if (twoColumnBottom)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildPeerDirectoryCard(context, p, c, i18n, cachedPeers),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: _buildTelemetryCard(p, c, i18n, cpuPct, ramUsed, ramTotal),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPeerDirectoryCard(context, p, c, i18n, cachedPeers),
                    const SizedBox(height: 16),
                    _buildTelemetryCard(p, c, i18n, cpuPct, ramUsed, ramTotal),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocalIdentityCard({
    required BuildContext context,
    required DauversePalette p,
    required DauverseController c,
    required DauverseI18n i18n,
    required String rawId,
    required String formattedId,
    required String tempPw,
    required List<Map<String, dynamic>> lanIfaces,
    required List<String> lanIpsFallback,
    required String? publicIp,
    required String publicIpStatus,
    required bool directIpEnabled,
    required String directIpPort,
  }) {
    final displayId = formattedId.isNotEmpty
        ? formattedId
        : i18n.t('Đang đồng bộ ID...', 'Syncing ID...');
    final hasRealId = rawId.isNotEmpty;
    final maskedPw = tempPw.isEmpty
        ? '••••••••'
        : (_showTempPassword ? tempPw : '•' * tempPw.length.clamp(6, 12));

    final effectiveLanList = lanIfaces.isNotEmpty
        ? lanIfaces
        : lanIpsFallback
            .map((ip) => <String, dynamic>{
                  'interface_name': 'LAN',
                  'friendly_name': 'LAN',
                  'ipv4': ip,
                  'is_default_route': false,
                })
            .toList();

    return DauverseCard(
      accentBorder: p.cyan.withOpacity(0.55),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, color: p.cyan, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  i18n.t(
                    'THÔNG TIN KẾT NỐI CỦA MÁY NÀY',
                    'THIS WORKSTATION — CONNECTION IDENTITY',
                  ),
                  style: DauverseTypography.heading(p, size: 14, color: p.cyan),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Tooltip(
                message: directIpEnabled
                    ? i18n.t('Direct IP Access đang bật trên cổng $directIpPort', 'Direct IP Access enabled on port $directIpPort')
                    : i18n.t('Direct IP Access tắt mặc định để bảo vệ an ninh mạng', 'Direct IP Access disabled by default for security'),
                child: DauverseStatusBadge(
                  label: directIpEnabled
                      ? 'Direct IP: ON (:$directIpPort)'
                      : i18n.t('Direct IP: TẮT (An toàn)', 'Direct IP: OFF (Safe)'),
                  color: directIpEnabled ? p.warning : p.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. CONNECTION ID (36px — within mandatory 32-40px spec!)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: p.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.cyan.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t('ID KẾT NỐI (CONNECTION ID)', 'CONNECTION ID'),
                  style: DauverseTypography.caption(p, size: 11.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 160),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          displayId,
                          key: const Key('dashboard-connection-id-text'),
                          style: DauverseTypography.kpi(
                            p,
                            size: 36,
                            letterSpacing: 1.2,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('copy-connection-id-btn'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.cyan,
                        side: BorderSide(color: p.cyan.withOpacity(0.7)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: hasRealId
                          ? () => c.copyToClipboardWithFeedback(
                                context,
                                rawId,
                                keyTag: 'conn_id',
                                displayLabel: 'ID $formattedId',
                              )
                          : null,
                      icon: Icon(
                        c.lastCopiedKey == 'conn_id' ? Icons.check_rounded : Icons.copy_rounded,
                        size: 16,
                      ),
                      label: Text(
                        c.lastCopiedKey == 'conn_id'
                            ? i18n.t('Đã sao chép', 'Copied')
                            : i18n.t('Sao chép ID', 'Copy ID'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. LAN IP ADDRESSES (26px — within mandatory 24-28px spec, per-IP 1-click Copy!)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lan_outlined, size: 15, color: p.cyan),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        i18n.t('ĐỊA CHỈ IP LAN (MẠNG NỘI BỘ)', 'LOCAL AREA NETWORK (LAN IP)'),
                        style: DauverseTypography.caption(p, size: 11.5, weight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (effectiveLanList.isEmpty)
                  Text(
                    i18n.t(
                      'Chưa phát hiện giao diện IPv4 LAN đang hoạt động (Không dữ liệu giả).',
                      'No active non-loopback LAN IPv4 interface detected.',
                    ),
                    style: DauverseTypography.body(p, size: 13, color: p.textSecondary),
                  )
                else
                  for (var idx = 0; idx < effectiveLanList.length; idx++) ...[
                    Builder(
                      builder: (_) {
                        final item = effectiveLanList[idx];
                        final ip = item['ipv4']?.toString() ?? '';
                        final nic = (item['friendly_name'] ?? item['interface_name'] ?? 'LAN').toString();
                        final isDef = item['is_default_route'] == true;
                        final tag = 'lan_ip_$ip';
                        return Padding(
                          padding: EdgeInsets.only(bottom: idx + 1 < effectiveLanList.length ? 8 : 0),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: SelectableText(
                                      ip,
                                      key: Key('lan-ip-text-$ip'),
                                      style: DauverseTypography.kpi(
                                        p,
                                        size: 26,
                                        color: p.cyan,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                  DauverseStatusBadge(
                                    label: isDef ? '$nic • Primary' : nic,
                                    color: isDef ? p.success : p.blue,
                                  ),
                                ],
                              ),
                              OutlinedButton.icon(
                                key: Key('copy-lan-ip-$ip'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: p.blue,
                                  side: BorderSide(color: p.blue.withOpacity(0.65)),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => c.copyToClipboardWithFeedback(
                                  context,
                                  ip,
                                  keyTag: tag,
                                  displayLabel: 'IP LAN $ip',
                                ),
                                icon: Icon(
                                  c.lastCopiedKey == tag ? Icons.check_rounded : Icons.copy_rounded,
                                  size: 15,
                                ),
                                label: Text(
                                  c.lastCopiedKey == tag
                                      ? i18n.t('Đã sao chép', 'Copied')
                                      : i18n.t('Sao chép', 'Copy'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. PUBLIC IP (Clearly separated from ID & LAN IP; Opt-In only, 1-click Copy!)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: p.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t('ĐỊA CHỈ IP PUBLIC (WAN — TÙY CHỌN)', 'PUBLIC WAN IP (OPT-IN)'),
                      style: DauverseTypography.caption(p, size: 11, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    if (publicIp != null && publicIp.isNotEmpty)
                      SelectableText(
                        publicIp,
                        key: const Key('public-ip-text'),
                        style: DauverseTypography.kpi(p, size: 20, color: p.purple),
                      )
                    else
                      Text(
                        publicIpStatus == 'UNAVAILABLE'
                            ? i18n.t('Không khả dụng (Mạng nội bộ / Proxy)', 'Unavailable (Offline / Proxy)')
                            : i18n.t(
                                'Chưa truy vấn ngoài (Bảo vệ quyền riêng tư mặc định)',
                                'Not queried automatically (Privacy-first default)',
                              ),
                        style: DauverseTypography.caption(p, size: 12),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (publicIp != null && publicIp.isNotEmpty)
                      OutlinedButton.icon(
                        key: const Key('copy-public-ip-btn'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.purple,
                          side: BorderSide(color: p.purple.withOpacity(0.65)),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => c.copyToClipboardWithFeedback(
                          context,
                          publicIp,
                          keyTag: 'pub_ip',
                          displayLabel: 'IP Public $publicIp',
                        ),
                        icon: Icon(
                          c.lastCopiedKey == 'pub_ip' ? Icons.check_rounded : Icons.copy_rounded,
                          size: 15,
                        ),
                        label: Text(
                          c.lastCopiedKey == 'pub_ip'
                              ? i18n.t('Đã sao chép', 'Copied')
                              : i18n.t('Sao chép', 'Copy'),
                        ),
                      ),
                    TextButton.icon(
                      key: const Key('probe-public-ip-btn'),
                      onPressed: c.isBusy ? null : c.probePublicIpOptIn,
                      icon: c.isBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.public_rounded, size: 16, color: p.purple),
                      label: Text(
                        i18n.t('Kiểm tra IP Public', 'Check Public IP'),
                        style: TextStyle(color: p.purple, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 4. TEMPORARY PASSWORD (Show/Hide, 1-click Copy -> "Đã sao chép", Regenerate!)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t('MẬT KHẨU TẠM THỜI (TEMPORARY PASSWORD)', 'TEMPORARY PASSWORD'),
                      style: DauverseTypography.caption(p, size: 11.5, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      maskedPw,
                      key: const Key('temp-password-display'),
                      style: DauverseTypography.kpi(
                        p,
                        size: 22,
                        letterSpacing: _showTempPassword ? 1.5 : 2.5,
                        color: _showTempPassword ? p.warning : p.textPrimary,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    IconButton(
                      key: const Key('toggle-temp-pw-btn'),
                      tooltip: _showTempPassword
                          ? i18n.t('Ẩn mật khẩu tạm thời', 'Hide temporary password')
                          : i18n.t('Hiện mật khẩu tạm thời', 'Show temporary password'),
                      onPressed: () => setState(() => _showTempPassword = !_showTempPassword),
                      icon: Icon(
                        _showTempPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: p.cyan,
                        size: 20,
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('copy-temp-pw-btn'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.cyan,
                        side: BorderSide(color: p.cyan.withOpacity(0.65)),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: tempPw.isNotEmpty
                          ? () => c.copyToClipboardWithFeedback(
                                context,
                                tempPw,
                                keyTag: 'temp_pw',
                                displayLabel: i18n.t('Mật khẩu tạm thời', 'Temporary Password'),
                              )
                          : null,
                      icon: Icon(
                        c.lastCopiedKey == 'temp_pw' ? Icons.check_rounded : Icons.copy_rounded,
                        size: 15,
                      ),
                      label: Text(
                        c.lastCopiedKey == 'temp_pw'
                            ? i18n.t('Đã sao chép', 'Copied')
                            : i18n.t('Sao chép', 'Copy'),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('regen-temp-pw-btn'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.warning,
                        side: BorderSide(color: p.warning.withOpacity(0.7)),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: c.regenerateTemporaryPassword,
                      icon: const Icon(Icons.autorenew_rounded, size: 16),
                      label: Text(i18n.t('Tạo mới', 'Regenerate')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteConnectCard(
    BuildContext context,
    DauversePalette p,
    DauverseController c,
    DauverseI18n i18n,
    String connStatus,
  ) {
    return DauverseCard(
      accentBorder: p.blue.withOpacity(0.6),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rocket_launch_rounded, color: p.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  i18n.t(
                    'ĐIỀU KHIỂN THIẾT BỊ TỪ XA',
                    'CONNECT TO REMOTE WORKSTATION',
                  ),
                  style: DauverseTypography.heading(p, size: 15, color: p.blue),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            i18n.t(
              'Nhập ID kết nối hoặc địa chỉ IP của máy tính đích để điều khiển màn hình thời gian thực hoặc truyền dữ liệu hai chiều.',
              'Enter the remote workstation Connection ID or IP address to launch real-time remote desktop or file transfer.',
            ),
            style: DauverseTypography.caption(p, size: 12.5),
          ),
          const SizedBox(height: 16),

          // Large, easy-to-use Remote ID / IP Input + 1-click Paste button
          TextField(
            key: const Key('remote-target-input'),
            controller: _peerIdCtrl,
            onChanged: (v) {
              c.targetPeerId = DauverseController.normalizePeerTarget(v);
              setState(() {});
            },
            onSubmitted: (v) => c.launchRealRemoteSession(context, v),
            style: DauverseTypography.kpi(p, size: 22, letterSpacing: 0.8),
            decoration: InputDecoration(
              filled: true,
              fillColor: p.surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              prefixIcon: Icon(Icons.desktop_windows_rounded, size: 22, color: p.cyan),
              hintText: i18n.t('Nhập ID hoặc IP thiết bị từ xa...', 'Enter Remote ID or IP...'),
              hintStyle: DauverseTypography.body(p, size: 15, color: p.textSecondary),
              suffixIcon: _peerIdCtrl.text.isNotEmpty
                  ? IconButton(
                      tooltip: i18n.t('Xóa ô nhập', 'Clear'),
                      icon: Icon(Icons.clear_rounded, size: 18, color: p.textSecondary),
                      onPressed: () {
                        _peerIdCtrl.clear();
                        c.targetPeerId = '';
                        setState(() {});
                      },
                    )
                  : null,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.cyan.withOpacity(0.45), width: 1.2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.cyan, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Prominent Paste + KẾT NỐI NGAY Primary CTA
          Row(
            children: [
              OutlinedButton.icon(
                key: const Key('paste-target-btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.cyan,
                  side: BorderSide(color: p.cyan.withOpacity(0.75)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final txt = await c.pasteFromClipboard();
                  if (txt.isNotEmpty) {
                    setState(() => _peerIdCtrl.text = txt);
                  }
                },
                icon: const Icon(Icons.content_paste_go_rounded, size: 19),
                label: Text(
                  i18n.t('Dán', 'Paste'),
                  style: DauverseTypography.body(p, size: 14, weight: FontWeight.w700, color: p.cyan),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: p.ctaGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: p.blue.withOpacity(0.32),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    key: const Key('connect-now-cta-btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => c.launchRealRemoteSession(context, _peerIdCtrl.text),
                    icon: const Icon(Icons.bolt_rounded, size: 22),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        i18n.t('KẾT NỐI NGAY', 'CONNECT NOW'),
                        style: const TextStyle(
                          fontFamily: DauverseTypography.uiFont,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Secondary Action Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.cyan,
                  side: BorderSide(color: p.cyan.withOpacity(0.55)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => c.launchRealFileTransfer(context, _peerIdCtrl.text),
                icon: const Icon(Icons.folder_open_rounded, size: 17),
                label: Text(i18n.t('Truyền File', 'File Transfer')),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.blue,
                  side: BorderSide(color: p.blue.withOpacity(0.55)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _openConnectionDialog(context),
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: Text(i18n.t('Tùy chọn kết nối', 'Connect Options')),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.purple,
                  side: BorderSide(color: p.purple.withOpacity(0.55)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: c.openClassicRustDeskView,
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: Text(i18n.t('Engine Gốc', 'Native Connector')),
              ),
            ],
          ),
          const Divider(height: 26),

          // Graphics Compatibility Quick Selector (Phase A Heterogeneous GPU Safety)
          Row(
            children: [
              Icon(Icons.display_settings_rounded, size: 16, color: p.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  i18n.t(
                    'Chế độ Tương thích Đồ họa (Chống màn hình đen):',
                    'Graphics Compatibility Mode (Anti-Black-Screen):',
                  ),
                  style: DauverseTypography.caption(p, size: 11.5, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: Text(i18n.t('PixelBuffer Chuẩn (Mặc định)', 'PixelBuffer Safe (Default)')),
                selected: c.graphicsFallbackMode == 'PIXEL_BUFFER_SAFE',
                onSelected: (_) => c.setGraphicsFallbackMode('PIXEL_BUFFER_SAFE', restoreHwcodec: true),
              ),
              ChoiceChip(
                label: Text(i18n.t('Canvas Phần mềm (An toàn tối đa)', 'Software Canvas Fallback')),
                selected: c.graphicsFallbackMode == 'SOFTWARE_CANVAS_FALLBACK',
                onSelected: (_) => c.setGraphicsFallbackMode('SOFTWARE_CANVAS_FALLBACK'),
              ),
              ChoiceChip(
                label: Text(i18n.t('GPU D3D11 Zero-Copy', 'GPU D3D11 Zero-Copy')),
                selected: c.graphicsFallbackMode == 'GPU_D3D11_ZERO_COPY',
                onSelected: (_) => c.setGraphicsFallbackMode('GPU_D3D11_ZERO_COPY', restoreHwcodec: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeerDirectoryCard(
    BuildContext context,
    DauversePalette p,
    DauverseController c,
    DauverseI18n i18n,
    List<Map<String, String>> cachedPeers,
  ) {
    return DauverseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                i18n.t('Danh bạ Thiết bị thực tế', 'Live Saved Peer Directory'),
                style: DauverseTypography.heading(p, size: 16),
              ),
              TextButton.icon(
                onPressed: () => c.selectScreen(DauverseScreenId.miniControl),
                icon: Icon(Icons.picture_in_picture_alt_rounded, size: 16, color: p.cyan),
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
                  'Chưa có thiết bị nào trong lịch sử kết nối cục bộ. Nhập ID hoặc IP vào ô ĐIỀU KHIỂN THIẾT BỊ TỪ XA phía trên để kết nối ngay.',
                  'No peers saved in local connection cache yet. Enter a Remote ID or IP above and click CONNECT NOW.',
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
                    : '${cachedPeers[i]['hostname'] ?? 'Workstation'} (${cachedPeers[i]['id']})',
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
    );
  }

  Widget _buildTelemetryCard(
    DauversePalette p,
    DauverseController c,
    DauverseI18n i18n,
    String cpuPct,
    String ramUsed,
    String ramTotal,
  ) {
    return DauverseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                i18n.t('Tài nguyên Máy cục bộ & AI Bridge', 'Local Host Telemetry & AI Bridge'),
                style: DauverseTypography.heading(p, size: 16),
              ),
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
          Text('CPU ($cpuPct%)', style: DauverseTypography.caption(p)),
          const SizedBox(height: 6),
          DauverseSparkline(
            values: c.cpuHistory.isEmpty ? const [0, 0] : c.cpuHistory,
            color: p.cyan,
          ),
          const SizedBox(height: 12),
          Text('RAM ($ramUsed / $ramTotal GB)', style: DauverseTypography.caption(p)),
          const SizedBox(height: 6),
          DauverseSparkline(
            values: c.ramHistory.isEmpty ? const [0, 0] : c.ramHistory,
            color: p.purple,
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
                    child: Text(
                      title,
                      style: DauverseTypography.caption(p, size: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(icon, size: 18, color: accent),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: DauverseTypography.kpi(p, size: 20, color: accent)),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                style: DauverseTypography.caption(p, size: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.cyan.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.computer_rounded, color: p.cyan),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DauverseTypography.body(p, size: 14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: $id • $spec',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DauverseTypography.caption(p, size: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Mini Control',
              onPressed: onMini,
              icon: Icon(Icons.picture_in_picture_alt_rounded, color: p.cyan, size: 20),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Smart Power',
              onPressed: onPower,
              icon: Icon(Icons.power_settings_new_rounded, color: p.warning, size: 20),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: p.blue,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onConnect,
              child: Text(i18n.t('Kết nối', 'Connect')),
            ),
          ],
        ),
      ],
    );
  }
}
