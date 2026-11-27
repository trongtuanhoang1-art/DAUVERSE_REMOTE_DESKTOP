import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/dauverse_i18n.dart';

const String kDauverseProductVersion = '1.0.0-rc4.3';
const String kDauverseReleaseCandidate = 'RC4.3';
const String kDauverseDisplayVersion = 'V1.0 RC4.3';
const String kDauverseEngineVersion = '1.5.3';

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

  static const bool isReleaseBuild = bool.fromEnvironment('dart.vm.product');

  static bool _testHarnessMode = false;
  static bool _forceUnboundForTest = false;
  static Map<String, dynamic>? _testHarnessIdentityOverride;

  @visibleForTesting
  static void setTestHarnessMode(bool enabled) {
    if (isReleaseBuild) {
      throw UnsupportedError(
        'SECURITY_DENY_RELEASE_TEST_HARNESS: Test harness mode is compiled out of release builds.',
      );
    }
    assert(() {
      _testHarnessMode = enabled;
      if (!enabled) {
        _testHarnessIdentityOverride = null;
      }
      return true;
    }());
  }

  @visibleForTesting
  static void setTestHarnessIdentityOverride(Map<String, dynamic>? overrideMap) {
    if (isReleaseBuild) {
      throw UnsupportedError(
        'SECURITY_DENY_RELEASE_TEST_HARNESS: Test harness override is compiled out of release builds.',
      );
    }
    assert(() {
      _testHarnessIdentityOverride = overrideMap;
      return true;
    }());
  }

  @visibleForTesting
  static void setForceUnboundForTest(bool forceUnbound) {
    if (isReleaseBuild) {
      throw UnsupportedError(
        'SECURITY_DENY_RELEASE_TEST_HARNESS: Force-unbound test hook is compiled out of release builds.',
      );
    }
    assert(() {
      _forceUnboundForTest = forceUnbound;
      return true;
    }());
  }

  @visibleForTesting
  static void assertReleaseIsolationPolicy({required bool simulatedReleaseFlag}) {
    if (simulatedReleaseFlag) {
      throw UnsupportedError(
        'SECURITY_DENY_RELEASE_TEST_HARNESS: Test harness mode is compiled out of release builds.',
      );
    }
  }

  _DauverseInvokeDart? _invoke;
  _DauverseFreeDart? _free;
  bool _bound = false;

  DauverseNativeBridge._() {
    _tryBindNative();
  }

  bool get isNativeBound {
    if (isReleaseBuild) {
      return _bound;
    }
    var forcedUnbound = false;
    assert(() {
      forcedUnbound = _forceUnboundForTest;
      return true;
    }());
    return _bound && !forcedUnbound;
  }

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
    if (isNativeBound && _invoke != null && _free != null) {
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

    if (!isReleaseBuild) {
      Map<String, dynamic>? harnessResult;
      assert(() {
        if (_testHarnessMode) {
          harnessResult = _widgetTestHarnessOnlyState(
            command,
            payload ?? const <String, dynamic>{},
          );
        }
        return true;
      }());
      if (harnessResult != null) {
        return harnessResult!;
      }
    }

    return {
      'ok': false,
      'backend_available': false,
      'error':
          'NATIVE_FFI_UNBOUND_FAIL_CLOSED: librustdesk native backend is unavailable; refused "$command".',
    };
  }

  static String _harnessTempPw = 'dv9x4k2p';
  static String _harnessPerfMode = 'AUTO_ADAPTIVE';
  static String _harnessGfxMode = 'PIXEL_BUFFER_SAFE';

  Map<String, dynamic> _widgetTestHarnessOnlyState(String cmd, Map<String, dynamic> args) {
    final baseIdentity = <String, dynamic>{
      'connection_id': 'UNBOUND-TEST',
      'formatted_id': 'UNBOUND-TEST',
      'temporary_password': _harnessTempPw,
      'permanent_password_configured': false,
      'lan_interfaces': const <Map<String, dynamic>>[],
      'lan_ips': const <String>[],
      'public_ip': null,
      'public_ip_status': 'OPT_IN_NOT_QUERIED',
      'direct_ip_access_enabled': false,
      'direct_ip_port': 21118,
      'rendezvous_server': '',
      'using_public_rendezvous': true,
      'service_stopped': false,
      'active_sessions_count': 0,
      'online_state_code': 1,
      'connection_status': 'ONLINE',
      if (_testHarnessIdentityOverride != null) ..._testHarnessIdentityOverride!,
    };

    if (cmd == 'dashboard_snapshot') {
      return {
        'ok': true,
        'data': {
          'product': 'DAUVERSE REMOTE DESKTOP',
          'version': kDauverseProductVersion,
          'release_candidate': kDauverseReleaseCandidate,
          'display_version': kDauverseDisplayVersion,
          'engine_base': kDauverseEngineVersion,
          'local_peer_id': baseIdentity['connection_id'],
          'connection_identity': baseIdentity,
          'graphics_fallback_mode': _harnessGfxMode,
          'ui_preferences': {
            'dark_mode': true,
            'vietnamese': true,
            'transfer_overwrite_policy': 'REQUIRE_CONFIRMATION',
          },
          'bridge_endpoint': 'http://127.0.0.1:21188/v1/events',
          'bridge_port': 21188,
          'hardware': {
            'telemetry_scope': 'WIDGET_TEST_HARNESS_ONLY',
            'cpu_brand': 'Widget Test Host CPU (Test Harness)',
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
            'active_mode': _harnessPerfMode,
            'measured_fps': null,
            'measured_bitrate_kbps': null,
            'configured_target_fps': 60,
            'estimated_bitrate_cap_kbps': 8000,
            'telemetry_source_scope': 'DISCONNECTED_NO_ACTIVE_STREAM',
            'ping_rtt_ms': 0,
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
            'overwrite_policy': 'REQUIRE_CONFIRMATION',
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
            'operational_status': 'CONFIGURED',
            'virtual_display_active': false,
            'primary_driver': 'Amyuni USB Mobile Monitor Virtual Display (usbmmidd_v2 — Microsoft WHQL Signed)',
            'rustdesk_idd_v04_audit': 'BLOCKED_DO_NOT_INSTALL: Self-signed WDKTestCert SHA-1 root import.',
            'boss_driver_install_approved': false,
          },
          'service': {
            'scm_service_name': 'RustDesk',
            'service_state': 'NOT_INSTALLED_PORTABLE_MODE',
            'external_service_collision_detected': false,
            'auto_start_with_windows': false,
            'unattended_access_enabled': false,
          },
          'host_capabilities': {
            'conservative_deny_latched': false,
            'stop_service': false,
            'approve_mode': 'password_and_click',
            'direct_ip_access_enabled': false,
            'enable_keyboard': true,
            'enable_clipboard': true,
            'enable_file_transfer': true,
            'enable_audio': true,
            'enable_tunnel': true,
            'enable_remote_restart': true,
            'enable_record_session': false,
          },
          'windows_access_readiness': {
            'readiness_code': 'PORTABLE_OR_USER_SESSION_ONLY',
            'windows_password_preserved': true,
            'windows_auto_login_disabled': true,
            'owned_service_installed': false,
            'owned_service_running': false,
            'external_rustdesk_collision': false,
            'pre_login_winlogon_ready': false,
            'lock_screen_uac_ready': false,
            'auto_start_user_logon': false,
            'unattended_access_enabled': false,
            'permanent_password_set': false,
            'service_state': 'NOT_INSTALLED_PORTABLE_MODE',
          },
          'session_tools': {
            'recording': {
              'active': false,
              'visible_banner_indicator': false,
            },
            'history': const [],
            'shortcuts': const {
              'toggle_fullscreen': 'Ctrl+Alt+Enter',
              'toggle_mini_control': 'Ctrl+Alt+M',
              'open_file_transfer': 'Ctrl+Alt+F',
            },
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
              'step_up_pin_configured': false,
              'trusted_devices': const [],
            },
            'recent_audit': const [],
          },
          'release': {
            'product_version': kDauverseProductVersion,
            'release_candidate': kDauverseReleaseCandidate,
            'display_version': kDauverseDisplayVersion,
            'upstream_engine_base': kDauverseEngineVersion,
            'code_signing_status': 'UNSIGNED',
            'auto_update_enabled': false,
            'rollback_supported': true,
          },
        }
      };
    }
    if (cmd == 'regenerate_temporary_password') {
      _harnessTempPw = _harnessTempPw == 'dv9x4k2p' ? 'mk7r3w8q' : 'dv9x4k2p';
      return {
        'ok': true,
        'data': {...baseIdentity, 'temporary_password': _harnessTempPw},
      };
    }
    if (cmd == 'set_performance_mode') {
      _harnessPerfMode = args['mode']?.toString() ?? 'AUTO_ADAPTIVE';
      return {'ok': true, 'data': {'mode': _harnessPerfMode}};
    }
    if (cmd == 'set_graphics_fallback_mode') {
      _harnessGfxMode = args['mode']?.toString() ?? 'PIXEL_BUFFER_SAFE';
      return {'ok': true, 'data': {'graphics_fallback_mode': _harnessGfxMode}};
    }
    if (cmd == 'network_probe') {
      return {
        'ok': true,
        'data': {'target': args['target'] ?? '127.0.0.1:21116', 'reachable': false, 'latency_ms': 0, 'detail': 'harness'},
      };
    }
    if (cmd == 'run_benchmark') {
      return {
        'ok': true,
        'data': {'scope': 'LOCAL_HARNESS_BENCHMARK', 'tile_scan_ms': 1.2, 'hmac_sign_us': 18},
      };
    }
    if (cmd == 'export_diagnostics') {
      return {
        'ok': true,
        'data': '{"product":"DAUVERSE REMOTE DESKTOP","version":"1.0.0-rc4.3","secrets_redacted":true}',
      };
    }
    if (cmd == 'verify_update_package') {
      return {
        'ok': true,
        'data': {
          'safe_for_auto_update': false,
          'safe_for_manual_owner_install': false,
          'status_code': 'ARTIFACT_NOT_FOUND',
          'computed_sha256': null,
          'signature_status': 'UNSIGNED_BUILD',
          'reason': 'Widget test harness check',
        },
      };
    }
    if (cmd == 'notification_mark_read' ||
        cmd == 'mini_control_state' ||
        cmd == 'set_ui_preferences' ||
        cmd == 'set_transfer_overwrite_policy' ||
        cmd == 'record_session_history' ||
        cmd == 'session_recording_control' ||
        cmd == 'set_shortcut') {
      return {'ok': true, 'simulated_test_harness': true, 'data': args};
    }
    return {
      'ok': false,
      'error': 'TEST_HARNESS_UNEXECUTED_COMMAND: "$cmd" requires bound native librustdesk.',
    };
  }
}

