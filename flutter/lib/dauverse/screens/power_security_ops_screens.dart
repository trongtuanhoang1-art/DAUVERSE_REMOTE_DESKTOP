import 'package:flutter/material.dart';
import '../bridge/dauverse_bridge.dart';
import '../theme/dauverse_theme.dart';

class DauverseSmartPowerScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseSmartPowerScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseSmartPowerScreen> createState() => _DauverseSmartPowerScreenState();
}

class _DauverseSmartPowerScreenState extends State<DauverseSmartPowerScreen> {
  final TextEditingController _macCtrl = TextEditingController();
  final TextEditingController _wolTargetCtrl = TextEditingController(text: '255.255.255.255:9');
  final TextEditingController _currentPinCtrl = TextEditingController();
  final TextEditingController _stepUpPinCtrl = TextEditingController();
  bool _liveOsExecution = false;

  @override
  void dispose() {
    _macCtrl.dispose();
    _wolTargetCtrl.dispose();
    _currentPinCtrl.dispose();
    _stepUpPinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final sp = c.snapshot['smart_power'] as Map<String, dynamic>? ?? const {};
    final plug = sp['smart_plug'] as Map<String, dynamic>? ?? const {};
    final events = (sp['recent_events'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
    final secWrap = c.snapshot['security'] as Map<String, dynamic>? ?? const {};
    final sec = secWrap['summary'] as Map<String, dynamic>? ?? secWrap;
    final pinAlreadyConfigured = sec['step_up_pin_configured'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n.t('Smart Power Management — Điều khiển nguồn & Khóa an toàn AI', 'Smart Power Management & AI Safety Interlocks'),
              style: DauverseTypography.heading(p, size: 19)),
          Text(
            i18n.t(
              'Yêu cầu mã Step-Up PIN / Mật khẩu máy chủ đã niêm phong trước lệnh OS thật • Đổi PIN bắt buộc xác thực PIN hiện tại.',
              'Requires verified Vault Step-Up PIN for live OS commands • PIN replacement requires current PIN reauthentication.',
            ),
            style: DauverseTypography.caption(p),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 195,
                      child: TextField(
                        controller: _macCtrl,
                        style: DauverseTypography.kpi(p, size: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: i18n.t('Địa chỉ MAC máy nhà', 'Target NIC MAC (XX:XX:...)'),
                          hintText: 'AA:BB:CC:DD:EE:FF',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: TextField(
                        controller: _wolTargetCtrl,
                        style: DauverseTypography.kpi(p, size: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: i18n.t('Broadcast IP:Port', 'Broadcast IP:Port'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (pinAlreadyConfigured)
                      SizedBox(
                        width: 185,
                        child: TextField(
                          controller: _currentPinCtrl,
                          obscureText: true,
                          style: DauverseTypography.kpi(p, size: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: i18n.t('PIN hiện tại (Để đổi)', 'Current PIN (To Rotate)'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 205,
                      child: TextField(
                        controller: _stepUpPinCtrl,
                        obscureText: true,
                        style: DauverseTypography.kpi(p, size: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: pinAlreadyConfigured
                              ? i18n.t('PIN xác thực / PIN mới', 'Step-Up PIN / New PIN')
                              : i18n.t('Mã Step-Up PIN (>=6 ký tự)', 'Step-Up PIN (>=6 chars)'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (!pinAlreadyConfigured)
                      OutlinedButton.icon(
                        onPressed: () {
                          c.setStepUpPin(_stepUpPinCtrl.text);
                        },
                        icon: const Icon(Icons.enhanced_encryption_outlined, size: 16),
                        label: Text(i18n.t('Đăng ký PIN đầu tiên', 'Enroll Initial PIN')),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () {
                          c.changeStepUpPin(_currentPinCtrl.text, _stepUpPinCtrl.text);
                        },
                        icon: const Icon(Icons.lock_reset, size: 16),
                        label: Text(i18n.t('Đổi PIN (Xác thực chủ sở hữu)', 'Rotate PIN (Owner Auth)')),
                      ),
                    FilterChip(
                      label: Text(_liveOsExecution
                          ? i18n.t('Chế độ: LỆNH OS THẬT (Cần PIN)', 'Mode: LIVE OS COMMAND (PIN Required)')
                          : i18n.t('Chế độ: Dry-Run An toàn', 'Mode: Safe Dry-Run')),
                      selected: _liveOsExecution,
                      onSelected: (v) => setState(() => _liveOsExecution = v),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _powerBtn(p, 'Wake-on-LAN (UDP Magic Packet)', Icons.flash_on, p.success, () {
                      c.invokePowerAction(
                        'WAKE_ON_LAN',
                        authenticated: _stepUpPinCtrl.text.trim().isNotEmpty,
                        stepUpPin: _stepUpPinCtrl.text,
                        dryRun: !_liveOsExecution,
                        mac: _macCtrl.text.trim(),
                        target: _wolTargetCtrl.text.trim(),
                      );
                    }),
                    _powerBtn(p, 'Lock Workstation', Icons.lock_outline, p.cyan, () {
                      c.invokePowerAction(
                        'LOCK_WORKSTATION',
                        authenticated: _stepUpPinCtrl.text.trim().isNotEmpty,
                        stepUpPin: _stepUpPinCtrl.text,
                        dryRun: !_liveOsExecution,
                      );
                    }),
                    _powerBtn(p, 'Sleep (Safe Interlock)', Icons.bedtime_outlined, p.blue, () {
                      c.invokePowerAction(
                        'SLEEP',
                        authenticated: _stepUpPinCtrl.text.trim().isNotEmpty,
                        stepUpPin: _stepUpPinCtrl.text,
                        dryRun: !_liveOsExecution,
                      );
                    }),
                    _powerBtn(p, 'Restart (Safe Interlock)', Icons.restart_alt, p.warning, () {
                      c.invokePowerAction(
                        'RESTART',
                        authenticated: _stepUpPinCtrl.text.trim().isNotEmpty,
                        stepUpPin: _stepUpPinCtrl.text,
                        dryRun: !_liveOsExecution,
                      );
                    }),
                    _powerBtn(p, 'Safe OS Shutdown', Icons.power_settings_new, p.danger, () {
                      c.invokePowerAction(
                        'SAFE_SHUTDOWN',
                        authenticated: _stepUpPinCtrl.text.trim().isNotEmpty,
                        stepUpPin: _stepUpPinCtrl.text,
                        dryRun: !_liveOsExecution,
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            accentBorder: p.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DauverseStatusBadge(label: 'HUNONIC SK02: ${plug['integration_state'] ?? 'BLOCKED'}', color: p.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(plug['adapter_name']?.toString() ?? 'DisabledSmartPlugAdapter',
                          style: DauverseTypography.heading(p, size: 15)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  plug['blocker_note']?.toString() ??
                      'BLOCKED (Hunonic SK02 Surveyed): Không có tài liệu API công khai chính thức; giữ nguyên DisabledSmartPlugAdapter.',
                  style: DauverseTypography.body(p),
                ),
                const Divider(height: 22),
                Text(
                  'BIOS Reference (ASUS PRIME H610M-K D4): Advanced > APM Configuration > Restore AC Power Loss > [Power On] & Power On By PCI-E > [Enabled].',
                  style: DauverseTypography.caption(p, size: 12),
                ),
              ],
            ),
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 16),
            DauverseCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent Power Controller Events', style: DauverseTypography.heading(p, size: 14)),
                  const SizedBox(height: 8),
                  for (final ev in events.reversed.take(6))
                    Text(ev, style: DauverseTypography.kpi(p, size: 11)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _powerBtn(DauversePalette p, String label, IconData icon, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class DauverseSecurityCenterScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseSecurityCenterScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = controller;
    final i18n = c.i18n;
    final secWrap = c.snapshot['security'] as Map<String, dynamic>? ?? const {};
    final sec = secWrap['summary'] as Map<String, dynamic>? ?? secWrap;
    final headless = c.snapshot['headless'] as Map<String, dynamic>? ?? const {};

    const capabilities = [
      ('Remote Control (Mouse/Keyboard)', true),
      ('View Only', true),
      ('Smart Clipboard (Engine Hooked)', true),
      ('File Transfer (Path/Symlink Guarded)', true),
      ('System Audio', true),
      ('Power Control (Step-Up Auth)', true),
      ('Hardware Monitoring (Local OS)', true),
      ('AI Notification (No Auto-Approve)', true),
      ('AI Live Status (Read-Only)', true),
      ('Screen Recording (Opt-In + Banner)', false),
    ];

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
                    Text(i18n.t('Device Shield & Security Center — Trung tâm Bảo mật', 'Device Shield & Security Center'),
                        style: DauverseTypography.heading(p, size: 19)),
                    Text(
                      '${sec['encryption'] ?? 'Curve25519 + XSalsa20-Poly1305'} • Vault: ${sec['credential_vault'] ?? 'DPAPI/0600'} • Audit Intact: ${sec['audit_chain_intact'] ?? true}',
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white),
                onPressed: c.emergencyRevokeAllAccess,
                icon: const Icon(Icons.gpp_bad, size: 18),
                label: Text(i18n.t('Thu hồi khẩn cấp mọi truy cập', 'Emergency Revoke All Access')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('Ma trận 10 Quyền độc lập theo phiên (Least Privilege)', '10 Granular Per-Session Capabilities'),
                    style: DauverseTypography.heading(p, size: 16)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: capabilities
                      .map((cap) => DauverseStatusBadge(
                            label: '${cap.$1}: ${cap.$2 ? "GRANTED" : "DEFAULT DENY"}',
                            color: cap.$2 ? p.success : p.warning,
                          ))
                      .toList(),
                ),
                const Divider(height: 24),
                Text(
                  headless['rustdesk_idd_v04_audit']?.toString() ??
                      'BLOCKED_DO_NOT_INSTALL: RustDeskIddDriver v0.4 uses self-signed WDKTestCert SHA-1 root import.',
                  style: DauverseTypography.kpi(p, size: 11.5, color: p.warning),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DauverseSessionHistoryScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseSessionHistoryScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final i18n = controller.i18n;
    final secWrap = controller.snapshot['security'] as Map<String, dynamic>? ?? const {};
    final audits = (secWrap['recent_audit'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: DauverseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n.t('Nhật ký Phiên & Chuỗi Băm Kiểm toán SHA-256 (Persistent JSONL)', 'Session & SHA-256 Hash-Chained Security Audit Log'),
                style: DauverseTypography.heading(p, size: 18)),
            const SizedBox(height: 12),
            if (audits.isEmpty)
              Text(
                i18n.t('Chưa có bản ghi kiểm toán nào trong phiên này.', 'No audit entries recorded yet.'),
                style: DauverseTypography.body(p),
              )
            else
              for (var i = 0; i < audits.length; i++) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.verified_user_outlined, color: p.cyan, size: 20),
                  title: Text(
                    '#${audits[i]['seq']} [${audits[i]['outcome']}] ${audits[i]['actor']} -> ${audits[i]['action']}',
                    style: DauverseTypography.body(p, size: 13, weight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${audits[i]['detail']}  •  SHA-256: ${(audits[i]['entry_hash']?.toString() ?? '').padRight(16).substring(0, 16)}...',
                    style: DauverseTypography.caption(p, size: 11),
                  ),
                ),
                if (i + 1 < audits.length) const Divider(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class DauverseNetworkDiagnosticsScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseNetworkDiagnosticsScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseNetworkDiagnosticsScreen> createState() => _DauverseNetworkDiagnosticsScreenState();
}

class _DauverseNetworkDiagnosticsScreenState extends State<DauverseNetworkDiagnosticsScreen> {
  String _diagReport = '';

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final i18n = widget.controller.i18n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n.t('Chẩn đoán Mạng, P2P & Self-Host Server (hbbs/hbbr)', 'Network Diagnostics & Self-Host Server'),
              style: DauverseTypography.heading(p, size: 19)),
          Text(
            i18n.t(
              'Lưu ý minh bạch: Benchmark nội bộ chỉ đo tốc độ quét khung hình CPU & ký HMAC cục bộ — KHÔNG đại diện độ trễ Remote Desktop End-to-End.',
              'Transparency note: Local microbenchmark measures CPU tile scan & HMAC signing only — NOT end-to-end Remote Desktop latency.',
            ),
            style: DauverseTypography.caption(p),
          ),
          const SizedBox(height: 12),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                      onPressed: () {
                        final res = DauverseNativeBridge.instance.call('run_benchmark');
                        setState(() => _diagReport = res.toString());
                      },
                      icon: const Icon(Icons.speed, size: 18),
                      label: Text(i18n.t('Chạy Microbenchmark Cục bộ', 'Run Local Pipeline Microbenchmark')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final res = DauverseNativeBridge.instance.call('export_diagnostics', {
                          'notes': 'Diagnostic bundle exported cleanly without secrets.',
                        });
                        setState(() => _diagReport = res['data']?.toString() ?? '');
                      },
                      icon: Icon(Icons.download, size: 18, color: p.cyan),
                      label: Text(i18n.t('Xuất Báo cáo Chẩn đoán (Đã lọc Secret)', 'Export Redacted Diagnostic Report'),
                          style: TextStyle(color: p.cyan)),
                    ),
                  ],
                ),
                if (_diagReport.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(_diagReport, style: DauverseTypography.kpi(p, size: 12)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DauverseUpdateCenterScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseUpdateCenterScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final i18n = controller.i18n;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: DauverseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DauverseStatusBadge(label: 'V1.0.0 RC2 (Engine 1.5.3)', color: p.cyan),
                const SizedBox(width: 10),
                DauverseStatusBadge(label: 'CODE SIGNING: UNSIGNED', color: p.warning),
              ],
            ),
            const SizedBox(height: 12),
            Text(i18n.t('Update Center & Quản lý Phiên bản an toàn', 'Safe Update & Release Management'),
                style: DauverseTypography.heading(p, size: 18)),
            const SizedBox(height: 8),
            Text(
              i18n.t(
                'Trạng thái chữ ký số: UNSIGNED (Bản thử nghiệm nội bộ chưa ký Authenticode). Tự động cập nhật nền bị KHÓA CỨNG để đảm bảo an toàn; chỉ cho phép cập nhật thủ công sau khi kiểm tra SHA-256 và chống hạ cấp (Anti-Downgrade).',
                'Code Signing Status: UNSIGNED. Background auto-update is HARD-BLOCKED; manual updates verify SHA-256 and enforce anti-downgrade.',
              ),
              style: DauverseTypography.body(p),
            ),
          ],
        ),
      ),
    );
  }
}

class DauverseSettingsScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseSettingsScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = controller;
    final i18n = c.i18n;
    final headless = c.snapshot['headless'] as Map<String, dynamic>? ?? const {};
    final service = c.snapshot['service'] as Map<String, dynamic>? ?? const {};
    final headlessOpStatus = headless['operational_status']?.toString() ?? 'CONFIGURED';
    final virtualDisplayActive = headless['virtual_display_active'] == true;
    final serviceState = service['service_state']?.toString() ?? 'NOT_INSTALLED';
    final externalCollision = service['external_service_collision_detected'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: DauverseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n.t('Cài đặt Hệ thống, Headless WHQL, Service & Mobile Readiness', 'System, WHQL Headless IDD, Service & Mobile Settings'),
                style: DauverseTypography.heading(p, size: 18)),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text(i18n.t('Giao diện Tối (Executive Dark Mode)', 'Executive Dark Mode')),
              value: c.isDarkMode,
              onChanged: (_) => c.toggleTheme(),
            ),
            SwitchListTile(
              title: Text(i18n.t('Ngôn ngữ Tiếng Việt (Mặc định)', 'Vietnamese Language (Default)')),
              subtitle: const Text('Toggle Tiếng Việt / English'),
              value: c.isVietnamese,
              onChanged: (_) => c.toggleLanguage(),
            ),
            const Divider(),
            ListTile(
              title: const Text('Headless Virtual Display Driver Policy (Secure Boot + DSE Preserved)'),
              subtitle: Text(
                'Primary: ${headless['primary_driver'] ?? 'Amyuni usbmmidd_v2 (Microsoft WHQL Signed)'}\n'
                'State: $headlessOpStatus • Native Active: ${virtualDisplayActive ? "YES" : "NO"} • Blocked: RustDeskIddDriver v0.4 (WDKTestCert)',
              ),
              trailing: DauverseStatusBadge(
                label: virtualDisplayActive ? 'ACTIVE (VERIFIED)' : headlessOpStatus,
                color: virtualDisplayActive ? p.success : p.warning,
              ),
            ),
            ListTile(
              title: const Text('Windows Service & Unattended Access'),
              subtitle: Text(
                externalCollision
                    ? 'SCM Name: RustDesk • EXTERNAL RUSTDESK SERVICE PRESERVED UNTOUCHED'
                    : 'SCM Name: RustDesk • Opt-in only; verified against OS SCM & HKCU Run state',
              ),
              trailing: DauverseStatusBadge(
                label: externalCollision ? 'EXTERNAL COLLISION' : serviceState,
                color: externalCollision ? p.danger : (serviceState == 'RUNNING' ? p.success : p.cyan),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DauverseAboutScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseAboutScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: DauverseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DauverseEmblem(size: 48),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DAUVERSE REMOTE DESKTOP V1.0 (RC2)', style: DauverseTypography.heading(p, size: 20)),
                    Text('Autonomous Remote AI Workstation Suite • License: GNU AGPL-3.0',
                        style: DauverseTypography.caption(p)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Built upon open-source RustDesk v1.5.3 (Copyright © Purslane Tech Pte. Ltd. & Contributors, GNU AGPL-3.0) with full upstream attribution preserved in LICENSE, LICENCE, THIRD_PARTY_NOTICES, UPSTREAM_MANIFEST.json, and SBOM.spdx.json.\n'
              'Operates 100% independently of DAUVERSE AI production without modifying external controllers.',
              style: DauverseTypography.body(p),
            ),
          ],
        ),
      ),
    );
  }
}
