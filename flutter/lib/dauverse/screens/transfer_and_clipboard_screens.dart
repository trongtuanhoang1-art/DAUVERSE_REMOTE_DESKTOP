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
  bool _bwCapEnabled = true;
  String _overwritePolicy = 'REQUIRE_CONFIRMATION';

  final List<Map<String, dynamic>> _queue = [
    {
      'name': 'comfyui_wan2_render_1080p.mp4',
      'dir': 'Download <- HOME-RTX3060',
      'size': '1.42 GB',
      'progress': 0.74,
      'speed': '48.2 MB/s',
      'eta': '00:08',
      'status': 'ACTIVE',
      'sha256': 'SHA-256 Pending Stream...',
    },
    {
      'name': 'dauverse_prompt_pack_vi.json',
      'dir': 'Upload -> HOME-RTX3060',
      'size': '248 KB',
      'progress': 1.0,
      'speed': '0 MB/s',
      'eta': '00:00',
      'status': 'COMPLETED',
      'sha256': 'VERIFIED (e3b0c44298fc...)',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final i18n = widget.controller.i18n;

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
                    Text(i18n.t('Trung tâm Truyền dữ liệu An toàn (File Transfer Center)', 'Secure File Transfer Center'),
                        style: DauverseTypography.heading(p, size: 19)),
                    Text(
                      i18n.t(
                        'Chống Path Traversal, Symlink, Reparse Point & Junction • Kiểm tra SHA-256 • Không bao giờ tự thực thi file nhận.',
                        'Protected against Path Traversal, Symlink, Junction & Reparse Points • SHA-256 verified • Inert non-executing.',
                      ),
                      style: DauverseTypography.caption(p),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: p.blue, foregroundColor: Colors.white),
                onPressed: widget.controller.openClassicRustDeskView,
                icon: const Icon(Icons.folder_shared, size: 18),
                label: Text(i18n.t('Mở Trình duyệt File hai chiều', 'Open Dual-Pane Native File Browser')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Wrap(
              spacing: 20,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(value: _bwCapEnabled, onChanged: (v) => setState(() => _bwCapEnabled = v)),
                    Text(i18n.t('Giới hạn băng thông (bảo vệ phiên Remote/AI):', 'Bandwidth Limit:'),
                        style: DauverseTypography.body(p)),
                    SizedBox(
                      width: 150,
                      child: Slider(
                        min: 5,
                        max: 200,
                        value: _bwLimitMbps,
                        onChanged: _bwCapEnabled ? (v) => setState(() => _bwLimitMbps = v) : null,
                      ),
                    ),
                    Text('${_bwLimitMbps.round()} MB/s', style: DauverseTypography.kpi(p, size: 13, color: p.cyan)),
                  ],
                ),
                DropdownButton<String>(
                  value: _overwritePolicy,
                  items: const [
                    DropdownMenuItem(value: 'REQUIRE_CONFIRMATION', child: Text('Duplicate: Ask Confirmation')),
                    DropdownMenuItem(value: 'AUTO_RENAME', child: Text('Duplicate: Auto-Rename (1)')),
                    DropdownMenuItem(value: 'SKIP', child: Text('Duplicate: Skip Existing')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _overwritePolicy = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('Hàng đợi truyền file & Lịch sử toàn vẹn (Transfer Queue)', 'Transfer Queue & Integrity History'),
                    style: DauverseTypography.heading(p, size: 16)),
                const SizedBox(height: 12),
                for (var idx = 0; idx < _queue.length; idx++) ...[
                  _transferRow(p, idx),
                  if (idx + 1 < _queue.length) const Divider(height: 20),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transferRow(DauversePalette p, int index) {
    final item = _queue[index];
    final st = item['status'] as String;
    final progress = (item['progress'] as num).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.insert_drive_file_outlined, color: p.cyan, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${item['name']}  (${item['size']})',
                  style: DauverseTypography.body(p, size: 13, weight: FontWeight.w700)),
            ),
            DauverseStatusBadge(
              label: st,
              color: st == 'COMPLETED' ? p.success : (st == 'PAUSED' ? p.warning : p.cyan),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: st == 'PAUSED' ? 'Resume' : 'Pause',
              icon: Icon(st == 'PAUSED' ? Icons.play_arrow : Icons.pause, size: 18, color: p.cyan),
              onPressed: st == 'COMPLETED'
                  ? null
                  : () => setState(() {
                        item['status'] = st == 'PAUSED' ? 'ACTIVE' : 'PAUSED';
                      }),
            ),
            IconButton(
              tooltip: 'Retry',
              icon: Icon(Icons.refresh, size: 18, color: p.blue),
              onPressed: () => setState(() => item['status'] = 'ACTIVE'),
            ),
            IconButton(
              tooltip: 'Cancel',
              icon: Icon(Icons.close, size: 18, color: p.danger),
              onPressed: st == 'COMPLETED' ? null : () => setState(() => item['status'] = 'CANCELLED'),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${item['dir']}  •  Speed: ${item['speed']}  •  ETA: ${item['eta']}',
                style: DauverseTypography.caption(p, size: 11)),
            Text('${item['sha256']}  •  Auto-Execute: BLOCKED',
                style: DauverseTypography.kpi(p, size: 11, color: p.success)),
          ],
        ),
      ],
    );
  }
}