class DauverseController extends ChangeNotifier {
  DauverseScreenId currentScreen;
  bool isDarkMode;
  bool isVietnamese;
  bool sidebarCollapsed = false;
  RealSessionLauncher? onLaunchRealSession;
  List<Map<String, String>> Function()? peersProvider;
  void Function(bool isDark)? onSyncThemeExternal;
  void Function(bool isVi)? onSyncLanguageExternal;

  bool showClassicRustDeskConnector = false;
  String targetPeerId = '';
  bool miniControlAlwaysOnTop = true;
  bool miniControlWindowDetached = false;
  bool miniControlCollapsedStrip = false;
  bool miniControlStatusOnlyNoVideo = false;
  double miniControlOpacity = 0.96;
  String miniControlMode = 'INTERACTIVE';
  String performanceMode = 'AUTO_ADAPTIVE';
  String graphicsFallbackMode = 'PIXEL_BUFFER_SAFE';
  String transferOverwritePolicy = 'REQUIRE_CONFIRMATION';
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

  bool isBusy = false;
  String lastCopiedKey = '';
  String lastCopiedNotice = '';

  Map<String, dynamic> snapshot = const {};
  bool backendAvailable = true;
  String backendError = '';
  List<double> cpuHistory = [];
  List<double> ramHistory = [];
  String lastActionBanner = '';
  Map<String, dynamic>? activeCornerToast;
  String? _lastShownToastId;
  bool _hydratedPrefsOnce = false;

