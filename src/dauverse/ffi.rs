use super::{
    ai_bridge::SignedAiEventEnvelope,
    notifications::NotificationFilter,
    performance::PerformanceMode,
    smart_power::{PowerOperation, PowerSafetyContext},
    DauverseRuntime,
};
use std::{
    ffi::{CStr, CString},
    os::raw::c_char,
    panic::catch_unwind,
};

pub fn dispatch_command(cmd: &str, payload_json: &str) -> serde_json::Value {
    let rt = DauverseRuntime::global();
    let args: serde_json::Value = if payload_json.trim().is_empty() {
        serde_json::json!({})
    } else {
        match serde_json::from_str(payload_json) {
            Ok(v) => v,
            Err(e) => {
                return serde_json::json!({
                    "ok": false,
                    "error": format!("INVALID_JSON_PAYLOAD: {e}")
                });
            }
        }
    };

    match cmd {
        "dashboard_snapshot" => serde_json::json!({
            "ok": true,
            "data": rt.dashboard_snapshot(),
        }),
        "set_performance_mode" => {
            let mode_str = args
                .get("mode")
                .and_then(|v| v.as_str())
                .unwrap_or("AUTO_ADAPTIVE");
            let params = rt.performance.set_mode(PerformanceMode::from_key(mode_str));
            serde_json::json!({ "ok": true, "data": params })
        }
        "run_benchmark" => match super::performance::PerformanceEngine::run_pipeline_benchmark() {
            Ok(rep) => serde_json::json!({ "ok": true, "data": rep }),
            Err(e) => serde_json::json!({ "ok": false, "error": e }),
        },
        "hardware_sample" => {
            let (snap, alerts) = rt.hardware.sample_now();
            serde_json::json!({
                "ok": true,
                "data": {
                    "snapshot": snap,
                    "alerts": alerts,
                    "history": rt.hardware.history(),
                    "thresholds": rt.hardware.get_thresholds(),
                }
            })
        }
        "ai_live_status" => serde_json::json!({
            "ok": true,
            "data": {
                "live_tasks": rt.ai_bridge.live_tasks(),
                "recent_events": rt.ai_bridge.recent_events(),
                "sources_catalog": super::ai_bridge::AiEventBridge::supported_sources_catalog(),
                "rejected_security_count": rt.ai_bridge.rejected_security_count(),
            }
        }),
        "ai_ingest_signed_event" => {
            let parsed: Result<SignedAiEventEnvelope, _> = serde_json::from_value(args);
            match parsed {
                Ok(env) => {
                    let now_ms = chrono::Utc::now().timestamp_millis();
                    match rt.ai_bridge.ingest_signed_envelope(env, now_ms) {
                        Ok(ev) => {
                            let notif = rt.notifications.publish_from_ai_event(&ev, now_ms);
                            serde_json::json!({
                                "ok": true,
                                "data": { "event": ev, "notification": notif }
                            })
                        }
                        Err(e) => serde_json::json!({ "ok": false, "error": e }),
                    }
                }
                Err(e) => serde_json::json!({ "ok": false, "error": format!("BAD_ENVELOPE: {e}") }),
            }
        }
        "notifications_query" => {
            let filter: NotificationFilter =
                serde_json::from_value(args).unwrap_or_default();
            serde_json::json!({
                "ok": true,
                "data": {
                    "unread_count": rt.notifications.unread_count(),
                    "active_toasts": rt.notifications.active_toasts(),
                    "items": rt.notifications.query_history(&filter),
                    "preferences": rt.notifications.preferences(),
                }
            })
        }
        "notification_mark_read" => {
            if let Some(id) = args.get("id").and_then(|v| v.as_str()) {
                let updated = rt.notifications.mark_read(id);
                serde_json::json!({ "ok": true, "updated": updated, "unread_count": rt.notifications.unread_count() })
            } else {
                rt.notifications.mark_all_read();
                serde_json::json!({ "ok": true, "updated": true, "unread_count": 0 })
            }
        }
        "smart_power_action" => {
            let op_str = args
                .get("operation")
                .and_then(|v| v.as_str())
                .unwrap_or("LOCK_WORKSTATION");
            let op = match op_str {
                "WAKE_ON_LAN" => PowerOperation::WakeOnLan,
                "SLEEP" => PowerOperation::Sleep,
                "RESTART" => PowerOperation::Restart,
                "SAFE_SHUTDOWN" => PowerOperation::SafeShutdown,
                "SMART_PLUG_ON" => PowerOperation::SmartPlugPowerOn,
                "SMART_PLUG_OFF" => PowerOperation::SmartPlugPowerOff,
                _ => PowerOperation::LockWorkstation,
            };
            let (ai_running, ai_waiting, comfy_rendering) = rt.ai_bridge.active_counts();
            let dry_run_only = args
                .get("dry_run")
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            let step_up_pin = args
                .get("step_up_pin")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let step_up_verified = if dry_run_only {
                args.get("authenticated")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false)
                    || (!step_up_pin.is_empty() && rt.security.verify_step_up_passcode(step_up_pin))
            } else {
                // Live OS execution NEVER trusts an unauthenticated UI boolean flag
                rt.security.verify_step_up_passcode(step_up_pin)
            };
            let ctx = PowerSafetyContext {
                host_state: rt.smart_power.get_host_state(),
                ai_running_count: ai_running,
                ai_waiting_approval_count: ai_waiting,
                comfyui_rendering: comfy_rendering,
                active_file_transfers: rt.transfer_queue.active_transfer_count(),
                step_up_auth_verified: step_up_verified,
                force_after_warning_acknowledged: args
                    .get("force_confirmed")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false),
                dry_run_only,
            };
            let mac = args.get("mac").and_then(|v| v.as_str());
            let target = args.get("target").and_then(|v| v.as_str());
            let wol_pair = match (mac, target) {
                (Some(m), Some(t)) => Some((m, t)),
                _ => None,
            };
            let outcome = rt.smart_power.evaluate_and_execute(op, &ctx, wol_pair);
            serde_json::json!({ "ok": outcome.allowed, "data": outcome })
        }
        "set_step_up_pin" => {
            let pin = args.get("pin").and_then(|v| v.as_str()).unwrap_or("");
            match rt.security.set_step_up_passcode(pin) {
                Ok(()) => serde_json::json!({ "ok": true, "data": rt.security.summary() }),
                Err(e) => serde_json::json!({ "ok": false, "error": e }),
            }
        }
        "security_summary" => serde_json::json!({
            "ok": true,
            "data": {
                "summary": rt.security.summary(),
                "recent_audit": rt.security.recent_audit_entries(50),
            }
        }),
        "revoke_all_access" => {
            let svc = rt.service_ctrl.revoke_all_access_immediately();
            rt.security
                .append_audit("BOSS", "EMERGENCY_REVOKE_ALL_ACCESS", "OK", "Revoked unattended & service access");
            serde_json::json!({ "ok": true, "data": svc })
        }
        "network_probe" => {
            let target = args
                .get("target")
                .and_then(|v| v.as_str())
                .unwrap_or("127.0.0.1:21116");
            let timeout_ms = args
                .get("timeout_ms")
                .and_then(|v| v.as_u64())
                .unwrap_or(1_500);
            let probe = super::session_tools::SessionToolsManager::probe_endpoint(target, timeout_ms);
            serde_json::json!({ "ok": true, "data": probe })
        }
        "export_diagnostics" => {
            let notes = args.get("notes").and_then(|v| v.as_str()).unwrap_or("");
            let report = rt.session_tools.build_redacted_diagnostic_report(notes);
            serde_json::json!({ "ok": true, "data": report })
        }
        "clipboard_policy" => serde_json::json!({
            "ok": true,
            "data": rt.clipboard_guard.stats(),
        }),
        "set_clipboard_policy" => {
            let mut pol = rt.clipboard_guard.get_policy();
            if let Some(v) = args.get("enabled").and_then(|v| v.as_bool()) {
                pol.enabled = v;
            }
            if let Some(v) = args.get("allow_text_unicode").and_then(|v| v.as_bool()) {
                pol.allow_text_unicode = v;
            }
            if let Some(v) = args.get("allow_rich_html").and_then(|v| v.as_bool()) {
                pol.allow_rich_html = v;
            }
            if let Some(v) = args.get("allow_images").and_then(|v| v.as_bool()) {
                pol.allow_images = v;
            }
            if let Some(v) = args.get("allow_files").and_then(|v| v.as_bool()) {
                pol.allow_files = v;
            }
            if let Some(dir) = args.get("direction").and_then(|v| v.as_str()) {
                pol.direction = match dir {
                    "CLIENT_TO_HOST" | "CLIENT_TO_HOST_ONLY" => {
                        super::clipboard_guard::ClipboardSyncDirection::ClientToHostOnly
                    }
                    "HOST_TO_CLIENT" | "HOST_TO_CLIENT_ONLY" => {
                        super::clipboard_guard::ClipboardSyncDirection::HostToClientOnly
                    }
                    "DISABLED" => super::clipboard_guard::ClipboardSyncDirection::Disabled,
                    _ => super::clipboard_guard::ClipboardSyncDirection::Bidirectional,
                };
            }
            let updated = rt.clipboard_guard.update_policy(pol);
            let enable_flag = if updated.enabled
                && updated.direction != super::clipboard_guard::ClipboardSyncDirection::Disabled
            {
                "Y"
            } else {
                "N"
            };
            hbb_common::config::Config::set_option(
                "enable-clipboard".to_owned(),
                enable_flag.to_owned(),
            );
            rt.security.append_audit(
                "BOSS",
                "UPDATE_CLIPBOARD_POLICY",
                "OK",
                &format!("enabled={} direction={:?}", updated.enabled, updated.direction),
            );
            serde_json::json!({ "ok": true, "data": rt.clipboard_guard.stats() })
        }
        "transfer_queue" => serde_json::json!({
            "ok": true,
            "data": {
                "authorized_root": rt.transfer_queue.get_authorized_root(),
                "bandwidth_limit_kbps": rt.transfer_queue.get_bandwidth_limit_kbps(),
                "active_count": rt.transfer_queue.active_transfer_count(),
                "jobs": rt.transfer_queue.list_jobs(),
            }
        }),
        "transfer_set_policy" => {
            let cap_kbps = args
                .get("bandwidth_limit_kbps")
                .and_then(|v| v.as_u64())
                .map(|v| v as u32);
            rt.transfer_queue.set_bandwidth_limit_kbps(cap_kbps);
            serde_json::json!({
                "ok": true,
                "data": {
                    "bandwidth_limit_kbps": rt.transfer_queue.get_bandwidth_limit_kbps(),
                }
            })
        }
        "transfer_control" => {
            let action = args.get("action").and_then(|v| v.as_str()).unwrap_or("");
            let job_id = args.get("job_id").and_then(|v| v.as_str()).unwrap_or("");
            let res = match action {
                "PAUSE" => rt.transfer_queue.pause(job_id),
                "RESUME" => rt.transfer_queue.resume(job_id),
                "CANCEL" => rt.transfer_queue.cancel(job_id),
                "RETRY" => rt.transfer_queue.retry(job_id),
                _ => Err(format!("UNSUPPORTED_TRANSFER_ACTION: {action}")),
            };
            match res {
                Ok(job) => serde_json::json!({ "ok": true, "data": job }),
                Err(e) => serde_json::json!({ "ok": false, "error": e }),
            }
        }
        "mini_control_state" => {
            if let Some(m) = args.get("minimized").and_then(|v| v.as_bool()) {
                *rt.mini_control_minimized.lock().unwrap() = m;
            }
            if let Some(i) = args.get("idle").and_then(|v| v.as_bool()) {
                *rt.mini_control_idle.lock().unwrap() = i;
            }
            serde_json::json!({
                "ok": true,
                "data": rt.performance.current_telemetry(),
            })
        }
        "set_notification_prefs" => {
            let mut prefs = rt.notifications.preferences();
            if let Some(v) = args.get("quiet_mode").and_then(|v| v.as_bool()) {
                prefs.quiet_mode = v;
            }
            if let Some(v) = args.get("do_not_disturb").and_then(|v| v.as_bool()) {
                prefs.do_not_disturb = v;
            }
            if let Some(v) = args.get("auto_hide_seconds").and_then(|v| v.as_u64()) {
                prefs.auto_hide_seconds = v as u8;
            }
            let updated = rt.notifications.update_preferences(prefs);
            serde_json::json!({ "ok": true, "data": updated })
        }
        "ai_send_signed_loopback_probe" => {
            use std::io::{Read, Write};
            let port = rt.bridge_listen_port;
            if port == 0 {
                return serde_json::json!({ "ok": false, "error": "BRIDGE_HTTP_NOT_BOUND" });
            }
            let now_ms = chrono::Utc::now().timestamp_millis();
            let ev_id = uuid::Uuid::new_v4().to_string();
            let source = args
                .get("source")
                .and_then(|v| v.as_str())
                .unwrap_or("codex_cli")
                .to_owned();
            let summary = args
                .get("summary")
                .and_then(|v| v.as_str())
                .unwrap_or("Loopback signed diagnostic event verified over 127.0.0.1 HTTP gateway.")
                .to_owned();
            let ev = super::ai_bridge::AiEvent {
                event_id: ev_id,
                timestamp: chrono::Utc::now().to_rfc3339(),
                source,
                device_id: "LOCAL-WORKSTATION".to_owned(),
                project_id: "DAUVERSE_REMOTE_V1".to_owned(),
                task_id: format!("probe-{}", now_ms),
                task_name: "Signed Bridge Loopback Diagnostic".to_owned(),
                event_type: super::ai_bridge::AiEventType::QaPassed,
                status: super::ai_bridge::AiTaskStatus::Completed,
                severity: super::ai_bridge::EventSeverity::Success,
                progress: Some(100.0),
                summary,
                artifact_reference: None,
                confidence: 1.0,
                provenance: super::ai_bridge::EventProvenance {
                    adapter_type: super::ai_bridge::SourceSupportStatus::OfficialHook,
                    evidence_verified: true,
                    exit_code: Some(0),
                    evidence_badge: Some("HMAC_LOOPBACK_VERIFIED".to_owned()),
                },
            };
            let nonce = super::crypto_util::generate_nonce_hex();
            let env = rt.ai_bridge.sign_with_runtime_secret(ev, now_ms, nonce);
            let body = serde_json::to_string(&env).unwrap_or_default();
            let req = format!(
                "POST /v1/events HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            match std::net::TcpStream::connect(("127.0.0.1", port)) {
                Ok(mut s) => {
                    s.set_read_timeout(Some(std::time::Duration::from_secs(2))).ok();
                    let _ = s.write_all(req.as_bytes());
                    let mut resp = String::new();
                    let _ = s.read_to_string(&mut resp);
                    let ok = resp.starts_with("HTTP/1.1 200");
                    serde_json::json!({
                        "ok": ok,
                        "data": {
                            "port": port,
                            "http_response_head": resp.lines().next().unwrap_or(""),
                            "unread_notifications": rt.notifications.unread_count(),
                        }
                    })
                }
                Err(e) => serde_json::json!({ "ok": false, "error": format!("TCP_CONNECT_ERR: {e}") }),
            }
        }
        "verify_update_package" => {
            let path_str = args.get("artifact_path").and_then(|v| v.as_str()).unwrap_or("");
            let desc: Result<super::update_center::UpdatePackageDescriptor, _> =
                serde_json::from_value(args.get("descriptor").cloned().unwrap_or_default());
            match desc {
                Ok(d) => {
                    let res = super::update_center::verify_local_update_artifact(
                        super::update_center::DAUVERSE_PRODUCT_VERSION,
                        &d,
                        std::path::Path::new(path_str),
                    );
                    serde_json::json!({ "ok": true, "data": res })
                }
                Err(e) => serde_json::json!({ "ok": false, "error": format!("BAD_DESCRIPTOR: {e}") }),
            }
        }
        _ => serde_json::json!({
            "ok": false,
            "error": format!("UNKNOWN_COMMAND: {cmd}")
        }),
    }
}

