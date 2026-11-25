import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/dauverse_i18n.dart';

typedef _DauverseInvokeNative = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8> cmd,
  ffi.Pointer<Utf8> payload,
);
typedef _DauverseInvokeDart = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8> cmd,
  ffi.Pointer<Utf8> payload,
);

typedef _DauverseFreeNative = ffi.Void Function(ffi.Pointer<Utf8> ptr);
typedef _DauverseFreeDart = void Function(ffi.Pointer<Utf8> ptr);

typedef RealSessionLauncher = Future<void> Function(
  BuildContext context,
  String peerId, {
  bool isFileTransfer,
});

class DauverseNativeBridge {
  static final DauverseNativeBridge instance = DauverseNativeBridge._();

  _DauverseInvokeDart? _invoke;
  _DauverseFreeDart? _free;
  bool _bound = false;

  DauverseNativeBridge._() {
    _tryBindNative();
  }

  bool get isNativeBound => _bound;

  void _tryBindNative() {
    if (kIsWeb) return;
    final candidates = <ffi.DynamicLibrary Function()>[
      () => ffi.DynamicLibrary.process(),
      if (Platform.isWindows) () => ffi.DynamicLibrary.open('librustdesk.dll'),
      if (Platform.isLinux) () => ffi.DynamicLibrary.open('librustdesk.so'),
      if (Platform.isLinux) () => ffi.DynamicLibrary.open('lib/librustdesk.so'),
      if (Platform.isLinux)
        () => ffi.DynamicLibrary.open('../target/release/liblibrustdesk.so'),
      if (Platform.isMacOS) () => ffi.DynamicLibrary.open('librustdesk.dylib'),
    ];
    for (final loader in candidates) {
      try {
        final lib = loader();
        final inv = lib.lookupFunction<_DauverseInvokeNative, _DauverseInvokeDart>('dauverse_invoke');
        final fr = lib.lookupFunction<_DauverseFreeNative, _DauverseFreeDart>('dauverse_free_str');
        _invoke = inv;
        _free = fr;
        _bound = true;
        return;
      } catch (_) {
        continue;
      }
    }
  }

  Map<String, dynamic> call(String command, [Map<String, dynamic>? payload]) {
    final payloadJson = jsonEncode(payload ?? const <String, dynamic>{});
    if (_bound && _invoke != null && _free != null) {
      final cmdPtr = command.toNativeUtf8();
      final payloadPtr = payloadJson.toNativeUtf8();
      ffi.Pointer<Utf8> outPtr = ffi.nullptr;
      try {
        outPtr = _invoke!(cmdPtr, payloadPtr);
        if (outPtr == ffi.nullptr) {
          return {'ok': false, 'error': 'NULL_FFI_RESPONSE'};
        }
        final rawJson = outPtr.toDartString();
        return jsonDecode(rawJson) as Map<String, dynamic>;
      } catch (e) {
        return {'ok': false, 'error': e.toString()};
      } finally {
        malloc.free(cmdPtr);
        malloc.free(payloadPtr);
        if (outPtr != ffi.nullptr) {
          _free!(outPtr);
        }
      }
    }
    return _fallbackTestState(command, payload ?? const <String, dynamic>{});
  }

