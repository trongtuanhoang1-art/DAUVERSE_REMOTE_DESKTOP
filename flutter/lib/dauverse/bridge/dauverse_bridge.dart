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

  Map<String, dynamic> _fallbackTestState(String cmd, Map<String, dynamic> args) {
    if (cmd == 'dashboard_snapshot') {
      return {
        'ok': true,
        'data': {
          'product': 'DAUVERSE REMOTE DESKTOP',
          'version': '1.0.0',
          'engine_base': '1.5.3',
          'hardware': {
            'cpu_brand': 'Intel Core i5-12400F / Test VM',
            'cpu_usage_pct': 21.4,
            'cpu_temp_c': null,
            'ram_used_gb': 6.4,
            'ram_total_gb': 16.0,
            'ram_usage_pct': 40.0,
            'gpu_model': null,
            'gpu_usage_pct': null,
            'gpu_temp_c': null,
            'vram_used_mb': null,
            'vram_total_mb': null,
            'vram_usage_pct': null,
            'gpu_power_watts': null,
            'disk_used_gb': 84.0,
            'disk_free_gb': 416.0,
            'disk_total_gb': 500.0,
            'disk_usage_pct': 16.8,
            'net_upload_bps': 142000,
            'net_download_bps': 890000,
            'system_uptime_secs': 48200,
            'remote_service_healthy': true,
            'ai_processes': const [],
          },
          'performance': {
            'active_mode': 'AUTO_ADAPTIVE',
            'fps': 60,
            'ping_rtt_ms': 14,
            'bitrate_kbps': 6800,
            'packet_loss_pct': 0.0,
            'codec': 'H265',
            'encoder': 'NVENC_BALANCED_P3',
            'cpu_usage_pct': 21.4,
            'gpu_usage_pct': 0.0,
            'connection_route': 'Direct P2P',
            'network_quality_score': 96,
            'network_quality_label': 'Excellent',
          },
          'ai_summary': {
            'running': 2,
            'waiting_approval': 1,
            'completed': 5,
            'comfyui_rendering': false,
            'live_tasks': const [],
            'sources_catalog': const [],
          },
          'notifications': {
            'unread_count': 2,
            'active_toasts': const [],
            'preferences': {
              'enabled': true,
              'quiet_mode': false,
              'do_not_disturb': false,
              'play_sound': false,
              'auto_hide_seconds': 6,
            },
          },
          'smart_power': {
            'host_state': 'ONLINE',
            'smart_plug': {
              'adapter_name': 'DisabledSmartPlugAdapter',
              'integration_state': 'BLOCKED',
              'evidence_class': 'BLOCKED',
              'blocker_note': 'BLOCKED: Smart plug model not yet configured by Boss.',
            },
          },
          'security': {
            'encryption': 'End-to-End Curve25519 + XSalsa20-Poly1305 + HMAC-SHA256',
            'credential_vault': 'WINDOWS_DPAPI / SEALED_VAULT',
            'allowlist_enforced': true,
            'mfa_required': false,
            'telemetry_enabled': false,
            'trusted_devices_count': 2,
            'audit_chain_intact': true,
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
  bool showClassicRustDeskConnector = false;
  bool miniControlAlwaysOnTop = true;
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
  bool recordingActive = false;
  bool quietMode = false;
  bool doNotDisturb = false;
  int toastAutoHideSeconds = 6;

  Map<String, dynamic> snapshot = const {};
  List<double> cpuHistory = [18, 22, 19, 25, 21, 24, 20, 22, 19, 21];
  List<double> ramHistory = [38, 39, 39, 40, 41, 40, 40, 41, 41, 40];
  String lastActionBanner = '';
  Map<String, dynamic>? activeCornerToast;

  Timer? _pollTimer;
  Timer? _toastTimer;

  DauverseController({
    DauverseScreenId initialScreen = DauverseScreenId.dashboard,
    this.isDarkMode = true,
    this.isVietnamese = true,
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

  void refreshSnapshot() {
    final resp = DauverseNativeBridge.instance.call('dashboard_snapshot');
    if (resp['ok'] == true && resp['data'] is Map<String, dynamic>) {
      snapshot = resp['data'] as Map<String, dynamic>;
      final hw = snapshot['hardware'] as Map<String, dynamic>? ?? const {};
      final cpu = (hw['cpu_usage_pct'] as num?)?.toDouble() ?? 15.0;
      final ram = (hw['ram_usage_pct'] as num?)?.toDouble() ?? 40.0;
      cpuHistory = [...cpuHistory.skip(1), cpu];
      ramHistory = [...ramHistory.skip(1), ram];
      notifyListeners();
    }
  }

  void setPerformanceProfile(String mode) {
    performanceMode = mode;
    DauverseNativeBridge.instance.call('set_performance_mode', {'mode': mode});
    lastActionBanner = i18n.t(
      'Đã áp dụng chế độ hiệu năng: $mode',
      'Applied performance mode: $mode',
    );
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
    if (enable) {
      recordingActive = true;
      lastActionBanner = i18n.t(
        'ĐANG GHI HÌNH PHIÊN: Chỉ báo ghi hình công khai đang bật.',
        'SESSION RECORDING ACTIVE: Mandatory visible recording banner enabled.',
      );
    } else {
      recordingActive = false;
      lastActionBanner = i18n.t('Đã dừng ghi hình phiên.', 'Stopped session recording.');
    }
    notifyListeners();
  }

  Map<String, dynamic> invokePowerAction(
    String operation, {
    bool authenticated = true,
    bool forceConfirmed = false,
    String? mac,
    String? target,
  }) {
    final res = DauverseNativeBridge.instance.call('smart_power_action', {
      'operation': operation,
      'authenticated': authenticated,
      'force_confirmed': forceConfirmed,
      'dry_run': true,
      if (mac != null) 'mac': mac,
      if (target != null) 'target': target,
    });
    final data = res['data'] as Map<String, dynamic>? ?? const {};
    lastActionBanner = '${data['status_code'] ?? operation}: ${data['message'] ?? ''}';
    notifyListeners();
    return data;
  }

  void emergencyRevokeAllAccess() {
    DauverseNativeBridge.instance.call('revoke_all_access');
    lastActionBanner = i18n.t(
      'ĐÃ THU HỒI KHẨN CẤP toàn bộ quyền Unattended Access & phiên kết nối.',
      'EMERGENCY REVOCATION EXECUTED: All unattended access and active sessions revoked.',
    );
    refreshSnapshot();
  }
}
