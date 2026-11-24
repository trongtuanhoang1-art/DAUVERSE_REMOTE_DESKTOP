import 'package:flutter/material.dart';
import '../bridge/dauverse_bridge.dart';
import '../l10n/dauverse_i18n.dart';
import '../theme/dauverse_theme.dart';

class DauverseCornerToastOverlay extends StatelessWidget {
  final DauverseController controller;
  const DauverseCornerToastOverlay({Key? key, required this.controller}) : super(key: key);

  Color _parseHexColor(String hex, Color fallback) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final v = int.tryParse('FF$cleaned', radix: 16);
      if (v != null) return Color(v);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final toast = controller.activeCornerToast;
    if (toast == null || controller.doNotDisturb) {
      return const SizedBox.shrink();
    }
    final p = DauversePalette.of(context);
    final i18n = controller.i18n;
    final accent = _parseHexColor(toast['severity_color_hex']?.toString() ?? '', p.success);
    final verifiedEvidence = toast['verified_evidence_line'] as String?;

    return Positioned(
      right: 20,
      bottom: 20,
      child: FocusScope(
        canRequestFocus: false,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 390,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.sidebarBg.withOpacity(0.97),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    DauverseStatusBadge(
                      label: toast['ai_source']?.toString() ?? 'AI',
                      color: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${toast['project_name'] ?? ''} • ${toast['timestamp'] ?? ''}',
                        style: DauverseTypography.caption(p, size: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      canRequestFocus: false,
                      onTap: controller.dismissCornerToast,
                      child: Icon(Icons.close, size: 16, color: p.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  toast['title']?.toString() ?? '',
                  style: DauverseTypography.heading(p, size: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  toast['body']?.toString() ?? '',
                  style: DauverseTypography.body(p, size: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (verifiedEvidence != null && verifiedEvidence.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: p.success.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$verifiedEvidence (VERIFIED EVIDENCE)',
                      style: DauverseTypography.kpi(p, size: 11, color: p.success),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _actionChip(p, i18n.t('Mở Remote', 'Open Remote'), p.cyan, () {
                      controller.dismissCornerToast();
                      controller.selectScreen(DauverseScreenId.remoteSession);
                    }),
                    _actionChip(p, i18n.t('Xem trạng thái', 'View Status'), p.blue, () {
                      controller.dismissCornerToast();
                      controller.selectScreen(DauverseScreenId.aiLiveStatus);
                    }),
                    _actionChip(p, i18n.t('Xem báo cáo', 'View Report'), p.purple, () {
                      controller.dismissCornerToast();
                      controller.selectScreen(DauverseScreenId.notificationCenter);
                    }),
                    _actionChip(p, i18n.t('Đánh dấu đã đọc', 'Mark Read'), p.textSecondary, () {
                      DauverseNativeBridge.instance.call('notification_mark_read', {});
                      controller.dismissCornerToast();
                      controller.refreshSnapshot();
                    }),
                    _actionChip(p, i18n.t('Đóng', 'Close'), p.textSecondary, controller.dismissCornerToast),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionChip(DauversePalette p, String label, Color color, VoidCallback onTap) {
    return InkWell(
      canRequestFocus: false,
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: DauverseTypography.body(p, size: 11, weight: FontWeight.w600),
        ),
      ),
    );
  }
}
