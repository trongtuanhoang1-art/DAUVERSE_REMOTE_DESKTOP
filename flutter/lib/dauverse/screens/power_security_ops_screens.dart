import 'dart:convert';
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

  Future<void> _executePowerOperation(
    BuildContext context,
    String operation, {
    String? mac,
    String? target,
  }) async {
    final c = widget.controller;
    final i18n = c.i18n;
    final pin = _stepUpPinCtrl.text;
    final res = c.invokePowerAction(
      operation,
      authenticated: pin.trim().isNotEmpty,
      stepUpPin: pin,
      forceConfirmed: false,
      dryRun: !_liveOsExecution,
      mac: mac,
      target: target,
    );
    if (!context.mounted) return;
    if (res['status_code']?.toString() == 'SAFETY_INTERLOCK_CONFIRMATION_REQUIRED') {
      final p = DauversePalette.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: p.warning),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: p.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  i18n.t(
                    'Khóa An toàn AI / Truyền File đang kích hoạt',
                    'Active AI / File Transfer Safety Interlock',
                  ),
                  style: DauverseTypography.heading(p, size: 16),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              res['message']?.toString() ??
                  i18n.t(
                    'Phát hiện tác vụ AI hoặc truyền dữ liệu đang chạy. Bạn có chắc chắn muốn cưỡng bức thực thi lệnh nguồn này?',
                    'Active AI workload or file transfer detected. Force execute this power command anyway?',
                  ),
              style: DauverseTypography.body(p, size: 13),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(i18n.t('Hủy an toàn', 'Cancel Safely')),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: p.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.gpp_maybe_rounded, size: 18),
              label: Text(i18n.t('Xác nhận Cưỡng bức', 'Force Confirm')),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        c.invokePowerAction(
          operation,
          authenticated: pin.trim().isNotEmpty,
          stepUpPin: pin,
          forceConfirmed: true,
          dryRun: !_liveOsExecution,
          mac: mac,
          target: target,
        );
      }
    }
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
          Text(
            i18n.t(
              'Smart Power Management — Điều khiển nguồn & Khóa an toàn AI',
              'Smart Power Management & AI Safety Interlocks',
            ),
            style: DauverseTypography.heading(p, size: 19),
          ),
          const SizedBox(height: 4),
          Text(
            i18n.t(
              'Yêu cầu mã Step-Up PIN đã niêm phong trước lệnh OS thật • Tự động chặn Sleep/Restart/Shutdown khi AI hoặc truyền file đang chạy.',
              'Requires verified Vault Step-Up PIN for live OS commands • Safety interlock guards active AI & file transfer jobs.',
            ),
            style: DauverseTypography.caption(p),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 190,
                      child: TextField(
                        controller: _macCtrl,
                        style: DauverseTypography.kpi(p, size: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: i18n.t('Địa chỉ MAC máy đích', 'Target NIC MAC'),
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
                        width: 180,
                        child: TextField(
                          controller: _currentPinCtrl,
                          obscureText: true,
                          style: DauverseTypography.kpi(p, size: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: i18n.t('PIN hiện tại (Để đổi)', 'Current PIN'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 200,
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
                        onPressed: () => c.setStepUpPin(_stepUpPinCtrl.text),
                        icon: const Icon(Icons.enhanced_encryption_outlined, size: 16),
                        label: Text(i18n.t('Đăng ký PIN đầu tiên', 'Enroll Initial PIN')),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => c.changeStepUpPin(_currentPinCtrl.text, _stepUpPinCtrl.text),
                        icon: const Icon(Icons.lock_reset, size: 16),
                        label: Text(i18n.t('Đổi PIN chủ sở hữu', 'Rotate Owner PIN')),
                      ),
                    FilterChip(
                      label: Text(
                        _liveOsExecution
                            ? i18n.t('Chế độ: LỆNH OS THẬT (Cần PIN)', 'Mode: LIVE OS COMMAND')
                            : i18n.t('Chế độ: Dry-Run An toàn', 'Mode: Safe Dry-Run'),
                      ),
                      selected: _liveOsExecution,
                      onSelected: (v) => setState(() => _liveOsExecution = v),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _powerBtn(
                      p,
                      'Wake-on-LAN (UDP Magic Packet)',
                      Icons.flash_on,
                      p.success,
                      () => _executePowerOperation(
                        context,
                        'WAKE_ON_LAN',
                        mac: _macCtrl.text.trim(),
                        target: _wolTargetCtrl.text.trim(),
                      ),
                    ),
                    _powerBtn(
                      p,
                      i18n.t('Khóa màn hình (Lock)', 'Lock Workstation'),
                      Icons.lock_outline,
                      p.cyan,
                      () => _executePowerOperation(context, 'LOCK_WORKSTATION'),
                    ),
                    _powerBtn(
                      p,
                      i18n.t('Ngủ (Sleep — Có khóa AI)', 'Sleep (Safe Interlock)'),
                      Icons.bedtime_outlined,
                      p.blue,
                      () => _executePowerOperation(context, 'SLEEP'),
                    ),
                    _powerBtn(
                      p,
                      i18n.t('Khởi động lại (Restart)', 'Restart (Safe Interlock)'),
                      Icons.restart_alt,
                      p.warning,
                      () => _executePowerOperation(context, 'RESTART'),
                    ),
                    _powerBtn(
                      p,
                      i18n.t('Tắt máy an toàn (Shutdown)', 'Safe OS Shutdown'),
                      Icons.power_settings_new,
                      p.danger,
                      () => _executePowerOperation(context, 'SAFE_SHUTDOWN'),
                    ),
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
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DauverseStatusBadge(
                      label: 'HUNONIC SK02: ${plug['integration_state'] ?? 'BLOCKED'}',
                      color: p.warning,
                    ),
                    Text(
                      plug['adapter_name']?.toString() ?? 'DisabledSmartPlugAdapter',
                      style: DauverseTypography.heading(p, size: 15),
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
                  Text(
                    i18n.t('Nhật ký Bộ điều khiển Nguồn gần đây', 'Recent Power Controller Events'),
                    style: DauverseTypography.heading(p, size: 14),
                  ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class DauverseSecurityCenterScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseSecurityCenterScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseSecurityCenterScreen> createState() => _DauverseSecurityCenterScreenState();
}

class _DauverseSecurityCenterScreenState extends State<DauverseSecurityCenterScreen> {
  final TextEditingController _pinCtrl = TextEditingController();

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final secWrap = c.snapshot['security'] as Map<String, dynamic>? ?? const {};
    final sec = secWrap['summary'] as Map<String, dynamic>? ?? secWrap;
    final headless = c.snapshot['headless'] as Map<String, dynamic>? ?? const {};
    final caps = c.snapshot['host_capabilities'] as Map<String, dynamic>? ?? const {};
    final denyLatched = caps['conservative_deny_latched'] == true;
    final pinConfigured = sec['step_up_pin_configured'] == true;

    final editableCaps = <(String, String, bool)>[
      (
        'enable_keyboard',
        i18n.t('Điều khiển Chuột & Bàn phím', 'Remote Mouse & Keyboard'),
        caps['enable_keyboard'] != false && !denyLatched,
      ),
      (
        'enable_clipboard',
        i18n.t('Đồng bộ Smart Clipboard', 'Smart Clipboard Sync'),
        caps['enable_clipboard'] != false && !denyLatched,
      ),
      (
        'enable_file_transfer',
        i18n.t('Truyền File hai chiều (Guarded)', 'Guarded File Transfer'),
        caps['enable_file_transfer'] != false && !denyLatched,
      ),
      (
        'enable_audio',
        i18n.t('Truyền Âm thanh Hệ thống', 'System Audio Streaming'),
        caps['enable_audio'] != false && !denyLatched,
      ),
      (
        'enable_tunnel',
        i18n.t('Đường hầm TCP (TCP Tunneling)', 'TCP Tunneling'),
        caps['enable_tunnel'] != false && !denyLatched,
      ),
      (
        'enable_remote_restart',
        i18n.t('Cho phép Khởi động lại từ xa', 'Allow Remote Restart'),
        caps['enable_remote_restart'] != false && !denyLatched,
      ),
      (
        'enable_record_session',
        i18n.t('Ghi hình phiên (Opt-In + Banner)', 'Session Recording (Opt-In + Banner)'),
        caps['enable_record_session'] == true && !denyLatched,
      ),
    ];

    final fixedInvariants = <(String, bool)>[
      (i18n.t('Chế độ Chỉ xem (View Only)', 'View-Only Inspection'), !denyLatched),
      (i18n.t('Giám sát Phần cứng Cục bộ', 'Local Hardware Telemetry'), true),
      (i18n.t('Thông báo AI (Cấm Auto-Approve)', 'AI Alerts (Zero Auto-Approve)'), true),
    ];

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
                      i18n.t('Device Shield & Security Center — Trung tâm Bảo mật', 'Device Shield & Security Center'),
                      style: DauverseTypography.heading(p, size: 19),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${sec['encryption'] ?? 'Curve25519 + XSalsa20-Poly1305'} • Vault: ${sec['credential_vault'] ?? 'DPAPI/0600'} • Audit Intact: ${sec['audit_chain_intact'] ?? true}',
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: c.emergencyRevokeAllAccess,
                icon: const Icon(Icons.gpp_bad, size: 18),
                label: Text(i18n.t('Thu hồi khẩn cấp mọi truy cập', 'Emergency Revoke All Access')),
              ),
            ],
          ),
          if (denyLatched) ...[
            const SizedBox(height: 12),
            DauverseCard(
              accentBorder: p.danger,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.lock_person_rounded, color: p.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      i18n.t(
                        'CHẾ ĐỘ PHONG TỎA KHẨN CẤP ĐANG BẬT: Mọi quyền đầu vào, truyền file, clipboard và truy cập nền đã bị khóa cứng.',
                        'CONSERVATIVE DENY LATCH ACTIVE: All remote inputs, file transfer, clipboard, and unattended access are locked.',
                      ),
                      style: DauverseTypography.body(p, size: 13, weight: FontWeight.w700, color: p.danger),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      i18n.t(
                        'Ma trận 10 Quyền độc lập thực tế (Least Privilege — Đồng bộ Config)',
                        'Live 10 Granular Host Capabilities (Synced with Engine Config)',
                      ),
                      style: DauverseTypography.heading(p, size: 16),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 190,
                          child: TextField(
                            controller: _pinCtrl,
                            obscureText: true,
                            style: DauverseTypography.kpi(p, size: 12.5),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: i18n.t('Mã Step-Up PIN', 'Step-Up PIN'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (!pinConfigured)
                          OutlinedButton(
                            onPressed: () => c.setStepUpPin(_pinCtrl.text),
                            child: Text(i18n.t('Tạo PIN', 'Set PIN')),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final cap in editableCaps)
                      DauverseStatusBadge(
                        label: '${cap.$2}: ${cap.$3 ? "GRANTED" : "DENIED"}',
                        color: cap.$3 ? p.success : p.danger,
                      ),
                    for (final inv in fixedInvariants)
                      DauverseStatusBadge(
                        label: '${inv.$1}: ${inv.$2 ? "ACTIVE" : "DENIED"}',
                        color: inv.$2 ? p.cyan : p.danger,
                      ),
                  ],
                ),
                const Divider(height: 22),
                for (final cap in editableCaps)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(cap.$2, style: DauverseTypography.body(p, size: 13.5, weight: FontWeight.w600)),
                    subtitle: Text(
                      'Config key: ${cap.$1} • Approve mode: ${caps['approve_mode'] ?? 'password_and_click'}',
                      style: DauverseTypography.caption(p, size: 11.5),
                    ),
                    value: cap.$3,
                    onChanged: (val) => c.setHostCapability(cap.$1, val, _pinCtrl.text),
                  ),
                const Divider(height: 22),
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
    final st = controller.snapshot['session_tools'] as Map<String, dynamic>? ?? const {};
    final sessions = (st['history'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final secWrap = controller.snapshot['security'] as Map<String, dynamic>? ?? const {};
    final audits = (secWrap['recent_audit'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t('Lịch sử Phiên Kết nối Từ xa (Session History)', 'Remote Desktop & File Transfer Session History'),
                  style: DauverseTypography.heading(p, size: 18),
                ),
                const SizedBox(height: 10),
                if (sessions.isEmpty)
                  Text(
                    i18n.t(
                      'Chưa có phiên điều khiển từ xa nào được khởi tạo trong phiên làm việc này (0 bản ghi mẫu giả).',
                      'No remote sessions initiated yet in this runtime (zero synthetic mock rows).',
                    ),
                    style: DauverseTypography.body(p),
                  )
                else
                  for (var i = 0; i < sessions.length; i++) ...[
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 580),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${sessions[i]['peer_name'] ?? sessions[i]['peer_id']} (${sessions[i]['peer_id']})',
                                style: DauverseTypography.body(p, size: 13.5, weight: FontWeight.w700),
                              ),
                              Text(
                                '${sessions[i]['route'] ?? 'P2P'} • ${sessions[i]['started_at_utc'] ?? ''} • ${sessions[i]['disconnect_reason'] ?? 'ACTIVE'}',
                                style: DauverseTypography.caption(p, size: 11.5),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => controller.launchRealRemoteSession(
                            context,
                            sessions[i]['peer_id']?.toString() ?? '',
                          ),
                          icon: const Icon(Icons.replay_rounded, size: 16),
                          label: Text(i18n.t('Kết nối lại', 'Reconnect')),
                        ),
                      ],
                    ),
                    if (i + 1 < sessions.length) const Divider(height: 14),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t(
                    'Chuỗi Băm Kiểm toán Bảo mật SHA-256 (Persistent JSONL)',
                    'SHA-256 Hash-Chained Security Audit Log',
                  ),
                  style: DauverseTypography.heading(p, size: 18),
                ),
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
        ],
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
  final TextEditingController _endpointCtrl = TextEditingController(text: '127.0.0.1:21116');
  Map<String, dynamic>? _probeResult;
  Map<String, dynamic>? _benchResult;
  String _diagReport = '';

  @override
  void dispose() {
    _endpointCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.t('Chẩn đoán Mạng, P2P & Self-Host Server (hbbs/hbbr)', 'Network Diagnostics & Self-Host Server'),
            style: DauverseTypography.heading(p, size: 19),
          ),
          const SizedBox(height: 4),
          Text(
            i18n.t(
              'Lưu ý minh bạch: Benchmark nội bộ chỉ đo tốc độ quét khung hình CPU & ký HMAC cục bộ — KHÔNG đại diện độ trễ Remote Desktop End-to-End.',
              'Transparency note: Local microbenchmark measures CPU tile scan & HMAC signing only — NOT end-to-end Remote Desktop latency.',
            ),
            style: DauverseTypography.caption(p),
          ),
          const SizedBox(height: 14),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t('Kiểm tra Kết nối TCP Tới Máy chủ Rendezvous / Relay / LAN', 'Live TCP Endpoint Reachability Probe'),
                  style: DauverseTypography.heading(p, size: 15),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 250,
                      child: TextField(
                        controller: _endpointCtrl,
                        style: DauverseTypography.kpi(p, size: 13.5),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: i18n.t('Địa chỉ Host:Port', 'Target Host:Port'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: p.cyan, foregroundColor: Colors.white),
                      onPressed: () {
                        final res = DauverseNativeBridge.instance.call('network_probe', {
                          'target': _endpointCtrl.text.trim(),
                          'timeout_ms': 1500,
                        });
                        setState(() {
                          _probeResult = res['data'] as Map<String, dynamic>? ?? res;
                        });
                      },
                      icon: const Icon(Icons.network_check_rounded, size: 18),
                      label: Text(i18n.t('Kiểm tra TCP Endpoint', 'Probe TCP Endpoint')),
                    ),
                    if (_probeResult != null)
                      DauverseStatusBadge(
                        label: _probeResult!['reachable'] == true
                            ? 'REACHABLE (${_probeResult!['latency_ms'] ?? 0} ms)'
                            : 'UNREACHABLE (${_probeResult!['detail'] ?? _probeResult!['error'] ?? 'timeout'})',
                        color: _probeResult!['reachable'] == true ? p.success : p.warning,
                      ),
                  ],
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                      onPressed: () {
                        final res = DauverseNativeBridge.instance.call('run_benchmark');
                        setState(() {
                          _benchResult = res['data'] as Map<String, dynamic>? ?? res;
                          _diagReport = const JsonEncoder.withIndent('  ').convert(res);
                        });
                      },
                      icon: const Icon(Icons.speed, size: 18),
                      label: Text(i18n.t('Chạy Microbenchmark Cục bộ', 'Run Local Pipeline Microbenchmark')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final res = DauverseNativeBridge.instance.call('export_diagnostics', {
                          'notes': 'Diagnostic bundle exported cleanly without secrets.',
                        });
                        setState(() {
                          _diagReport = res['data'] is String
                              ? res['data'] as String
                              : const JsonEncoder.withIndent('  ').convert(res['data'] ?? res);
                        });
                      },
                      icon: Icon(Icons.download, size: 18, color: p.cyan),
                      label: Text(
                        i18n.t('Xuất Báo cáo Chẩn đoán (Đã lọc Secret)', 'Export Redacted Diagnostic Report'),
                        style: TextStyle(color: p.cyan),
                      ),
                    ),
                    if (_diagReport.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => c.copyToClipboardWithFeedback(
                          context,
                          _diagReport,
                          keyTag: 'diag_report',
                          displayLabel: 'Diagnostic JSON',
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(i18n.t('Sao chép Báo cáo', 'Copy Report')),
                      ),
                  ],
                ),
                if (_benchResult != null && _benchResult!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final entry in _benchResult!.entries.take(5))
                        DauverseStatusBadge(
                          label: '${entry.key}: ${entry.value}',
                          color: p.cyan,
                        ),
                    ],
                  ),
                ],
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

class DauverseUpdateCenterScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseUpdateCenterScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseUpdateCenterScreen> createState() => _DauverseUpdateCenterScreenState();
}

class _DauverseUpdateCenterScreenState extends State<DauverseUpdateCenterScreen> {
  final TextEditingController _artifactPathCtrl = TextEditingController();
  final TextEditingController _candVerCtrl = TextEditingController(text: kDauverseProductVersion);
  final TextEditingController _shaCtrl = TextEditingController();
  Map<String, dynamic>? _verifyResult;

  @override
  void dispose() {
    _artifactPathCtrl.dispose();
    _candVerCtrl.dispose();
    _shaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final rel = c.snapshot['release'] as Map<String, dynamic>? ?? const {};
    final displayVer = rel['display_version']?.toString() ?? kDauverseDisplayVersion;
    final prodVer = rel['product_version']?.toString() ?? kDauverseProductVersion;
    final engineVer = rel['upstream_engine_base']?.toString() ?? kDauverseEngineVersion;
    final signStatus = rel['code_signing_status']?.toString() ?? 'UNSIGNED';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    DauverseStatusBadge(label: '$displayVer ($prodVer • Engine $engineVer)', color: p.cyan),
                    DauverseStatusBadge(label: 'CODE SIGNING: $signStatus', color: p.warning),
                    DauverseStatusBadge(label: 'AUTO-UPDATE: LOCKED', color: p.danger),
                    DauverseStatusBadge(label: 'ROLLBACK: SUPPORTED', color: p.success),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  i18n.t('Update Center & Quản lý Phiên bản An toàn', 'Safe Update & Release Management'),
                  style: DauverseTypography.heading(p, size: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  i18n.t(
                    'Trạng thái chữ ký số: UNSIGNED (Bản nội bộ chưa ký Authenticode). Tự động cập nhật nền bị KHÓA CỨNG để đảm bảo an toàn; chỉ cho phép cập nhật thủ công sau khi kiểm tra SHA-256 và chống hạ cấp (Anti-Downgrade).',
                    'Code Signing Status: UNSIGNED. Background auto-update is HARD-BLOCKED; manual updates verify SHA-256 and enforce anti-downgrade.',
                  ),
                  style: DauverseTypography.body(p),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t(
                    'Trình Xác minh Gói Cập nhật Cục bộ (SHA-256 + Anti-Downgrade)',
                    'Local Update Artifact Verifier (SHA-256 + Anti-Downgrade)',
                  ),
                  style: DauverseTypography.heading(p, size: 16),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _artifactPathCtrl,
                        style: DauverseTypography.kpi(p, size: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: i18n.t('Đường dẫn gói cài đặt (.exe)', 'Local Installer Path (.exe)'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 155,
                      child: TextField(
                        controller: _candVerCtrl,
                        style: DauverseTypography.kpi(p, size: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: i18n.t('Phiên bản đích', 'Candidate Version'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _shaCtrl,
                        style: DauverseTypography.kpi(p, size: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: i18n.t('SHA-256 kỳ vọng (64 hex)', 'Expected SHA-256 (64 hex)'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                      onPressed: () {
                        final res = DauverseNativeBridge.instance.call('verify_update_package', {
                          'artifact_path': _artifactPathCtrl.text.trim(),
                          'descriptor': {
                            'version': _candVerCtrl.text.trim(),
                            'download_url': 'https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/releases',
                            'expected_sha256': _shaCtrl.text.trim(),
                            'signature_status': 'UNSIGNED_BUILD',
                            'release_notes_vi': 'Manual local verification',
                          },
                        });
                        setState(() {
                          _verifyResult = res['data'] as Map<String, dynamic>? ?? res;
                        });
                      },
                      icon: const Icon(Icons.verified_rounded, size: 18),
                      label: Text(i18n.t('Xác minh Gói Cập nhật', 'Verify Package')),
                    ),
                  ],
                ),
                if (_verifyResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      'Status: ${_verifyResult!['status_code'] ?? _verifyResult!['error']}\n'
                      'Manual Owner Install Allowed: ${_verifyResult!['safe_for_manual_owner_install'] ?? false}\n'
                      'Computed SHA-256: ${_verifyResult!['computed_sha256'] ?? 'N/A'}\n'
                      'Reason: ${_verifyResult!['reason'] ?? ''}',
                      style: DauverseTypography.kpi(p, size: 12),
                    ),
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

class DauverseSettingsScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseSettingsScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseSettingsScreen> createState() => _DauverseSettingsScreenState();
}

class _DauverseSettingsScreenState extends State<DauverseSettingsScreen> {
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _fsShortcutCtrl = TextEditingController(text: 'Ctrl+Alt+Enter');
  String _headlessPreset = '1920x1080@60';

  @override
  void dispose() {
    _pinCtrl.dispose();
    _fsShortcutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final headless = c.snapshot['headless'] as Map<String, dynamic>? ?? const {};
    final service = c.snapshot['service'] as Map<String, dynamic>? ?? const {};
    final readiness = c.snapshot['windows_access_readiness'] as Map<String, dynamic>? ?? const {};
    final secWrap = c.snapshot['security'] as Map<String, dynamic>? ?? const {};
    final sec = secWrap['summary'] as Map<String, dynamic>? ?? secWrap;
    final st = c.snapshot['session_tools'] as Map<String, dynamic>? ?? const {};
    final shortcuts = st['shortcuts'] as Map<String, dynamic>? ?? const {};

    final headlessOpStatus = headless['operational_status']?.toString() ?? 'CONFIGURED';
    final virtualDisplayActive = headless['virtual_display_active'] == true;
    final serviceState = service['service_state']?.toString() ?? 'NOT_INSTALLED';
    final externalCollision =
        service['external_service_collision_detected'] == true || readiness['external_rustdesk_collision'] == true;
    final autoStart = service['auto_start_with_windows'] == true;
    final unattended = service['unattended_access_enabled'] == true;
    final preloginReady = readiness['pre_login_winlogon_ready'] == true;
    final lockScreenReady = readiness['lock_screen_uac_ready'] == true;
    final pinConfigured = sec['step_up_pin_configured'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t('Giao diện, Ngôn ngữ & Tương thích Đồ họa Windows', 'Appearance, Language & Windows Graphics Compatibility'),
                  style: DauverseTypography.heading(p, size: 18),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(i18n.t('Giao diện Tối (Executive Dark Mode)', 'Executive Dark Mode')),
                  value: c.isDarkMode,
                  onChanged: (_) => c.toggleTheme(),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(i18n.t('Ngôn ngữ Tiếng Việt (Mặc định)', 'Vietnamese Language (Default)')),
                  subtitle: Text(i18n.t('Chuyển đổi tức thì Tiếng Việt / English', 'Instant Tiếng Việt / English toggle')),
                  value: c.isVietnamese,
                  onChanged: (_) => c.toggleLanguage(),
                ),
                const Divider(height: 20),
                Text(
                  i18n.t(
                    'Chế độ Kết xuất Video Phiên Từ xa (Chống văng ứng dụng trên máy khác GPU / không GPU rời)',
                    'Remote Video Rendering Fallback Mode (Heterogeneous GPU / iGPU / CPU Safety)',
                  ),
                  style: DauverseTypography.body(p, size: 13.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(i18n.t('PixelBuffer Safe (Mặc định an toàn)', 'PixelBuffer Safe (Default)')),
                      selected: c.graphicsFallbackMode == 'PIXEL_BUFFER_SAFE',
                      onSelected: (_) => c.setGraphicsFallbackMode('PIXEL_BUFFER_SAFE', restoreHwcodec: true),
                    ),
                    ChoiceChip(
                      label: Text(i18n.t('Software Canvas Fallback (Không GPU / iGPU cũ)', 'Software Canvas Fallback')),
                      selected: c.graphicsFallbackMode == 'SOFTWARE_CANVAS_FALLBACK',
                      onSelected: (_) => c.setGraphicsFallbackMode('SOFTWARE_CANVAS_FALLBACK'),
                    ),
                    ChoiceChip(
                      label: Text(i18n.t('GPU D3D11 Zero-Copy (Máy có GPU rời ổn định)', 'GPU D3D11 Zero-Copy')),
                      selected: c.graphicsFallbackMode == 'GPU_D3D11_ZERO_COPY',
                      onSelected: (_) => c.setGraphicsFallbackMode('GPU_D3D11_ZERO_COPY', restoreHwcodec: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            accentBorder: externalCollision ? p.danger : p.cyan.withOpacity(0.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t(
                    'Khởi động cùng Windows, Windows Service (UAC), Màn hình Khóa & Trước Đăng nhập (Winlogon)',
                    'Windows Startup, Owned Service (UAC), Lock-Screen & Pre-Login (Winlogon) Access',
                  ),
                  style: DauverseTypography.heading(p, size: 17),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DauverseStatusBadge(
                      label: i18n.t('Mật khẩu Windows: GIỮ NGUYÊN', 'Windows Password: PRESERVED'),
                      color: p.success,
                    ),
                    DauverseStatusBadge(
                      label: i18n.t('Windows Auto-Login: ĐÃ TẮT', 'Windows Auto-Login: DISABLED'),
                      color: p.success,
                    ),
                    DauverseStatusBadge(
                      label: preloginReady
                          ? i18n.t('Trước Đăng nhập (Winlogon): SẴN SÀNG', 'Pre-Login Winlogon: READY')
                          : i18n.t('Trước Đăng nhập: Cần cài Service', 'Pre-Login: Needs Service'),
                      color: preloginReady ? p.success : p.warning,
                    ),
                    DauverseStatusBadge(
                      label: lockScreenReady
                          ? i18n.t('Màn hình khóa & UAC: SẴN SÀNG', 'Lock Screen & UAC: READY')
                          : i18n.t('Màn hình khóa: Cần Service', 'Lock Screen: Needs Service'),
                      color: lockScreenReady ? p.success : p.warning,
                    ),
                    DauverseStatusBadge(
                      label: externalCollision ? 'EXTERNAL COLLISION (F03)' : 'SERVICE: $serviceState',
                      color: externalCollision ? p.danger : (serviceState == 'RUNNING' ? p.success : p.cyan),
                    ),
                  ],
                ),
                if (externalCollision) ...[
                  const SizedBox(height: 10),
                  Text(
                    i18n.t(
                      'F03 BẢO VỆ TƯƠNG HỢP: Phát hiện dịch vụ nền không thuộc thư mục cài đặt DAUVERSE. Tuyệt đối giữ nguyên dịch vụ hiện có và từ chối ghi đè.',
                      'F03 COEXISTENCE GUARD: External non-DAUVERSE service detected. Existing service is preserved untouched.',
                    ),
                    style: DauverseTypography.body(p, size: 12.5, weight: FontWeight.w700, color: p.danger),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 210,
                      child: TextField(
                        controller: _pinCtrl,
                        obscureText: true,
                        style: DauverseTypography.kpi(p, size: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: i18n.t('Mã Step-Up PIN chủ máy', 'Owner Step-Up PIN'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (!pinConfigured)
                      OutlinedButton.icon(
                        onPressed: () => c.setStepUpPin(_pinCtrl.text),
                        icon: const Icon(Icons.lock_outline, size: 16),
                        label: Text(i18n.t('Đăng ký PIN (>=6 ký tự)', 'Enroll Initial PIN')),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    i18n.t('Tự khởi động cùng Windows khi đăng nhập (HKCU Run)', 'Start Automatically on Windows User Logon (HKCU Run)'),
                  ),
                  value: autoStart,
                  onChanged: (v) => c.setAutoStartWithWindows(v, _pinCtrl.text),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    i18n.t(
                      'Cho phép Truy cập Không giám sát (Unattended Access — giữ nguyên mật khẩu Windows)',
                      'Enable Audited Unattended Access (Windows Password Preserved)',
                    ),
                  ),
                  value: unattended,
                  onChanged: (v) => c.configureUnattendedAccess(v, _pinCtrl.text),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                      onPressed: externalCollision
                          ? null
                          : () => c.manageOwnedWindowsService('INSTALL_AND_START_ELEVATED', _pinCtrl.text),
                      icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                      label: Text(i18n.t('Cài đặt & Bật Windows Service (UAC)', 'Install & Start Service (UAC)')),
                    ),
                    OutlinedButton.icon(
                      onPressed: externalCollision
                          ? null
                          : () => c.manageOwnedWindowsService('START_ELEVATED', _pinCtrl.text),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(i18n.t('Chạy Service (UAC)', 'Start Service (UAC)')),
                    ),
                    OutlinedButton.icon(
                      onPressed: externalCollision
                          ? null
                          : () => c.manageOwnedWindowsService('STOP', _pinCtrl.text),
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: Text(i18n.t('Dừng Service', 'Stop Service')),
                    ),
                    OutlinedButton.icon(
                      onPressed: externalCollision
                          ? null
                          : () => c.manageOwnedWindowsService('UNINSTALL_ELEVATED', _pinCtrl.text),
                      icon: Icon(Icons.delete_outline_rounded, size: 18, color: p.warning),
                      label: Text(i18n.t('Gỡ Service (UAC)', 'Uninstall Service (UAC)')),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white),
                      onPressed: c.emergencyRevokeAllAccess,
                      icon: const Icon(Icons.gpp_bad_rounded, size: 18),
                      label: Text(i18n.t('Thu hồi Khẩn cấp 1-Click', '1-Click Emergency Revoke')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      i18n.t('Màn hình Ảo Headless WHQL (Secure Boot + DSE Preserved)', 'WHQL Headless Virtual Display Policy'),
                      style: DauverseTypography.heading(p, size: 16),
                    ),
                    DauverseStatusBadge(
                      label: virtualDisplayActive ? 'ACTIVE (VERIFIED)' : headlessOpStatus,
                      color: virtualDisplayActive ? p.success : p.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Primary: ${headless['primary_driver'] ?? 'Amyuni usbmmidd_v2 (Microsoft WHQL Signed)'}\n'
                  'Blocked: RustDeskIddDriver v0.4 (Self-signed WDKTestCert SHA-1 root import)',
                  style: DauverseTypography.caption(p, size: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<String>(
                      value: _headlessPreset,
                      items: const [
                        DropdownMenuItem(value: '1920x1080@60', child: Text('1920×1080 @ 60Hz')),
                        DropdownMenuItem(value: '2560x1440@60', child: Text('2560×1440 @ 60Hz')),
                        DropdownMenuItem(value: '1366x768@60', child: Text('1366×768 @ 60Hz')),
                      ],
                      onChanged: (v) => setState(() => _headlessPreset = v ?? '1920x1080@60'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => c.approveAndActivateHeadless(_pinCtrl.text, _headlessPreset),
                      icon: const Icon(Icons.monitor_rounded, size: 17),
                      label: Text(i18n.t('Phê duyệt & Kích hoạt Headless', 'Approve & Activate Headless')),
                    ),
                    if (virtualDisplayActive)
                      TextButton(
                        onPressed: c.deactivateHeadless,
                        child: Text(i18n.t('Ngắt Headless', 'Deactivate')),
                      ),
                  ],
                ),
                const Divider(height: 22),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      i18n.t('Phím tắt Toàn màn hình:', 'Fullscreen Shortcut:'),
                      style: DauverseTypography.body(p, size: 13),
                    ),
                    SizedBox(
                      width: 175,
                      child: TextField(
                        controller: _fsShortcutCtrl,
                        style: DauverseTypography.kpi(p, size: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: shortcuts['toggle_fullscreen']?.toString() ?? 'Ctrl+Alt+Enter',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => c.updateShortcut('toggle_fullscreen', _fsShortcutCtrl.text.trim()),
                      child: Text(i18n.t('Lưu Phím tắt', 'Save Shortcut')),
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
}

class DauverseAboutScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseAboutScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final i18n = controller.i18n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: DauverseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DauverseEmblem(size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DAUVERSE REMOTE DESKTOP V1.0 ($kDauverseReleaseCandidate)',
                        style: DauverseTypography.heading(p, size: 20),
                      ),
                      Text(
                        'Version $kDauverseProductVersion • Autonomous Remote AI Workstation Suite • License: GNU AGPL-3.0',
                        style: DauverseTypography.caption(p),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              i18n.t(
                'Phát triển trên nền tảng mã nguồn mở RustDesk v1.5.3 (Copyright © Purslane Tech Pte. Ltd. & Contributors, GNU AGPL-3.0) với đầy đủ thông tin bản quyền được giữ nguyên trong LICENSE, LICENCE, THIRD_PARTY_NOTICES, UPSTREAM_MANIFEST.json và SBOM.spdx.json.\n'
                'Bộ phông chữ giao diện đóng gói cục bộ theo giấy phép SIL Open Font License 1.1 (Be Vietnam Pro, Inter, Roboto Mono).\n'
                'Vận hành độc lập 100% với hệ thống DAUVERSE AI Production, không can thiệp trình điều khiển ngoài phạm vi.',
                'Built upon open-source RustDesk v1.5.3 (Copyright © Purslane Tech Pte. Ltd. & Contributors, GNU AGPL-3.0) with full upstream attribution preserved in LICENSE, LICENCE, THIRD_PARTY_NOTICES, UPSTREAM_MANIFEST.json, and SBOM.spdx.json.\n'
                'Bundled offline typography licensed under SIL Open Font License 1.1 (Be Vietnam Pro, Inter, Roboto Mono).\n'
                'Operates 100% independently of DAUVERSE AI production without modifying external controllers.',
              ),
              style: DauverseTypography.body(p),
            ),
          ],
        ),
      ),
    );
  }
}