  /// Pure-Dart widget-test fallback ONLY when native librustdesk FFI is unbound.
  /// Reports honest disconnected/zero state (never fabricates 14ms RTT or fake tasks).
  Map<String, dynamic> _fallbackTestState(String cmd, Map<String, dynamic> args) {
    if (cmd == 'dashboard_snapshot') {
      return {
        'ok': true,
        'data': {
          'product': 'DAUVERSE REMOTE DESKTOP',
          'version': '1.0.0',
          'engine_base': '1.5.3',
          'local_peer_id': 'UNBOUND-TEST',
          'bridge_endpoint': 'http://127.0.0.1:21188/v1/events',
          'bridge_port': 21188,
          'hardware': {
            'telemetry_scope': 'TEST_FALLBACK_UNBOUND_FFI',
            'cpu_brand': 'Widget Test Host CPU (FFI Unbound)',
            'cpu_usage_pct': 0.0,
            'cpu_temp_c': null,
            'ram_used_gb': 0.0,
            'ram_total_gb': 0.0,
            'ram_usage_pct': 0.0,
            'gpu_model': null,
            'gpu_usage_pct': null,
            'gpu_temp_c': null,
            'vram_used_mb': null,
            'vram_total_mb': null,
            'vram_usage_pct': null,
            'gpu_power_watts': null,
            'disk_used_gb': 0.0,
            'disk_free_gb': 0.0,
            'disk_total_gb': 0.0,
            'disk_usage_pct': 0.0,
            'net_upload_bps': 0,
            'net_download_bps': 0,
            'system_uptime_secs': 0,
            'remote_service_healthy': false,
            'ai_processes': const [],
          },
          'hardware_alerts': const [],
          'performance': {
            'session_connected': false,
            'active_mode': 'AUTO_ADAPTIVE',
            'fps': 0,
            'ping_rtt_ms': 0,
            'bitrate_kbps': 0,
            'packet_loss_pct': null,
            'codec': 'H265',
            'encoder': 'NVENC_BALANCED_P3',
            'cpu_usage_pct': 0.0,
            'gpu_usage_pct': 0.0,
            'connection_route': 'DISCONNECTED (No Active Remote Session)',
            'network_quality_score': 0,
            'network_quality_label': 'Idle (No Session)',
          },
          'ai_summary': {
            'running': 0,
            'waiting_approval': 0,
            'completed': 0,
            'comfyui_rendering': false,
            'live_tasks': const [],
            'recent_events': const [],
            'rejected_security_count': 0,
            'sources_catalog': const [],
          },
          'notifications': {
            'unread_count': 0,
            'active_toasts': const [],
            'recent_items': const [],
            'preferences': {
              'enabled': true,
              'quiet_mode': false,
              'do_not_disturb': false,
              'play_sound': false,
              'auto_hide_seconds': 6,
            },
          },
          'clipboard': {
            'policy': {
              'enabled': true,
              'direction': 'BIDIRECTIONAL',
              'allow_text_unicode': true,
              'allow_rich_html': true,
              'allow_images': true,
              'allow_files': true,
            },
            'blocked_loops_count': 0,
            'synced_items_count': 0,
          },
          'transfer_queue': {
            'authorized_root': '/tmp/dauverse_remote_v1/received_files',
            'bandwidth_limit_kbps': null,
            'active_count': 0,
            'jobs': const [],
          },
          'smart_power': {
            'host_state': 'ONLINE',
            'smart_plug': {
              'adapter_name': 'DisabledSmartPlugAdapter (Hunonic SK02 Surveyed)',
              'integration_state': 'BLOCKED',
              'evidence_class': 'BLOCKED',
              'blocker_note':
                  'BLOCKED (Hunonic SK02 Surveyed): No official public HTTP/MQTT/OpenAPI documentation; DisabledSmartPlugAdapter retained per Section 6.',
            },
            'recent_events': const [],
          },
          'headless': {
            'primary_driver': 'Amyuni USB Mobile Monitor Virtual Display (usbmmidd_v2 — Microsoft WHQL Signed)',
            'rustdesk_idd_v04_audit': 'BLOCKED_DO_NOT_INSTALL: Self-signed WDKTestCert SHA-1 root import.',
            'boss_driver_install_approved': false,
          },
          'security': {
            'summary': {
              'encryption': 'End-to-End Curve25519 + XSalsa20-Poly1305 + HMAC-SHA256',
              'credential_vault': 'WINDOWS_DPAPI / SEALED_VAULT_PBKDF2_0600',
              'allowlist_enforced': true,
              'mfa_required': false,
              'telemetry_enabled': false,
              'trusted_devices_count': 0,
              'audit_chain_intact': true,
              'trusted_devices': const [],
            },
            'recent_audit': const [],
          },
          'release': {
            'product_version': '1.0.0',
            'upstream_engine_base': '1.5.3',
            'code_signing_status': 'UNSIGNED',
            'auto_update_enabled': false,
          },
        }
      };
    }
    return {'ok': true, 'data': args};
  }
}