#[no_mangle]
pub unsafe extern "C" fn dauverse_invoke(
    cmd_ptr: *const c_char,
    payload_ptr: *const c_char,
) -> *mut c_char {
    let result = catch_unwind(|| {
        let cmd = if cmd_ptr.is_null() {
            ""
        } else {
            CStr::from_ptr(cmd_ptr).to_str().unwrap_or("")
        };
        let payload = if payload_ptr.is_null() {
            "{}"
        } else {
            CStr::from_ptr(payload_ptr).to_str().unwrap_or("{}")
        };
        let val = dispatch_command(cmd, payload);
        val.to_string()
    });

    let json_str = match result {
        Ok(s) => s,
        Err(_) => r#"{"ok":false,"error":"INTERNAL_FFI_PANIC_CAUGHT"}"#.to_owned(),
    };
    CString::new(json_str)
        .unwrap_or_else(|_| CString::new(r#"{"ok":false,"error":"NUL_IN_JSON"}"#).unwrap())
        .into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn dauverse_free_str(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn ffi_c_abi_roundtrip_and_auto_bridge_pipeline_works() {
        let cmd = CString::new("dashboard_snapshot").unwrap();
        let payload = CString::new("{}").unwrap();
        unsafe {
            let raw = dauverse_invoke(cmd.as_ptr(), payload.as_ptr());
            assert!(!raw.is_null());
            let json_str = CStr::from_ptr(raw).to_str().unwrap().to_owned();
            dauverse_free_str(raw);
            let parsed: serde_json::Value = serde_json::from_str(&json_str).unwrap();
            assert_eq!(parsed["ok"], true);
            assert_eq!(parsed["data"]["product"], "DAUVERSE REMOTE DESKTOP");
            // Verify auto-started loopback HTTP bridge & zero fabricated RTT when disconnected
            assert!(parsed["data"]["bridge_port"].as_u64().unwrap_or(0) > 0);
            assert_eq!(parsed["data"]["performance"]["session_connected"], false);
            assert_eq!(parsed["data"]["performance"]["ping_rtt_ms"], 0);
            assert_eq!(parsed["data"]["performance"]["fps"], 0);
            assert!(parsed["data"]["smart_power"]["smart_plug"]["blocker_note"]
                .as_str()
                .unwrap_or("")
                .contains("Hunonic SK02"));
        }

        // Send a real signed AI event over the auto-started 127.0.0.1 HTTP listener
        let probe = dispatch_command(
            "ai_send_signed_loopback_probe",
            r#"{"source":"codex_cli","summary":"Real HTTP loopback probe"}"#,
        );
        assert_eq!(probe["ok"], true);
        assert!(probe["data"]["unread_notifications"].as_u64().unwrap_or(0) >= 1);

        // Verify clipboard policy syncs with upstream Config
        let clip_res = dispatch_command(
            "set_clipboard_policy",
            r#"{"enabled":false,"direction":"DISABLED"}"#,
        );
        assert_eq!(clip_res["ok"], true);
        assert_eq!(hbb_common::config::Config::get_option("enable-clipboard"), "N");
        let _ = dispatch_command(
            "set_clipboard_policy",
            r#"{"enabled":true,"direction":"BIDIRECTIONAL"}"#,
        );

        // Verify live OS power action rejects bare boolean authenticated=true without verified Step-Up PIN
        let unauth_live = dispatch_command(
            "smart_power_action",
            r#"{"operation":"SLEEP","authenticated":true,"dry_run":false}"#,
        );
        assert_eq!(unauth_live["ok"], false);
        assert_eq!(
            unauth_live["data"]["status_code"],
            "AUTH_REQUIRED_BEFORE_POWER_ACTION"
        );

        // Enroll sealed Step-Up PIN and verify wrong PIN is denied while active engine transfer blocks Sleep
        let pin_set = dispatch_command("set_step_up_pin", r#"{"pin":"BossVault#2026"}"#);
        assert_eq!(pin_set["ok"], true);
        let wrong_pin = dispatch_command(
            "smart_power_action",
            r#"{"operation":"SLEEP","step_up_pin":"wrong999","dry_run":false}"#,
        );
        assert_eq!(wrong_pin["ok"], false);
        assert_eq!(
            wrong_pin["data"]["status_code"],
            "AUTH_REQUIRED_BEFORE_POWER_ACTION"
        );

        let rt = DauverseRuntime::global();
        rt.transfer_queue
            .track_engine_receive_start(77, 1, "/tmp", "render.mp4", 10_485_760);
        let blocked_by_xfer = dispatch_command(
            "smart_power_action",
            r#"{"operation":"SLEEP","step_up_pin":"BossVault#2026","dry_run":true}"#,
        );
        assert_eq!(blocked_by_xfer["ok"], false);
        assert_eq!(
            blocked_by_xfer["data"]["status_code"],
            "SAFETY_INTERLOCK_CONFIRMATION_REQUIRED"
        );
        rt.transfer_queue
            .track_engine_receive_finish(77, true, false, None);
    }
}