class DauverseClipboardSettingsScreen extends StatefulWidget {
  final DauverseController controller;
  const DauverseClipboardSettingsScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<DauverseClipboardSettingsScreen> createState() => _DauverseClipboardSettingsScreenState();
}

class _DauverseClipboardSettingsScreenState extends State<DauverseClipboardSettingsScreen> {
  bool _enabled = true;
  bool _vnUnicode = true;
  bool _images = true;
  bool _files = true;
  bool _richHtml = true;
  String _direction = 'BIDIRECTIONAL';

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    final i18n = widget.controller.i18n;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n.t('Smart Clipboard — Đồng bộ hai chiều an toàn', 'Smart Clipboard — Bidirectional Sync & Loop Guard'),
              style: DauverseTypography.heading(p, size: 19)),
          const SizedBox(height: 4),
          Text(
            i18n.t(
              'Hỗ trợ Tiếng Việt Unicode chuẩn UTF-8, Prompt AI nhiều dòng, Code/JSON/PowerShell/Markdown, Screenshot & File. Không bao giờ ghi log nội dung nhạy cảm.',
              'Full Vietnamese UTF-8, multiline AI prompts, code/JSON/Markdown, screenshots & files. Zero sensitive clipboard logging.',
            ),
            style: DauverseTypography.caption(p),
          ),
          const SizedBox(height: 16),
          DauverseCard(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(i18n.t('Bật đồng bộ Clipboard tự nhiên (Ctrl+C / Ctrl+V)', 'Enable Natural Ctrl+C / Ctrl+V Sync'),
                      style: DauverseTypography.body(p, size: 14, weight: FontWeight.w700)),
                  subtitle: Text(i18n.t('Tự động chặn vòng lặp clipboard (Echo-Loop Suppression SHA-256)',
                      'Automatic SHA-256 echo-loop suppression without logging content')),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const Divider(),
                ListTile(
                  title: Text(i18n.t('Chiều phân quyền theo phiên', 'Session Sync Direction'),
                      style: DauverseTypography.body(p)),
                  trailing: DropdownButton<String>(
                    value: _direction,
                    items: const [
                      DropdownMenuItem(value: 'BIDIRECTIONAL', child: Text('Bidirectional (2 chiều)')),
                      DropdownMenuItem(value: 'CLIENT_TO_HOST', child: Text('Office -> Home Only')),
                      DropdownMenuItem(value: 'HOST_TO_CLIENT', child: Text('Home -> Office Only')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _direction = v);
                    },
                  ),
                ),
                CheckboxListTile(
                  title: const Text('Tiếng Việt Unicode / Prompt AI / Source Code / PowerShell / JSON / Markdown'),
                  value: _vnUnicode,
                  onChanged: (v) => setState(() => _vnUnicode = v ?? true),
                ),
                CheckboxListTile(
                  title: const Text('Rich Text & HTML Formatting'),
                  value: _richHtml,
                  onChanged: (v) => setState(() => _richHtml = v ?? true),
                ),
                CheckboxListTile(
                  title: const Text('Hình ảnh & Screenshot (Max 64 MiB)'),
                  value: _images,
                  onChanged: (v) => setState(() => _images = v ?? true),
                ),
                CheckboxListTile(
                  title: const Text('Copy/Paste File & Nhiều File (Chống Path Traversal)'),
                  value: _files,
                  onChanged: (v) => setState(() => _files = v ?? true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