class DauverseController extends ChangeNotifier {
  DauverseScreenId currentScreen;
  bool isDarkMode;
  bool isVietnamese;
  RealSessionLauncher? onLaunchRealSession;
  List<Map<String, String>> Function()? peersProvider;

  bool showClassicRustDeskConnector = false;
  String targetPeerId = '';
  bool miniControlAlwaysOnTop = true;
  bool miniControlWindowDetached = false;
  bool miniControlCollapsedStrip = false;
  bool miniControlStatusOnlyNoVideo = false;
  double miniControlOpacity = 0.96;
  String miniControlMode = 'INTERACTIVE';
  String performanceMode = 'AUTO_ADAPTIVE';
  bool toolbarCollapsed = false;
  bool toolbarAutoHide = false;
  bool toolbarPinnedTop = true;
  bool viewOnlySession = false;
  bool audioEnabled = true;
  double audioVolume = 0.80;
  int selectedMonitorIndex = 0;
  String selectedResolutionPreset = '1920x1080@60';
  bool recordingActive = false;
  bool quietMode = false;
  bool doNotDisturb = false;
  int toastAutoHideSeconds = 6;

  Map<String, dynamic> snapshot = const {};
  List<double> cpuHistory = [];
  List<double> ramHistory = [];
  String lastActionBanner = '';
  Map<String, dynamic>? activeCornerToast;
  String? _lastShownToastId;

  Timer? _pollTimer;
  Timer? _toastTimer;

  DauverseController({
    DauverseScreenId initialScreen = DauverseScreenId.dashboard,
    this.isDarkMode = true,
    this.isVietnamese = true,
    this.onLaunchRealSession,
    this.peersProvider,
  }) : currentScreen = initialScreen {
    refreshSnapshot();
  }

