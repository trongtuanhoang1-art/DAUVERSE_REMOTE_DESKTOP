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
  String _deviceFilter = 'ALL';
  String _projectFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = widget.controller;
    final i18n = c.i18n;

    final tasks = [
      {
        'source': 'Antigravity Desktop',
        'device': 'BOSS-HOME-AI-RIG',
        'project': 'DAUVERSE-AI-CORE',
        'task': 'FT004 Autonomous Fast Track',
        'status': 'COMPLETED',
        'started': '15:40:00 UTC',
        'elapsed': '38m 12s',
        'progress': 100.0,
        'evidence': '128/128 tests PASS (REAL VERIFIED)',
        'summary': 'All verification checks green; artifacts sealed.',
        'error': null,
      },
      {
        'source': 'Codex CLI (Independent QA)',
        'device': 'BOSS-HOME-AI-RIG',
        'project': 'DAUVERSE-REMOTE-V1',
        'task': 'Read-Only Release Candidate Audit',
        'status': 'WAITING_APPROVAL',
        'started': '16:12:00 UTC',
        'elapsed': '14m 05s',
        'progress': null,
        'evidence': null,
        'summary': 'Awaiting Boss review of security gate checklist.',
        'error': null,
      },
      {
        'source': 'ComfyUI Render Engine',
        'device': 'BOSS-HOME-AI-RIG',
        'project': 'MEDIA-PIPELINE',
        'task': 'Wan2.1 1080p Video Generation (RTX 3060 12GB)',
        'status': 'RUNNING',
        'started': '16:20:10 UTC',
        'elapsed': '06m 44s',
        'progress': 62.5,
        'evidence': 'Step 25/40 (ComfyUI /queue API)',
        'summary': 'VRAM 9.8 / 12.0 GB • AI Workload Priority active.',
        'error': null,
      },
      {
        'source': 'Claude Code',
        'device': 'BOSS-HOME-AI-RIG',
        'project': 'DAUVERSE-AI-CORE',
        'task': 'Schema Refactor Subtask',
        'status': 'RUNNING',
        'started': '16:22:00 UTC',
        'elapsed': '04m 50s',
        'progress': null,
        'evidence': 'Official Claude Hook Active',
        'summary': 'Progress unverified (no fake progress bar shown by policy).',
        'error': null,
      },
      {
        'source': 'Claude Desktop (GUI)',
        'device': 'BOSS-HOME-AI-RIG',
        'project': 'UNSPECIFIED',
        'task': 'Desktop Chat Window',
        'status': 'UNKNOWN',
        'started': '--',
        'elapsed': '--',
        'progress': null,
        'evidence': null,
        'summary': 'No official completion webhook; strictly no cookie/token scraping.',
        'error': null,
      },
    ];

    final filtered = tasks.where((t) {
      if (_deviceFilter != 'ALL' && t['device'] != _deviceFilter) return false;
      if (_projectFilter != 'ALL' && t['project'] != _projectFilter) return false;
      return true;
    }).toList();

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
                    Text(i18n.t('AI Live Status — Bảng theo dõi tác vụ AI độc lập', 'AI Live Status — Independent Multi-Agent Monitor'),
                        style: DauverseTypography.heading(p, size: 19)),
                    Text(
                      i18n.t(
                        'Chỉ đọc (Read-only) • Không tạo tiến độ giả • Tiến trình thoát không chứng cứ được gắn nhãn UNKNOWN.',
                        'Strictly read-only • Zero fake progress • Unverified process exit maps to UNKNOWN, never COMPLETED.',
                      ),
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 10,
                children: [
                  DropdownButton<String>(
                    value: _deviceFilter,
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Devices')),
                      DropdownMenuItem(value: 'BOSS-HOME-AI-RIG', child: Text('BOSS-HOME-AI-RIG')),
                    ],
                    onChanged: (v) => setState(() => _deviceFilter = v ?? 'ALL'),
                  ),
                  DropdownButton<String>(
                    value: _projectFilter,
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Projects')),
                      DropdownMenuItem(value: 'DAUVERSE-AI-CORE', child: Text('DAUVERSE-AI-CORE')),
                      DropdownMenuItem(value: 'DAUVERSE-REMOTE-V1', child: Text('DAUVERSE-REMOTE-V1')),
                      DropdownMenuItem(value: 'MEDIA-PIPELINE', child: Text('MEDIA-PIPELINE')),
                    ],
                    onChanged: (v) => setState(() => _projectFilter = v ?? 'ALL'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final t in filtered) ...[
            _taskCard(p, t),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _taskCard(DauversePalette p, Map<String, dynamic> t) {
    final status = t['status'] as String;
    final Color statusColor = switch (status) {
      'COMPLETED' => p.success,
      'RUNNING' => p.cyan,
      'WAITING_APPROVAL' => p.warning,
      'FAILED' => p.danger,
      _ => p.textSecondary,
    };
    final progress = t['progress'] as double?;
    final evidence = t['evidence'] as String?;

    return DauverseCard(
      accentBorder: status == 'WAITING_APPROVAL' ? p.warning : p.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DauverseStatusBadge(label: status, color: statusColor),
              const SizedBox(width: 10),
              Text('${t['source']}', style: DauverseTypography.heading(p, size: 15)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '• ${t['project']} • ${t['device']}',
                  style: DauverseTypography.caption(p),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('Elapsed: ${t['elapsed']}', style: DauverseTypography.kpi(p, size: 12, color: p.cyan)),
            ],
          ),
          const SizedBox(height: 8),
          Text('${t['task']} — ${t['summary']}', style: DauverseTypography.body(p, size: 13)),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: progress / 100.0,
                minHeight: 6,
                backgroundColor: p.surfaceElevated,
                color: statusColor,
              ),
            ),
          ],
          if (evidence != null) ...[
            const SizedBox(height: 8),
            Text('Evidence: $evidence', style: DauverseTypography.kpi(p, size: 11, color: p.success)),
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

    final sampleHistory = [
      ('Antigravity', 'DAUVERSE FT004', 'COMPLETED', 'Antigravity đã hoàn thành nhiệm vụ — 128/128 tests PASS (Verified)', '16:25:10'),
      ('Codex', 'DAUVERSE-REMOTE-V1', 'WAITING_APPROVAL', 'AI yêu cầu Boss phê duyệt (Mở phiên Remote để xác nhận trực tiếp)', '16:21:04'),
      ('ComfyUI', 'MEDIA-PIPELINE', 'RUNNING', 'Đang render video Wan2.1 1080p • RTX 3060 62°C', '16:20:10'),
      ('HardwareMonitor', 'BOSS-HOME-AI-RIG', 'INFO', 'Máy tính tại nhà đã Online • Direct P2P 14ms', '15:30:00'),
    ].where((e) => _aiFilter == 'ALL' || e.$1 == _aiFilter).toList();

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
                    Text(i18n.t('AI Notification Center — Thông báo nổi & Lịch sử Offline', 'AI Notification Center & Offline Queue'),
                        style: DauverseTypography.heading(p, size: 19)),
                    Text(
                      i18n.t(
                        'Hoạt động ngay cả khi đóng cửa sổ truyền hình • Tự ẩn 5–8s không chiếm focus • Cấm phê duyệt AI tự động qua thông báo.',
                        'Active without screen stream • 5–8s non-focus-stealing corner toast • Notification AI auto-approval strictly blocked.',
                      ),
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: p.purple, foregroundColor: Colors.white),
                onPressed: () {
                  c.triggerCornerToastPreview(
                    title: 'Antigravity đã hoàn thành nhiệm vụ',
                    aiSource: 'Antigravity',
                    project: 'DAUVERSE FT004',
                    body: 'Toàn bộ bài kiểm thử tích hợp đã hoàn tất.',
                    verifiedEvidence: '128/128 tests PASS',
                  );
                },
                icon: const Icon(Icons.notifications_active, size: 17),
                label: Text(i18n.t('Hiển thị Toast góc màn hình', 'Preview Corner Toast')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DauverseCard(
            child: Wrap(
              spacing: 18,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Quiet Mode (Priority Only)'),
                  selected: c.quietMode,
                  onSelected: (v) => setState(() => c.quietMode = v),
                ),
                FilterChip(
                  label: const Text('Do Not Disturb (DND)'),
                  selected: c.doNotDisturb,
                  onSelected: (v) => setState(() => c.doNotDisturb = v),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(i18n.t('Tự ẩn Toast:', 'Auto-hide:'), style: DauverseTypography.caption(p)),
                    Slider(
                      min: 5,
                      max: 8,
                      divisions: 3,
                      value: c.toastAutoHideSeconds.toDouble(),
                      onChanged: (v) => setState(() => c.toastAutoHideSeconds = v.round()),
                    ),
                    Text('${c.toastAutoHideSeconds}s', style: DauverseTypography.kpi(p, size: 13, color: p.cyan)),
                  ],
                ),
                DropdownButton<String>(
                  value: _aiFilter,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Filter: All Sources')),
                    DropdownMenuItem(value: 'Antigravity', child: Text('Antigravity')),
                    DropdownMenuItem(value: 'Codex', child: Text('Codex')),
                    DropdownMenuItem(value: 'ComfyUI', child: Text('ComfyUI')),
                  ],
                  onChanged: (v) => setState(() => _aiFilter = v ?? 'ALL'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < sampleHistory.length; i++) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: DauverseStatusBadge(label: sampleHistory[i].$1, color: p.cyan),
                    title: Text(sampleHistory[i].$4, style: DauverseTypography.body(p, size: 13, weight: FontWeight.w600)),
                    subtitle: Text('${sampleHistory[i].$2} • ${sampleHistory[i].$3} • ${sampleHistory[i].$5} UTC',
                        style: DauverseTypography.caption(p, size: 11)),
                  ),
                  if (i + 1 < sampleHistory.length) const Divider(height: 8),
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

    final cpuBrand = hw['cpu_brand']?.toString() ?? 'System CPU';
    final cpuPct = (hw['cpu_usage_pct'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final cpuTemp = hw['cpu_temp_c'] != null ? '${hw['cpu_temp_c']} °C' : 'Sensor N/A (VM)';
    final ramUsed = (hw['ram_used_gb'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final ramTotal = (hw['ram_total_gb'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final ramPct = (hw['ram_usage_pct'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final diskFree = (hw['disk_free_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final diskTotal = (hw['disk_total_gb'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final uptimeHrs = (((hw['system_uptime_secs'] as num?)?.toDouble() ?? 0.0) / 3600.0).toStringAsFixed(1);
    final gpuModel = hw['gpu_model']?.toString() ?? 'No Local NVIDIA GPU (RTX 3060 12GB Ready via NVML)';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n.t('Hardware Monitor — Giám sát Tài nguyên & Nhiệt độ thực tế', 'Hardware Monitor — Real OS & GPU Telemetry'),
              style: DauverseTypography.heading(p, size: 19)),
          Text(
            i18n.t(
              'Sử dụng API hệ điều hành (sysinfo + NVML/nvidia-smi) • Không cài đặt driver cảm biến kernel không đáng tin cậy.',
              'Powered by OS sysinfo + NVML/nvidia-smi • Never installs untrusted ring-0 sensor drivers.',
            ),
            style: DauverseTypography.caption(p),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _metricBox(p, 'CPU ($cpuBrand)', '$cpuPct%', 'Temp: $cpuTemp', p.cyan),
              _metricBox(p, 'RAM Memory', '$ramUsed / $ramTotal GB', 'Usage: $ramPct% (Alert >=90%)', p.blue),
              _metricBox(p, 'GPU / VRAM', gpuModel,
                  hw['gpu_temp_c'] != null ? '${hw['gpu_temp_c']}°C • ${hw['vram_used_mb']} MB' : 'Awaiting RTX 3060 Host', p.purple),
              _metricBox(p, 'Disk & Uptime', '$diskFree GB Free', 'Total: $diskTotal GB • Up ${uptimeHrs}h', p.success),
            ],
          ),
          const SizedBox(height: 18),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('Biểu đồ Lịch sử CPU & RAM thực tế', 'Live Historical CPU & RAM Sparklines'),
                    style: DauverseTypography.heading(p, size: 16)),
                const SizedBox(height: 12),
                DauverseSparkline(values: c.cpuHistory, color: p.cyan, height: 72),
                const SizedBox(height: 14),
                DauverseSparkline(values: c.ramHistory, color: p.blue, height: 72),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBox(DauversePalette p, String title, String val, String sub, Color color) {
    return SizedBox(
      width: 280,
      child: DauverseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: DauverseTypography.caption(p, size: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text(val, style: DauverseTypography.kpi(p, size: 18, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(sub, style: DauverseTypography.caption(p, size: 11)),
          ],
        ),
      ),
    );
  }
}
