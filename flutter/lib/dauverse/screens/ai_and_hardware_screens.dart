import 'package:flutter/material.dart';
import '../bridge/dauverse_bridge.dart';
import '../theme/dauverse_theme.dart';

class DauverseAiLiveStatusScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseAiLiveStatusScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseAiLiveStatusScreen> createState() => _DauverseAiLiveStatusScreenState();
}

class _DauverseAiLiveStatusScreenState extends State<DauverseAiLiveStatusScreen> {
  String _statusFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final ai = c.snapshot['ai_summary'] as Map<String, dynamic>? ?? const {};
    final bridgeUrl = c.snapshot['bridge_endpoint']?.toString() ?? 'http://127.0.0.1:21188/v1/events';
    final rejectedCount = ai['rejected_security_count']?.toString() ?? '0';
    final liveTasks = (ai['live_tasks'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final catalog = (ai['sources_catalog'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();

    final filtered = liveTasks.where((t) {
      if (_statusFilter != 'ALL' && t['status']?.toString() != _statusFilter) return false;
      return true;
    }).toList();

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
                constraints: const BoxConstraints(maxWidth: 660),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t(
                        'AI Live Status — Bảng theo dõi tác vụ AI thực tế (HTTP + HMAC)',
                        'AI Live Status — Live HMAC-Verified Bridge Tasks',
                      ),
                      style: DauverseTypography.heading(p, size: 19),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$bridgeUrl  •  Rejected Spoof/Replay: $rejectedCount  •  ${i18n.t("Không tạo tác vụ/tiến độ giả", "Zero fake tasks or synthetic progress")}',
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: _statusFilter,
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
                      DropdownMenuItem(value: 'RUNNING', child: Text('RUNNING')),
                      DropdownMenuItem(value: 'WAITING_APPROVAL', child: Text('WAITING_APPROVAL')),
                      DropdownMenuItem(value: 'COMPLETED', child: Text('COMPLETED')),
                      DropdownMenuItem(value: 'FAILED', child: Text('FAILED')),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v ?? 'ALL'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: p.purple, foregroundColor: Colors.white),
                    onPressed: () => c.sendSignedLoopbackAiProbe(source: 'codex_cli'),
                    icon: const Icon(Icons.bolt, size: 17),
                    label: Text(i18n.t('Gửi Probe HMAC thật', 'Send Real Signed Probe')),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            DauverseCard(
              child: Text(
                i18n.t(
                  'Hiện có 0 sự kiện AI đang hoạt động (không hiển thị dữ liệu mẫu giả mạo). Cổng HTTP nội bộ đang lắng nghe trực tiếp tại $bridgeUrl cho claude_code_hook.py, codex_notify_hook.py và dauverse_job_wrapper.ps1.',
                  '0 verified AI tasks ingested yet (zero fake demo cards). The loopback HTTP listener is live at $bridgeUrl awaiting signed events from Claude Code, Codex CLI, or PowerShell hooks.',
                ),
                style: DauverseTypography.body(p, size: 13),
              ),
            )
          else
            for (final t in filtered) ...[
              _taskCard(p, t),
              const SizedBox(height: 12),
            ],
          if (catalog.isNotEmpty) ...[
            const SizedBox(height: 16),
            DauverseCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.t(
                      'Danh mục Adapter Nguồn AI & Trạng thái Hỗ trợ trung thực',
                      'Supported AI Sources & Honest Adapter Capabilities',
                    ),
                    style: DauverseTypography.heading(p, size: 15),
                  ),
                  const SizedBox(height: 8),
                  for (final src in catalog)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DauverseStatusBadge(
                            label: src['support_status']?.toString() ?? 'UNKNOWN',
                            color: src['support_status'] == 'UNKNOWN' ? p.warning : p.cyan,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${src['display_name']}: ${src['notes']}',
                              style: DauverseTypography.caption(p, size: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _taskCard(DauversePalette p, Map<String, dynamic> t) {
    final status = t['status']?.toString() ?? 'UNKNOWN';
    final Color statusColor = switch (status) {
      'COMPLETED' => p.success,
      'RUNNING' => p.cyan,
      'WAITING_APPROVAL' => p.warning,
      'FAILED' => p.danger,
      _ => p.textSecondary,
    };
    final progress = ((t['verified_progress'] ?? t['progress']) as num?)?.toDouble();
    final evidence = (t['verified_test_evidence'] ?? t['evidence_badge'])?.toString();
    final updatedAt = (t['updated_at_utc'] ?? t['updated_at'])?.toString() ?? '';
    final summary = (t['latest_event_summary'] ?? t['last_summary'])?.toString() ?? '';

    return DauverseCard(
      accentBorder: status == 'WAITING_APPROVAL' ? p.warning : p.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DauverseStatusBadge(label: status, color: statusColor),
                  Text('${t['source']}', style: DauverseTypography.heading(p, size: 15)),
                  Text(
                    '• ${t['project_id']} • ${t['device_id']}',
                    style: DauverseTypography.caption(p),
                  ),
                ],
              ),
              Text(updatedAt, style: DauverseTypography.kpi(p, size: 11, color: p.cyan)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            summary.isNotEmpty ? '${t['task_name']} — $summary' : '${t['task_name']}',
            style: DauverseTypography.body(p, size: 13),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: (progress / 100.0).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: p.surfaceElevated,
                color: statusColor,
              ),
            ),
          ],
          if (evidence != null && evidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Verified Evidence: $evidence', style: DauverseTypography.kpi(p, size: 11, color: p.success)),
          ],
        ],
      ),
    );
  }
}

class DauverseNotificationCenterScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseNotificationCenterScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseNotificationCenterScreen> createState() => _DauverseNotificationCenterScreenState();
}

class _DauverseNotificationCenterScreenState extends State<DauverseNotificationCenterScreen> {
  String _aiFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;
    final notif = c.snapshot['notifications'] as Map<String, dynamic>? ?? const {};
    final items = (notif['recent_items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((it) {
          final src = (it['ai_source'] ?? it['source'])?.toString() ?? '';
          return _aiFilter == 'ALL' || src == _aiFilter;
        })
        .toList();

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
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t(
                        'AI Notification Center — Hàng đợi thực tế & Nhật ký Offline',
                        'AI Notification Center — Live History & Offline Journal',
                      ),
                      style: DauverseTypography.heading(p, size: 19),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      i18n.t(
                        'Đồng bộ trực tiếp với NotificationCenter • Tự ẩn 5–8s không chiếm focus • Cấm phê duyệt AI tự động qua thông báo.',
                        'Synced directly with NotificationCenter • 5–8s non-focus-stealing toast • Notification AI auto-approval blocked.',
                      ),
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      DauverseNativeBridge.instance.call('notification_mark_read');
                      c.refreshSnapshot();
                    },
                    child: Text(i18n.t('Đánh dấu đã đọc hết', 'Mark All Read')),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: p.purple, foregroundColor: Colors.white),
                    onPressed: () => c.sendSignedLoopbackAiProbe(source: 'claude_code'),
                    icon: const Icon(Icons.notifications_active, size: 17),
                    label: Text(i18n.t('Gửi sự kiện Toast thật (HTTP)', 'Trigger Real Signed HTTP Toast')),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          DauverseCard(
            child: Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Quiet Mode (Priority Only)'),
                  selected: c.quietMode,
                  onSelected: (v) => c.updateNotificationPrefs(quiet: v),
                ),
                FilterChip(
                  label: const Text('Do Not Disturb (DND)'),
                  selected: c.doNotDisturb,
                  onSelected: (v) => c.updateNotificationPrefs(dnd: v),
                ),
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(i18n.t('Tự ẩn Toast:', 'Auto-hide:'), style: DauverseTypography.caption(p)),
                    SizedBox(
                      width: 135,
                      child: Slider(
                        min: 5,
                        max: 8,
                        divisions: 3,
                        value: c.toastAutoHideSeconds.toDouble(),
                        onChanged: (v) => c.updateNotificationPrefs(autoHideSec: v.round()),
                      ),
                    ),
                    Text('${c.toastAutoHideSeconds}s', style: DauverseTypography.kpi(p, size: 13, color: p.cyan)),
                  ],
                ),
                DropdownButton<String>(
                  value: _aiFilter,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Filter: All Sources')),
                    DropdownMenuItem(value: 'claude_code', child: Text('claude_code')),
                    DropdownMenuItem(value: 'codex_cli', child: Text('codex_cli')),
                    DropdownMenuItem(value: 'comfyui', child: Text('comfyui')),
                  ],
                  onChanged: (v) => setState(() => _aiFilter = v ?? 'ALL'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: items.isEmpty
                ? Text(
                    i18n.t(
                      'Lịch sử thông báo hiện có 0 mục (không hiển thị thông báo giả). Nhấn "Gửi sự kiện Toast thật (HTTP)" hoặc chạy hook Claude/Codex để nhận thông báo thực.',
                      'Notification history currently has 0 items (zero fake sample entries). Click "Trigger Real Signed HTTP Toast" or run a Claude/Codex hook to ingest a real event.',
                    ),
                    style: DauverseTypography.body(p, size: 13),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        Builder(builder: (_) {
                          final it = items[i];
                          final src = (it['ai_source'] ?? it['source'])?.toString() ?? 'AI';
                          final proj = (it['project_name'] ?? it['project_id'])?.toString() ?? 'workspace';
                          final evLine = it['verified_evidence_line']?.toString();
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: DauverseStatusBadge(label: src, color: p.cyan),
                            title: Text(
                              '${it['title']} — ${it['body']}',
                              style: DauverseTypography.body(p, size: 13, weight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              evLine != null && evLine.isNotEmpty
                                  ? '$proj • ${it['category']} • $evLine • ${it['created_at_utc']}'
                                  : '$proj • ${it['category']} • ${it['created_at_utc']}',
                              style: DauverseTypography.caption(p, size: 11),
                            ),
                          );
                        }),
                        if (i + 1 < items.length) const Divider(height: 8),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class DauverseHardwareMonitorScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseHardwareMonitorScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = controller;
    final i18n = c.i18n;
    final hw = c.snapshot['hardware'] as Map<String, dynamic>? ?? const {};
    final alerts = (c.snapshot['hardware_alerts'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final procs = (hw['ai_processes'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();

    final scope = hw['telemetry_scope']?.toString() ?? 'LOCAL_HOST_SENSORS';
    final cpuBrand = hw['cpu_brand']?.toString() ?? 'System CPU';
    final cpuPct = (hw['cpu_usage_pct'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final cpuTemp = hw['cpu_temp_c'] != null ? '${hw['cpu_temp_c']} °C' : 'Sensor N/A';
    final ramUsed = (hw['ram_used_gb'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final ramTotal = (hw['ram_total_gb'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final ramPct = (hw['ram_usage_pct'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final diskFree = (hw['disk_free_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final diskTotal = (hw['disk_total_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final uptimeHrs = (((hw['system_uptime_secs'] as num?)?.toDouble() ?? 0.0) / 3600.0).toStringAsFixed(1);
    final gpuModel = hw['gpu_model']?.toString() ?? 'No Local NVIDIA GPU Detected';

    return LayoutBuilder(
      builder: (context, viewport) {
        final contentWidth = (viewport.maxWidth - 40).clamp(240.0, 2400.0);
        final int cols = contentWidth >= 1120 ? 4 : (contentWidth >= 560 ? 2 : 1);
        final double cardW = (contentWidth - (cols - 1) * 14.0) / cols;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i18n.t(
                            'Hardware Monitor — Giám sát Phần cứng Máy Cục bộ thực tế',
                            'Hardware Monitor — Live Local Host OS & GPU Sensors',
                          ),
                          style: DauverseTypography.heading(p, size: 19),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          i18n.t(
                            'Phạm vi đo: Máy đang chạy ứng dụng ($scope) qua sysinfo + nvidia-smi (CREATE_NO_WINDOW, cache 4s).',
                            'Measurement scope: Current host ($scope) via sysinfo + cached nvidia-smi (CREATE_NO_WINDOW).',
                          ),
                          style: DauverseTypography.caption(p),
                        ),
                      ],
                    ),
                  ),
                  DauverseStatusBadge(label: scope, color: p.cyan),
                ],
              ),
              const SizedBox(height: 16),
              if (alerts.isNotEmpty) ...[
                DauverseCard(
                  accentBorder: p.danger,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final a in alerts)
                        Text(
                          'ALERT [${a['code']}]: ${a['message']}',
                          style: DauverseTypography.kpi(p, size: 12, color: p.danger),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _metricBox(p, cardW, 'CPU ($cpuBrand)', '$cpuPct%', 'Temp: $cpuTemp', p.cyan),
                  _metricBox(p, cardW, 'RAM Memory', '$ramUsed / $ramTotal GB', 'Usage: $ramPct% (Alert >=90%)', p.blue),
                  _metricBox(
                    p,
                    cardW,
                    'GPU / VRAM',
                    gpuModel,
                    hw['gpu_temp_c'] != null ? '${hw['gpu_temp_c']}°C • ${hw['vram_used_mb']} MB' : 'NVML / nvidia-smi Idle',
                    p.purple,
                  ),
                  _metricBox(p, cardW, 'Disk & Uptime', '$diskFree GB Free', 'Total: $diskTotal GB • Up ${uptimeHrs}h', p.success),
                ],
              ),
              const SizedBox(height: 18),
              DauverseCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t('Biểu đồ Lịch sử CPU & RAM thực tế', 'Live Historical CPU & RAM Sparklines'),
                      style: DauverseTypography.heading(p, size: 16),
                    ),
                    const SizedBox(height: 12),
                    DauverseSparkline(values: c.cpuHistory.isEmpty ? const [0, 0] : c.cpuHistory, color: p.cyan, height: 72),
                    const SizedBox(height: 14),
                    DauverseSparkline(values: c.ramHistory.isEmpty ? const [0, 0] : c.ramHistory, color: p.blue, height: 72),
                  ],
                ),
              ),
              if (procs.isNotEmpty) ...[
                const SizedBox(height: 16),
                DauverseCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i18n.t('Tiến trình AI / Toolchain phát hiện trên máy này', 'Detected Local AI / Toolchain Processes'),
                        style: DauverseTypography.heading(p, size: 15),
                      ),
                      const SizedBox(height: 8),
                      for (final pr in procs.take(8))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            'PID ${pr['pid']} • ${pr['name']} (${pr['category']}) — CPU ${(pr['cpu_pct'] as num?)?.toStringAsFixed(1) ?? "0"}% • RAM ${pr['memory_mb']} MB',
                            style: DauverseTypography.kpi(p, size: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _metricBox(DauversePalette p, double width, String title, String val, String sub, Color color) {
    return SizedBox(
      width: width,
      child: DauverseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: DauverseTypography.caption(p, size: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(val, style: DauverseTypography.kpi(p, size: 18, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(sub, style: DauverseTypography.caption(p, size: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