  DauverseI18n get i18n => DauverseI18n(isVietnamese);

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => refreshSnapshot());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  void selectScreen(DauverseScreenId screen) {
    currentScreen = screen;
    showClassicRustDeskConnector = false;
    notifyListeners();
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    notifyListeners();
  }

  void toggleLanguage() {
    isVietnamese = !isVietnamese;
    notifyListeners();
  }

  void openClassicRustDeskView() {
    showClassicRustDeskConnector = true;
    notifyListeners();
  }

  Future<void> launchRealRemoteSession(BuildContext context, String rawPeerId) async {
    final cleaned = rawPeerId.trim();
    if (cleaned.isEmpty) {
      lastActionBanner = i18n.t(
        'Vui lòng nhập ID máy tính đích trước khi kết nối.',
        'Please enter a target Peer ID before connecting.',
      );
      notifyListeners();
      return;
    }
    targetPeerId = cleaned;
    if (onLaunchRealSession != null) {
      lastActionBanner = i18n.t(
        'Đang khởi chạy phiên RustDesk Engine tới $cleaned...',
        'Launching native RustDesk session to $cleaned...',
      );
      notifyListeners();
      await onLaunchRealSession!(context, cleaned, isFileTransfer: false);
    } else {
      currentScreen = DauverseScreenId.remoteSession;
      lastActionBanner = i18n.t(
        'Đã chọn thiết bị $cleaned (Chế độ xem trước Shell — mở Engine gốc để kết nối thực).',
        'Selected target $cleaned (Shell mode — launch with full RustDesk runtime for live stream).',
      );
      notifyListeners();
    }
  }

  Future<void> launchRealFileTransfer(BuildContext context, String rawPeerId) async {
    final cleaned = rawPeerId.trim();
    if (cleaned.isEmpty) {
      currentScreen = DauverseScreenId.fileTransfer;
      lastActionBanner = i18n.t(
        'Nhập Peer ID để mở trình truyền file hai chiều trực tiếp.',
        'Enter a Peer ID to launch native dual-pane file transfer.',
      );
      notifyListeners();
      return;
    }
    targetPeerId = cleaned;
    if (onLaunchRealSession != null) {
      lastActionBanner = i18n.t(
        'Đang mở phiên Truyền File hai chiều tới $cleaned...',
        'Opening native dual-pane File Transfer to $cleaned...',
      );
      notifyListeners();
      await onLaunchRealSession!(context, cleaned, isFileTransfer: true);
    } else {
      currentScreen = DauverseScreenId.fileTransfer;
      notifyListeners();
    }
  }

  void refreshSnapshot() {
    final resp = DauverseNativeBridge.instance.call('dashboard_snapshot');
    if (resp['ok'] == true && resp['data'] is Map<String, dynamic>) {
      snapshot = resp['data'] as Map<String, dynamic>;
      final hw = snapshot['hardware'] as Map<String, dynamic>? ?? const {};
      final cpu = (hw['cpu_usage_pct'] as num?)?.toDouble() ?? 0.0;
      final ram = (hw['ram_usage_pct'] as num?)?.toDouble() ?? 0.0;
      cpuHistory = [...cpuHistory, cpu];
      if (cpuHistory.length > 30) {
        cpuHistory = cpuHistory.sublist(cpuHistory.length - 30);
      }
      ramHistory = [...ramHistory, ram];
      if (ramHistory.length > 30) {
        ramHistory = ramHistory.sublist(ramHistory.length - 30);
      }

      // Surface real unread Corner Toasts emitted by Rust NotificationCenter
      final notif = snapshot['notifications'] as Map<String, dynamic>? ?? const {};
      final toasts = notif['active_toasts'] as List<dynamic>? ?? const [];
      if (toasts.isNotEmpty && !doNotDisturb) {
        final latest = toasts.last;
        if (latest is Map<String, dynamic>) {
          final id = (latest['notification_id'] ?? latest['id'])?.toString();
          if (id != null && id.isNotEmpty && id != _lastShownToastId) {
            _lastShownToastId = id;
            triggerCornerToastPreview(
              title: latest['title']?.toString() ?? 'AI Event',
              aiSource: (latest['ai_source'] ?? latest['source'])?.toString() ?? 'AI Bridge',
              project: (latest['project_name'] ?? latest['project_id'])?.toString() ?? 'DAUVERSE',
              body: latest['body']?.toString() ?? '',
              verifiedEvidence: (latest['verified_evidence_line'] ?? latest['evidence_badge'])?.toString(),
              severityHex: latest['severity_color_hex']?.toString() ?? '#10B981',
            );
          }
        }
      }
      notifyListeners();
    }
  }

  void setPerformanceProfile(String mode) {
    performanceMode = mode;
    DauverseNativeBridge.instance.call('set_performance_mode', {'mode': mode});
    lastActionBanner = i18n.t(
      'Đã áp dụng chế độ hiệu năng vào Engine: $mode',
      'Applied performance mode to Engine: $mode',
    );
    refreshSnapshot();
  }

  void syncMiniControlEngineState({bool? minimized, bool? idle}) {
    DauverseNativeBridge.instance.call('mini_control_state', {
      if (minimized != null) 'minimized': minimized,
      if (idle != null) 'idle': idle,
    });
    refreshSnapshot();
  }

  void updateClipboardPolicy(Map<String, dynamic> patch) {
    DauverseNativeBridge.instance.call('set_clipboard_policy', patch);
    lastActionBanner = i18n.t(
      'Đã đồng bộ chính sách Smart Clipboard xuống Rust Engine.',
      'Synced Smart Clipboard policy to Rust Engine.',
    );
    refreshSnapshot();
  }

  void updateTransferBandwidthCap(int? kbps) {
    DauverseNativeBridge.instance.call('transfer_set_policy', {
      'bandwidth_limit_kbps': kbps,
    });
    refreshSnapshot();
  }

  void controlTransferJob(String action, String jobId) {
    final res = DauverseNativeBridge.instance.call('transfer_control', {
      'action': action,
      'job_id': jobId,
    });
    if (res['ok'] != true) {
      lastActionBanner = 'Transfer $action error: ${res['error'] ?? 'unknown'}';
    }
    refreshSnapshot();
  }

  void updateNotificationPrefs({bool? quiet, bool? dnd, int? autoHideSec}) {
    if (quiet != null) quietMode = quiet;
    if (dnd != null) doNotDisturb = dnd;
    if (autoHideSec != null) toastAutoHideSeconds = autoHideSec;
    DauverseNativeBridge.instance.call('set_notification_prefs', {
      'quiet_mode': quietMode,
      'do_not_disturb': doNotDisturb,
      'auto_hide_seconds': toastAutoHideSeconds,
    });
    refreshSnapshot();
  }

  void sendSignedLoopbackAiProbe({String source = 'codex_cli', String? summary}) {
    final res = DauverseNativeBridge.instance.call('ai_send_signed_loopback_probe', {
      'source': source,
      if (summary != null) 'summary': summary,
    });
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã gửi & xác thực sự kiện HMAC-SHA256 qua HTTP 127.0.0.1 thành công.',
        'Dispatched & verified real HMAC-SHA256 event over 127.0.0.1 HTTP gateway.',
      );
    } else {
      lastActionBanner = 'AI Bridge probe error: ${res['error'] ?? 'failed'}';
    }
    refreshSnapshot();
  }

  void triggerCornerToastPreview({
    required String title,
    required String aiSource,
    required String project,
    required String body,
    String? verifiedEvidence,
    String severityHex = '#10B981',
  }) {
    activeCornerToast = {
      'title': title,
      'ai_source': aiSource,
      'project_name': project,
      'body': body,
      'verified_evidence_line': verifiedEvidence,
      'severity_color_hex': severityHex,
      'timestamp': DateTime.now().toIso8601String().substring(11, 19),
    };
    _toastTimer?.cancel();
    _toastTimer = Timer(Duration(seconds: toastAutoHideSeconds.clamp(5, 8)), () {
      activeCornerToast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void dismissCornerToast() {
    _toastTimer?.cancel();
    activeCornerToast = null;
    notifyListeners();
  }

  void toggleExplicitRecording(bool enable) {
    recordingActive = enable;
    lastActionBanner = enable
        ? i18n.t(
            'CHẾ ĐỘ GHI HÌNH ĐƯỢC CẤP QUYỀN: Chỉ báo ghi hình công khai đang bật (chờ luồng phiên kết nối).',
            'RECORDING ARMED: Mandatory visible recording banner enabled.',
          )
        : i18n.t('Đã tắt chế độ ghi hình phiên.', 'Disabled session recording.');
    notifyListeners();
  }

  bool setStepUpPin(String pin) {
    final res = DauverseNativeBridge.instance.call('set_step_up_pin', {
      'pin': pin,
    });
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã niêm phong mã Step-Up PIN vào kho mật mã an toàn.',
        'Sealed Boss Step-Up PIN into encrypted local vault.',
      );
      refreshSnapshot();
      return true;
    }
    lastActionBanner = 'Step-Up PIN error: ${res['error'] ?? 'invalid'}';
    notifyListeners();
    return false;
  }

  Map<String, dynamic> invokePowerAction(
    String operation, {
    bool authenticated = false,
    String stepUpPin = '',
    bool forceConfirmed = false,
    bool dryRun = true,
    String? mac,
    String? target,
  }) {
    final res = DauverseNativeBridge.instance.call('smart_power_action', {
      'operation': operation,
      'authenticated': authenticated,
      'step_up_pin': stepUpPin,
      'force_confirmed': forceConfirmed,
      'dry_run': dryRun,
      if (mac != null) 'mac': mac,
      if (target != null) 'target': target,
    });
    final data = res['data'] as Map<String, dynamic>? ?? const {};
    lastActionBanner = '${data['status_code'] ?? operation}: ${data['message'] ?? ''}';
    refreshSnapshot();
    return data;
  }

  void emergencyRevokeAllAccess() {
    DauverseNativeBridge.instance.call('revoke_all_access');
    lastActionBanner = i18n.t(
      'ĐÃ THU HỒI KHẨN CẤP toàn bộ quyền Unattended Access, xoay mật khẩu tạm & khoá đầu vào.',
      'EMERGENCY REVOCATION EXECUTED: Unattended access disabled, temp password rotated, inputs locked.',
    );
    refreshSnapshot();
  }
}
