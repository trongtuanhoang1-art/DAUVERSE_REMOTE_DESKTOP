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
            let ctx = PowerSafetyContext {
                host_state: rt.smart_power.get_host_state(),
                ai_running_count: ai_running,
                ai_waiting_approval_count: ai_waiting,
                comfyui_rendering: comfy_rendering,
                active_file_transfers: rt.transfer_queue.active_transfer_count(),
                step_up_auth_verified: args
                    .get("authenticated")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false),
                force_after_warning_acknowledged: args
                    .get("force_confirmed")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false),
                dry_run_only: args
                    .get("dry_run")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(true),
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
        "transfer_queue" => serde_json::json!({
            "ok": true,
            "data": {
                "authorized_root": rt.transfer_queue.get_authorized_root(),
                "bandwidth_limit_kbps": rt.transfer_queue.get_bandwidth_limit_kbps(),
                "jobs": rt.transfer_queue.list_jobs(),
            }
        }),
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
    fn ffi_c_abi_roundtrip_and_free_works() {
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
        }
    }
}