  Timer? _pollTimer;
  Timer? _toastTimer;
  Timer? _copiedNoticeTimer;

  DauverseController({
    DauverseScreenId initialScreen = DauverseScreenId.dashboard,
    this.isDarkMode = true,
    this.isVietnamese = true,
    this.onLaunchRealSession,
    this.peersProvider,
    this.onSyncThemeExternal,
    this.onSyncLanguageExternal,
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
    _copiedNoticeTimer?.cancel();
    super.dispose();
  }

  static String normalizePeerTarget(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    // Strip internal grouping spaces on numeric IDs (e.g. "123 456 789" -> "123456789")
    if (RegExp(r'^[\d\s]+$').hasMatch(trimmed)) {
      return trimmed.replaceAll(RegExp(r'\s+'), '');
    }
    return trimmed.replaceAll(RegExp(r'\s+'), '');
  }

  void selectScreen(DauverseScreenId screen) {
    currentScreen = screen;
    showClassicRustDeskConnector = false;
    notifyListeners();
  }

  void toggleSidebar() {
    sidebarCollapsed = !sidebarCollapsed;
    notifyListeners();
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    DauverseNativeBridge.instance.call('set_ui_preferences', {
      'dark_mode': isDarkMode,
    });
    onSyncThemeExternal?.call(isDarkMode);
    notifyListeners();
  }

  void toggleLanguage() {
    isVietnamese = !isVietnamese;
    DauverseNativeBridge.instance.call('set_ui_preferences', {
      'vietnamese': isVietnamese,
    });
    onSyncLanguageExternal?.call(isVietnamese);
    notifyListeners();
  }

  void openClassicRustDeskView() {
    showClassicRustDeskConnector = true;
    notifyListeners();
  }

  Future<void> copyToClipboardWithFeedback(
    BuildContext context,
    String value, {
    String? keyTag,
    String? displayLabel,
  }) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: cleaned));
    lastCopiedKey = keyTag ?? cleaned;
    lastCopiedNotice = i18n.t('Đã sao chép', 'Đã sao chép (Copied)');
    lastActionBanner = displayLabel != null
        ? '${i18n.t("Đã sao chép", "Copied")} $displayLabel'
        : i18n.t('Đã sao chép', 'Copied');
    _copiedNoticeTimer?.cancel();
    _copiedNoticeTimer = Timer(const Duration(milliseconds: 2400), () {
      lastCopiedKey = '';
      lastCopiedNotice = '';
      notifyListeners();
    });
    notifyListeners();
    if (context.mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1800),
          width: 300,
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  displayLabel != null
                      ? 'Đã sao chép • $displayLabel'
                      : 'Đã sao chép',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<String> pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final txt = data?.text?.trim() ?? '';
      if (txt.isNotEmpty) {
        targetPeerId = normalizePeerTarget(txt);
        lastActionBanner = i18n.t(
          'Đã dán từ Clipboard: $txt',
          'Pasted from Clipboard: $txt',
        );
        notifyListeners();
      }
      return txt;
    } catch (_) {
      return '';
    }
  }

  bool regenerateTemporaryPassword() {
    final res = DauverseNativeBridge.instance.call('regenerate_temporary_password');
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã tạo mật khẩu tạm thời mới thành công.',
        'Regenerated temporary password.',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'FAIL-CLOSED: ${res['error'] ?? 'Backend unavailable'}';
    notifyListeners();
    return false;
  }

  Future<void> probePublicIpOptIn() async {
    isBusy = true;
    notifyListeners();
    try {
      final res = DauverseNativeBridge.instance.call('probe_public_ip');
      if (res['ok'] == true) {
        final ip = (res['data'] as Map<String, dynamic>?)?['public_ip']?.toString() ?? '';
        lastActionBanner = i18n.t(
          'Đã xác định địa chỉ IP Public thực tế: $ip',
          'Resolved live Public IP: $ip',
        );
      } else {
        lastActionBanner = i18n.t(
          'Không thể truy vấn IP Public bên ngoài (${res['error'] ?? 'offline'}). Vẫn kết nối bình thường qua ID / LAN.',
          'External Public IP query unavailable (${res['error'] ?? 'offline'}). ID / LAN connection unaffected.',
        );
      }
      refreshSnapshot(preserveActionBanner: true);
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> launchRealRemoteSession(BuildContext context, String rawPeerId) async {
    final cleaned = normalizePeerTarget(rawPeerId);
    if (cleaned.isEmpty) {
      lastActionBanner = i18n.t(
        'Vui lòng nhập ID hoặc địa chỉ IP máy tính đích trước khi kết nối.',
        'Please enter a target Peer ID or IP address before connecting.',
      );
      notifyListeners();
      return;
    }
    targetPeerId = cleaned;
    DauverseNativeBridge.instance.call('record_session_history', {
      'peer_id': cleaned,
      'peer_name': cleaned,
      'route': 'OUTGOING_REMOTE_CONTROL',
    });
    if (onLaunchRealSession != null) {
      lastActionBanner = i18n.t(
        'Đang kết nối điều khiển từ xa tới $cleaned...',
        'Connecting remote desktop session to $cleaned...',
      );
      notifyListeners();
      await onLaunchRealSession!(context, cleaned, isFileTransfer: false);
    } else {
      currentScreen = DauverseScreenId.remoteSession;
      lastActionBanner = i18n.t(
        'Đã chọn thiết bị $cleaned (Chế độ xem trước — khởi chạy từ ứng dụng chính để mở luồng hình ảnh).',
        'Selected target $cleaned (Preview shell — launch full runtime for live video stream).',
      );
      notifyListeners();
    }
  }

  Future<void> launchRealFileTransfer(BuildContext context, String rawPeerId) async {
    final cleaned = normalizePeerTarget(rawPeerId);
    if (cleaned.isEmpty) {
      currentScreen = DauverseScreenId.fileTransfer;
      lastActionBanner = i18n.t(
        'Nhập ID hoặc IP thiết bị để mở trình truyền file hai chiều trực tiếp.',
        'Enter a Peer ID or IP to launch native dual-pane file transfer.',
      );
      notifyListeners();
      return;
    }
    targetPeerId = cleaned;
    DauverseNativeBridge.instance.call('record_session_history', {
      'peer_id': cleaned,
      'peer_name': cleaned,
      'route': 'OUTGOING_FILE_TRANSFER',
    });
    if (onLaunchRealSession != null) {
      lastActionBanner = i18n.t(
        'Đang mở phiên Truyền File hai chiều tới $cleaned...',
        'Opening dual-pane File Transfer to $cleaned...',
      );
      notifyListeners();
      await onLaunchRealSession!(context, cleaned, isFileTransfer: true);
    } else {
      currentScreen = DauverseScreenId.fileTransfer;
      notifyListeners();
    }
  }

  void refreshSnapshot({bool preserveActionBanner = false}) {
    final resp = DauverseNativeBridge.instance.call('dashboard_snapshot');
    if (resp['ok'] == true && resp['data'] is Map<String, dynamic>) {
      backendAvailable = true;
      backendError = '';
      snapshot = resp['data'] as Map<String, dynamic>;

      if (!_hydratedPrefsOnce) {
        _hydratedPrefsOnce = true;
        final perfMap = snapshot['performance'] as Map<String, dynamic>? ?? const {};
        if (perfMap['active_mode'] != null) {
          performanceMode = perfMap['active_mode'].toString();
        }
        if (snapshot['graphics_fallback_mode'] != null) {
          graphicsFallbackMode = snapshot['graphics_fallback_mode'].toString();
        }
        final tq = snapshot['transfer_queue'] as Map<String, dynamic>? ?? const {};
        if (tq['overwrite_policy'] != null) {
          transferOverwritePolicy = tq['overwrite_policy'].toString();
        }
        final notifMap = snapshot['notifications'] as Map<String, dynamic>? ?? const {};
        final nPrefs = notifMap['preferences'] as Map<String, dynamic>? ?? const {};
        quietMode = nPrefs['quiet_mode'] == true;
        doNotDisturb = nPrefs['do_not_disturb'] == true;
        toastAutoHideSeconds = (nPrefs['auto_hide_seconds'] as num?)?.toInt() ?? 6;
        final st = snapshot['session_tools'] as Map<String, dynamic>? ?? const {};
        final rec = st['recording'] as Map<String, dynamic>? ?? const {};
        recordingActive = rec['active'] == true;
      }

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
    } else {
      backendAvailable = false;
      backendError = resp['error']?.toString() ?? 'NATIVE_FFI_UNBOUND_FAIL_CLOSED';
      if (!preserveActionBanner && lastActionBanner.isEmpty) {
        lastActionBanner = 'FAIL-CLOSED: $backendError';
      }
      notifyListeners();
    }
  }

  bool setPerformanceProfile(String mode) {
    final res = DauverseNativeBridge.instance.call('set_performance_mode', {'mode': mode});
    if (res['ok'] == true) {
      performanceMode = mode;
      lastActionBanner = i18n.t(
        'Đã áp dụng cấu hình hiệu năng: $mode',
        'Applied performance mode: $mode',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'FAIL-CLOSED: ${res['error'] ?? 'Backend unavailable'}';
    notifyListeners();
    return false;
  }

  bool setGraphicsFallbackMode(String mode, {bool restoreHwcodec = false}) {
    final res = DauverseNativeBridge.instance.call('set_graphics_fallback_mode', {
      'mode': mode,
      'restore_hwcodec': restoreHwcodec,
    });
    if (res['ok'] == true) {
      graphicsFallbackMode = mode;
      lastActionBanner = i18n.t(
        'Đã lưu chế độ kết xuất đồ họa an toàn: $mode',
        'Saved graphics rendering mode: $mode',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'FAIL-CLOSED: ${res['error'] ?? 'Backend unavailable'}';
    notifyListeners();
    return false;
  }

  bool updateTransferOverwritePolicy(String policy) {
    final res = DauverseNativeBridge.instance.call('set_transfer_overwrite_policy', {
      'policy': policy,
    });
    if (res['ok'] == true) {
      transferOverwritePolicy = policy;
      lastActionBanner = i18n.t(
        'Đã lưu chính sách xử lý trùng tên file: $policy',
        'Saved duplicate file policy: $policy',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'FAIL-CLOSED: ${res['error'] ?? 'Backend unavailable'}';
    notifyListeners();
    return false;
  }

  void syncMiniControlEngineState({bool? minimized, bool? idle}) {
    final res = DauverseNativeBridge.instance.call('mini_control_state', {
      if (minimized != null) 'minimized': minimized,
      if (idle != null) 'idle': idle,
    });
    if (res['ok'] != true) {
      lastActionBanner = 'FAIL-CLOSED: ${res['error'] ?? 'Backend unavailable'}';
      notifyListeners();
      return;
    }
    refreshSnapshot(preserveActionBanner: true);
  }

  bool updateClipboardPolicy(Map<String, dynamic> patch) {
    final res = DauverseNativeBridge.instance.call('set_clipboard_policy', patch);
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã đồng bộ chính sách Smart Clipboard xuống Engine.',
        'Synced Smart Clipboard policy to Engine.',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'FAIL-CLOSED: ${res['error'] ?? 'Backend unavailable'}';
    notifyListeners();
    return false;
  }

  bool updateTransferBandwidthCap(int? kbps) {
    final res = DauverseNativeBridge.instance.call('transfer_set_policy', {
      'bandwidth_limit_kbps': kbps,
    });
    if (res['ok'] == true) {
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'FAIL-CLOSED: ${res['error'] ?? 'Backend unavailable'}';
    notifyListeners();
    return false;
  }

  void controlTransferJob(String action, String jobId) {
    final res = DauverseNativeBridge.instance.call('transfer_control', {
      'action': action,
      'job_id': jobId,
    });
    if (res['ok'] != true) {
      lastActionBanner = 'Transfer $action error: ${res['error'] ?? 'unknown'}';
    }
    refreshSnapshot(preserveActionBanner: true);
  }

  bool updateNotificationPrefs({bool? quiet, bool? dnd, int? autoHideSec}) {
    final nextQuiet = quiet ?? quietMode;
    final nextDnd = dnd ?? doNotDisturb;
    final nextHide = autoHideSec ?? toastAutoHideSeconds;
    final res = DauverseNativeBridge.instance.call('set_notification_prefs', {
      'quiet_mode': nextQuiet,
      'do_not_disturb': nextDnd,
      'auto_hide_seconds': nextHide,
    });
    if (res['ok'] == true) {
      quietMode = nextQuiet;
      doNotDisturb = nextDnd;
      toastAutoHideSeconds = nextHide;
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'FAIL-CLOSED: ${res['error'] ?? 'Backend unavailable'}';
    notifyListeners();
    return false;
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
    refreshSnapshot(preserveActionBanner: true);
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
    final res = DauverseNativeBridge.instance.call('session_recording_control', {
      'enable': enable,
      'explicit_opt_in': true,
    });
    if (res['ok'] == true) {
      recordingActive = enable;
      lastActionBanner = enable
          ? i18n.t(
              'CHẾ ĐỘ GHI HÌNH ĐƯỢC CẤP QUYỀN: Chỉ báo ghi hình công khai đang bật.',
              'RECORDING ARMED: Mandatory visible recording banner enabled.',
            )
          : i18n.t('Đã tắt chế độ ghi hình phiên.', 'Disabled session recording.');
      refreshSnapshot(preserveActionBanner: true);
      return;
    }
    lastActionBanner = 'FAIL-CLOSED: ${res['error'] ?? 'Recording denied'}';
    notifyListeners();
  }

  bool setStepUpPin(String pin) {
    final res = DauverseNativeBridge.instance.call('set_step_up_pin', {
      'pin': pin,
    });
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã niêm phong mã Step-Up PIN ban đầu vào kho mật mã an toàn.',
        'Enrolled initial Boss Step-Up PIN into encrypted local vault.',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'Step-Up PIN error: ${res['error'] ?? 'invalid'}';
    notifyListeners();
    return false;
  }

  bool changeStepUpPin(String currentPin, String newPin) {
    final res = DauverseNativeBridge.instance.call('change_step_up_pin', {
      'current_pin': currentPin,
      'new_pin': newPin,
    });
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã xác thực chủ sở hữu & xoay mã Step-Up PIN thành công.',
        'Verified current PIN and rotated Boss Step-Up PIN in vault.',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'Step-Up PIN change denied: ${res['error'] ?? 'invalid'}';
    notifyListeners();
    return false;
  }

  bool setAutoStartWithWindows(bool enable, String stepUpPin) {
    final res = DauverseNativeBridge.instance.call('set_auto_start', {
      'enable': enable,
      'step_up_pin': stepUpPin,
    });
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        enable ? 'Đã bật Tự khởi động cùng Windows (HKCU Run).' : 'Đã tắt Tự khởi động cùng Windows.',
        enable ? 'Enabled Start with Windows (HKCU Run).' : 'Disabled Start with Windows.',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'Auto-Start denied: ${res['error'] ?? 'PIN required'}';
    notifyListeners();
    return false;
  }

  bool configureUnattendedAccess(bool enable, String stepUpPin) {
    final res = DauverseNativeBridge.instance.call('configure_unattended', {
      'enable': enable,
      'step_up_pin': stepUpPin,
    });
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        enable
            ? 'Đã bật chế độ Unattended Access có kiểm toán (yêu cầu mật khẩu cố định).'
            : 'Đã tắt Unattended Access (chỉ cho phép xác nhận thủ công).',
        enable
            ? 'Enabled audited Unattended Access.'
            : 'Disabled Unattended Access (manual click approval enforced).',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'Unattended config denied: ${res['error'] ?? 'PIN required'}';
    notifyListeners();
    return false;
  }

  bool manageOwnedWindowsService(String action, String stepUpPin) {
    final res = DauverseNativeBridge.instance.call('manage_owned_windows_service', {
      'action': action,
      'user_confirmed': true,
      'step_up_pin': stepUpPin,
    });
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã thực thi thao tác Windows Service an toàn: $action',
        'Executed owned Windows Service operation: $action',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'Service operation refused: ${res['error'] ?? 'denied'}';
    notifyListeners();
    return false;
  }

  bool setHostCapability(String key, bool enabled, String stepUpPin) {
    final res = DauverseNativeBridge.instance.call('set_host_capability', {
      'key': key,
      'enabled': enabled,
      'step_up_pin': stepUpPin,
    });
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã cập nhật quyền phiên máy chủ ($key = ${enabled ? "BẬT" : "TẮT"}).',
        'Updated host session capability ($key = $enabled).',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'Capability change denied: ${res['error'] ?? 'PIN required'}';
    notifyListeners();
    return false;
  }

  bool approveAndActivateHeadless(String stepUpPin, String preset) {
    final parts = preset.split('@');
    final dims = parts.first.split('x');
    final w = dims.length == 2 ? (int.tryParse(dims[0]) ?? 1920) : 1920;
    final h = dims.length == 2 ? (int.tryParse(dims[1]) ?? 1080) : 1080;
    final hz = parts.length == 2 ? (int.tryParse(parts[1]) ?? 60) : 60;
    final drvRes = DauverseNativeBridge.instance.call('headless_request_driver', {
      'whql_signed': true,
      'self_signed_root': false,
      'boss_approved': true,
      'step_up_pin': stepUpPin,
    });
    if (drvRes['ok'] != true) {
      lastActionBanner = 'Headless approval denied: ${drvRes['error'] ?? 'PIN required'}';
      notifyListeners();
      return false;
    }
    final actRes = DauverseNativeBridge.instance.call('headless_activate', {
      'display_state': 'HEADLESS_NO_PHYSICAL_MONITOR',
      'preset': {'width': w, 'height': h, 'refresh_hz': hz},
    });
    if (actRes['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã kích hoạt cấu hình màn hình ảo WHQL ($w×$h @ ${hz}Hz).',
        'Activated WHQL virtual display preset ($w×$h @ ${hz}Hz).',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'Headless activation status: ${actRes['error'] ?? 'requires installed WHQL driver'}';
    refreshSnapshot(preserveActionBanner: true);
    return false;
  }

  void deactivateHeadless() {
    DauverseNativeBridge.instance.call('headless_disconnect');
    lastActionBanner = i18n.t(
      'Đã ngắt phiên màn hình ảo Headless.',
      'Deactivated Headless virtual display session.',
    );
    refreshSnapshot(preserveActionBanner: true);
  }

  bool updateShortcut(String action, String combo) {
    final res = DauverseNativeBridge.instance.call('set_shortcut', {
      'action': action,
      'combo': combo,
    });
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'Đã lưu phím tắt $action = $combo',
        'Saved shortcut $action = $combo',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'Shortcut error: ${res['error'] ?? 'invalid'}';
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
    if (res['ok'] != true && res['data'] == null) {
      final err = res['error']?.toString() ?? 'NATIVE_FFI_UNBOUND_FAIL_CLOSED';
      lastActionBanner = 'FAIL-CLOSED ($operation): $err';
      notifyListeners();
      return {'allowed': false, 'executed': false, 'status_code': 'FAIL_CLOSED', 'message': err};
    }
    final data = res['data'] as Map<String, dynamic>? ?? const {};
    lastActionBanner = '${data['status_code'] ?? operation}: ${data['message'] ?? res['error'] ?? ''}';
    refreshSnapshot(preserveActionBanner: true);
    return data;
  }

  bool emergencyRevokeAllAccess() {
    final res = DauverseNativeBridge.instance.call('revoke_all_access');
    if (res['ok'] == true) {
      lastActionBanner = i18n.t(
        'ĐÃ THU HỒI KHẨN CẤP toàn bộ quyền Unattended Access, xoay mật khẩu tạm & khoá đầu vào.',
        'EMERGENCY REVOCATION EXECUTED: Unattended access disabled, temp password rotated, inputs locked.',
      );
      refreshSnapshot(preserveActionBanner: true);
      return true;
    }
    lastActionBanner = 'FAIL-CLOSED (REVOKE DENIED): ${res['error'] ?? 'Backend unavailable'}';
    notifyListeners();
    return false;
  }
}
