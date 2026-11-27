import 'package:flutter/material.dart';
import '../bridge/dauverse_bridge.dart';
import '../theme/dauverse_theme.dart';

class DauverseFileTransferScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseFileTransferScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseFileTransferScreen> createState() => _DauverseFileTransferScreenState();
}

class _DauverseFileTransferScreenState extends State<DauverseFileTransferScreen> {
  double _bwLimitMbps = 80;
  bool _bwCapEnabled = false;
  late final TextEditingController _peerCtrl;

  @override
  void initState() {
    super.initState();
    _peerCtrl = TextEditingController(text: widget.controller.targetPeerId);
    final tq = widget.controller.snapshot['transfer_queue'] as Map<String, dynamic>? ?? const {};
    final kbps = (tq['bandwidth_limit_kbps'] as num?)?.toDouble();
    if (kbps != null && kbps > 0) {
      _bwCapEnabled = true;
      _bwLimitMbps = (kbps / 1024.0).clamp(5.0, 200.0);
    }
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
    final tq = c.snapshot['transfer_queue'] as Map<String, dynamic>? ?? const {};
    final jobs = (tq['jobs'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final authRoot = tq['authorized_root']?.toString() ?? '';
    final overwriteVal = const {'REQUIRE_CONFIRMATION', 'AUTO_RENAME', 'SKIP'}.contains(c.transferOverwritePolicy)
        ? c.transferOverwritePolicy
        : 'REQUIRE_CONFIRMATION';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t('Trung tâm Truyền dữ liệu An toàn (File Transfer Center)', 'Secure File Transfer Center'),
                      style: DauverseTypography.heading(p, size: 19),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      i18n.t(
                        'Đã gắn trực tiếp transfer_guard vào luồng nhận file (ui_cm_interface.rs) • Chống Path Traversal, Symlink & Reparse Point.',
                        'Wired directly into host file write path (ui_cm_interface.rs) • Blocks Path Traversal, Symlink & NTFS Reparse Points.',
                      ),
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _peerCtrl,
                      onChanged: (v) => c.targetPeerId = v.trim(),
                      style: DauverseTypography.kpi(p, size: 13.5),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: i18n.t('ID / IP thiết bị đích...', 'Target Peer ID / IP...'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: i18n.t('Dán từ Clipboard', 'Paste from Clipboard'),
                          icon: Icon(Icons.content_paste_rounded, size: 17, color: p.cyan),
                          onPressed: () async {
                            final txt = await c.pasteFromClipboard();
                            if (txt.isNotEmpty) {
                              _peerCtrl.text = txt;
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onPressed: () => c.launchRealFileTransfer(context, _peerCtrl.text),
                    icon: const Icon(Icons.folder_shared, size: 18),
                    label: Text(i18n.t('Mở Trình duyệt File hai chiều', 'Open Dual-Pane File Transfer')),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Switch(
                      value: _bwCapEnabled,
                      onChanged: (v) {
                        setState(() => _bwCapEnabled = v);
                        c.updateTransferBandwidthCap(v ? (_bwLimitMbps.round() * 1024) : null);
                      },
                    ),
                    Text(
                      i18n.t('Giới hạn băng thông:', 'Bandwidth Cap:'),
                      style: DauverseTypography.body(p),
                    ),
                    SizedBox(
                      width: 145,
                      child: Slider(
                        min: 5,
                        max: 200,
                        value: _bwLimitMbps,
                        onChanged: _bwCapEnabled
                            ? (v) {
                                setState(() => _bwLimitMbps = v);
                                c.updateTransferBandwidthCap(v.round() * 1024);
                              }
                            : null,
                      ),
                    ),
                    Text(
                      _bwCapEnabled ? '${_bwLimitMbps.round()} MB/s' : 'UNLIMITED',
                      style: DauverseTypography.kpi(p, size: 13, color: p.cyan),
                    ),
                  ],
                ),
                DropdownButton<String>(
                  value: overwriteVal,
                  items: [
                    DropdownMenuItem(
                      value: 'REQUIRE_CONFIRMATION',
                      child: Text(i18n.t('Trùng tên: Hỏi xác nhận', 'Duplicate: Ask Confirmation')),
                    ),
                    DropdownMenuItem(
                      value: 'AUTO_RENAME',
                      child: Text(i18n.t('Trùng tên: Tự đổi tên (1)', 'Duplicate: Auto-Rename (1)')),
                    ),
                    DropdownMenuItem(
                      value: 'SKIP',
                      child: Text(i18n.t('Trùng tên: Bỏ qua file cũ', 'Duplicate: Skip Existing')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      c.updateTransferOverwritePolicy(v);
                    }
                  },
                ),
                if (authRoot.isNotEmpty)
                  Text('Sandbox Root: $authRoot', style: DauverseTypography.caption(p, size: 11)),
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
                    'Hàng đợi truyền file thực tế (TransferQueueManager — Hồi tiếp SHA-256 & Resume 2 chiều)',
                    'Live Transfer Queue (TransferQueueManager — Bidirectional Resume & SHA-256)',
                  ),
                  style: DauverseTypography.heading(p, size: 16),
                ),
                const SizedBox(height: 12),
                if (jobs.isEmpty)
                  Text(
                    i18n.t(
                      'Hiện có 0 tác vụ trong hàng đợi (không hiển thị file mẫu giả mạo). Nhập ID/IP thiết bị và nhấn "Mở Trình duyệt File hai chiều" để truyền file/thư mục thực.',
                      '0 transfer jobs currently queued (zero fake mock rows). Enter a Peer ID and open Dual-Pane File Transfer to send or receive real files.',
                    ),
                    style: DauverseTypography.body(p, size: 13),
                  )
                else
                  for (var idx = 0; idx < jobs.length; idx++) ...[
                    _transferRow(p, jobs[idx]),
                    if (idx + 1 < jobs.length) const Divider(height: 20),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transferRow(DauversePalette p, Map<String, dynamic> item) {
    final c = widget.controller;
    final jobId = item['job_id']?.toString() ?? '';
    final st = item['status']?.toString() ?? 'QUEUED';
    final total = (item['total_bytes'] as num?)?.toDouble() ?? 1.0;
    final done = (item['transferred_bytes'] as num?)?.toDouble() ?? 0.0;
    final progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final sha = item['verified_sha256']?.toString() ?? 'Pending SHA-256 verification';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file_outlined, color: p.cyan, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${item['relative_path']}  (${item['total_bytes']} B)',
                      style: DauverseTypography.body(p, size: 13, weight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DauverseStatusBadge(
                  label: st,
                  color: st == 'COMPLETED' ? p.success : (st == 'PAUSED' ? p.warning : p.cyan),
                ),
                IconButton(
                  tooltip: st == 'PAUSED' ? 'Resume' : 'Pause',
                  icon: Icon(st == 'PAUSED' ? Icons.play_arrow : Icons.pause, size: 18, color: p.cyan),
                  onPressed: st == 'COMPLETED'
                      ? null
                      : () => c.controlTransferJob(st == 'PAUSED' ? 'RESUME' : 'PAUSE', jobId),
                ),
                IconButton(
                  tooltip: 'Retry',
                  icon: Icon(Icons.refresh, size: 18, color: p.blue),
                  onPressed: () => c.controlTransferJob('RETRY', jobId),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  icon: Icon(Icons.close, size: 18, color: p.danger),
                  onPressed: st == 'COMPLETED' ? null : () => c.controlTransferJob('CANCEL', jobId),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: p.surfaceElevated,
            color: st == 'COMPLETED' ? p.success : p.cyan,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'SHA-256: $sha  •  Auto-Execute: BLOCKED',
          style: DauverseTypography.kpi(p, size: 11, color: p.success),
        ),
      ],
    );
  }
}

class DauverseClipboardSettingsScreen extends StatelessWidget {
  final DauverseController controller;
  const DauverseClipboardSettingsScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final c = controller;
    final i18n = c.i18n;
    final clipStats = c.snapshot['clipboard'] as Map<String, dynamic>? ?? const {};
    final pol = clipStats['policy'] as Map<String, dynamic>? ?? const {};

    final enabled = pol['enabled'] != false;
    final vnUnicode = pol['allow_text_unicode'] != false;
    final richHtml = pol['allow_rich_html'] != false;
    final images = pol['allow_images'] != false;
    final files = pol['allow_files'] != false;
    final rawDir = pol['direction']?.toString() ?? 'BIDIRECTIONAL';
    final direction = switch (rawDir) {
      'CLIENT_TO_HOST_ONLY' || 'CLIENT_TO_HOST' => 'CLIENT_TO_HOST',
      'HOST_TO_CLIENT_ONLY' || 'HOST_TO_CLIENT' => 'HOST_TO_CLIENT',
      'DISABLED' => 'DISABLED',
      _ => 'BIDIRECTIONAL',
    };
    final syncedCount = clipStats['synced_items_count']?.toString() ?? '0';
    final blockedLoops = clipStats['blocked_loops_count']?.toString() ?? '0';

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
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.t(
                        'Smart Clipboard — Đồng bộ hai chiều gắn trực tiếp vào Engine',
                        'Smart Clipboard — Live Engine Policy & Loop Guard',
                      ),
                      style: DauverseTypography.heading(p, size: 19),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      i18n.t(
                        'Đã nối trực tiếp vào src/clipboard.rs & Config(enable-clipboard) • Không bao giờ ghi log nội dung nhạy cảm.',
                        'Wired directly into src/clipboard.rs & Config(enable-clipboard) • Zero sensitive clipboard logging.',
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
                  DauverseStatusBadge(label: 'SYNCED: $syncedCount', color: p.success),
                  DauverseStatusBadge(label: 'LOOPS BLOCKED: $blockedLoops', color: p.cyan),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    i18n.t('Bật đồng bộ Clipboard tự nhiên (Ctrl+C / Ctrl+V)', 'Enable Natural Ctrl+C / Ctrl+V Sync'),
                    style: DauverseTypography.body(p, size: 14, weight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    i18n.t(
                      'Tự động chặn vòng lặp clipboard (Echo-Loop Suppression SHA-256)',
                      'Automatic SHA-256 echo-loop suppression without logging content',
                    ),
                  ),
                  value: enabled,
                  onChanged: (v) => c.updateClipboardPolicy({'enabled': v}),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        i18n.t('Chiều phân quyền theo phiên:', 'Session Sync Direction:'),
                        style: DauverseTypography.body(p, weight: FontWeight.w600),
                      ),
                      DropdownButton<String>(
                        value: direction,
                        items: const [
                          DropdownMenuItem(value: 'BIDIRECTIONAL', child: Text('Bidirectional (2 chiều)')),
                          DropdownMenuItem(value: 'CLIENT_TO_HOST', child: Text('Office -> Home Only')),
                          DropdownMenuItem(value: 'HOST_TO_CLIENT', child: Text('Home -> Office Only')),
                          DropdownMenuItem(value: 'DISABLED', child: Text('Disabled (Tắt hẳn)')),
                        ],
                        onChanged: (v) {
                          if (v != null) c.updateClipboardPolicy({'direction': v});
                        },
                      ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tiếng Việt Unicode / Prompt AI / Source Code / PowerShell / JSON / Markdown'),
                  value: vnUnicode,
                  onChanged: (v) => c.updateClipboardPolicy({'allow_text_unicode': v ?? true}),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rich Text & HTML Formatting'),
                  value: richHtml,
                  onChanged: (v) => c.updateClipboardPolicy({'allow_rich_html': v ?? true}),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hình ảnh & Screenshot (Max 64 MiB)'),
                  value: images,
                  onChanged: (v) => c.updateClipboardPolicy({'allow_images': v ?? true}),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Copy/Paste File & Nhiều File (Chống Path Traversal)'),
                  value: files,
                  onChanged: (v) => c.updateClipboardPolicy({'allow_files': v ?? true}),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
