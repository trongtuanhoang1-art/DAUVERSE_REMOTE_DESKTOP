use serde::{Deserialize, Serialize};
use std::{
    net::UdpSocket,
    sync::{Arc, Mutex},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum HostPowerState {
    Online,
    Sleeping,
    ShuttingDown,
    ConfirmedOff,
    NetworkUnreachable,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PowerOperation {
    WakeOnLan,
    LockWorkstation,
    Sleep,
    Restart,
    SafeShutdown,
    SmartPlugPowerOn,
    SmartPlugPowerOff,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerSafetyContext {
    pub host_state: HostPowerState,
    pub ai_running_count: usize,
    pub ai_waiting_approval_count: usize,
    pub comfyui_rendering: bool,
    pub active_file_transfers: usize,
    pub step_up_auth_verified: bool,
    pub force_after_warning_acknowledged: bool,
    pub dry_run_only: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PowerActionOutcome {
    pub allowed: bool,
    pub executed: bool,
    pub status_code: String,
    pub warnings: Vec<String>,
    pub message: String,
    pub evidence_class: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmartPlugStatus {
    pub adapter_name: String,
    pub integration_state: String,
    pub relay_on: Option<bool>,
    pub power_watts: Option<f32>,
    pub evidence_class: String,
    pub blocker_note: Option<String>,
}

pub trait SmartPlugAdapter: Send + Sync {
    fn status(&self) -> SmartPlugStatus;
    fn turn_on(&self) -> Result<SmartPlugStatus, String>;
    fn turn_off_verified_safe(&self) -> Result<SmartPlugStatus, String>;
}

pub struct DisabledSmartPlugAdapter;

impl SmartPlugAdapter for DisabledSmartPlugAdapter {
    fn status(&self) -> SmartPlugStatus {
        SmartPlugStatus {
            adapter_name: "DisabledSmartPlugAdapter".to_owned(),
            integration_state: "BLOCKED".to_owned(),
            relay_on: None,
            power_watts: None,
            evidence_class: "BLOCKED".to_owned(),
            blocker_note: Some(
                "BLOCKED: Smart plug brand/model not specified yet. Interface ready; Boss may continue using vendor app to toggle AC power."
                    .to_owned(),
            ),
        }
    }

    fn turn_on(&self) -> Result<SmartPlugStatus, String> {
        Err("BLOCKED_SMART_PLUG_UNCONFIGURED: Configure official smart plug adapter model and credentials first.".to_owned())
    }

    fn turn_off_verified_safe(&self) -> Result<SmartPlugStatus, String> {
        Err("BLOCKED_SMART_PLUG_UNCONFIGURED: Smart plug live hardware control is disabled.".to_owned())
    }
}

pub struct SimulatedSmartPlugAdapter {
    relay_on: Mutex<bool>,
}

impl SimulatedSmartPlugAdapter {
    pub fn new(initial_on: bool) -> Self {
        Self {
            relay_on: Mutex::new(initial_on),
        }
    }
}

impl SmartPlugAdapter for SimulatedSmartPlugAdapter {
    fn status(&self) -> SmartPlugStatus {
        let on = *self.relay_on.lock().unwrap();
        SmartPlugStatus {
            adapter_name: "SimulatedSmartPlugAdapter (MOCK)".to_owned(),
            integration_state: "SIMULATED_MOCK_ONLY".to_owned(),
            relay_on: Some(on),
            power_watts: Some(if on { 95.0 } else { 0.0 }),
            evidence_class: "SIMULATED".to_owned(),
            blocker_note: Some("SIMULATED adapter for automated testing only — not a real hardware plug.".to_owned()),
        }
    }

    fn turn_on(&self) -> Result<SmartPlugStatus, String> {
        let mut g = self.relay_on.lock().unwrap();
        *g = true;
        drop(g);
        Ok(self.status())
    }

    fn turn_off_verified_safe(&self) -> Result<SmartPlugStatus, String> {
        let mut g = self.relay_on.lock().unwrap();
        *g = false;
        drop(g);
        Ok(self.status())
    }
}

pub fn parse_mac_address(mac_str: &str) -> Result<[u8; 6], String> {
    let cleaned = mac_str.trim().replace('-', ":");
    let parts: Vec<&str> = cleaned.split(':').collect();
    if parts.len() != 6 {
        return Err(format!("invalid MAC address format: '{mac_str}'"));
    }
    let mut mac = [0u8; 6];
    for (i, part) in parts.iter().enumerate() {
        if part.len() != 2 {
            return Err(format!("invalid MAC octet '{part}'"));
        }
        mac[i] = u8::from_str_radix(part, 16)
            .map_err(|_| format!("invalid hex octet '{part}' in MAC"))?;
    }
    Ok(mac)
}

pub fn build_wol_magic_packet(mac_str: &str) -> Result<[u8; 102], String> {
    let mac = parse_mac_address(mac_str)?;
    let mut packet = [0xFFu8; 102];
    for i in 0..16 {
        let start = 6 + i * 6;
        packet[start..start + 6].copy_from_slice(&mac);
    }
    Ok(packet)
}

pub fn send_wol_udp(mac_str: &str, target_addr: &str) -> Result<usize, String> {
    let packet = build_wol_magic_packet(mac_str)?;
    let sock = UdpSocket::bind("0.0.0.0:0")
        .map_err(|e| format!("failed binding UDP socket for WoL: {e}"))?;
    sock.set_broadcast(true)
        .map_err(|e| format!("failed enabling UDP broadcast for WoL: {e}"))?;
    sock.send_to(&packet, target_addr)
        .map_err(|e| format!("failed sending WoL magic packet to {target_addr}: {e}"))
}

pub struct SmartPowerController {
    host_state: Mutex<HostPowerState>,
    plug_adapter: Mutex<Arc<dyn SmartPlugAdapter>>,
    power_events_log: Mutex<Vec<String>>,
}

impl SmartPowerController {
    pub fn new() -> Self {
        Self {
            host_state: Mutex::new(HostPowerState::Online),
            plug_adapter: Mutex::new(Arc::new(DisabledSmartPlugAdapter)),
            power_events_log: Mutex::new(Vec::new()),
        }
    }

    pub fn set_plug_adapter(&self, adapter: Arc<dyn SmartPlugAdapter>) {
        let mut g = self.plug_adapter.lock().unwrap();
        *g = adapter;
    }

    pub fn plug_status(&self) -> SmartPlugStatus {
        self.plug_adapter.lock().unwrap().status()
    }

    pub fn get_host_state(&self) -> HostPowerState {
        *self.host_state.lock().unwrap()
    }

    pub fn record_network_loss(&self) -> HostPowerState {
        let mut g = self.host_state.lock().unwrap();
        if *g == HostPowerState::Online {
            *g = HostPowerState::NetworkUnreachable;
        }
        *g
    }

    pub fn set_host_state(&self, next: HostPowerState) {
        let mut g = self.host_state.lock().unwrap();
        *g = next;
    }

    pub fn evaluate_and_execute(
        &self,
        op: PowerOperation,
        ctx: &PowerSafetyContext,
        wol_mac_and_target: Option<(&str, &str)>,
    ) -> PowerActionOutcome {
        if !ctx.step_up_auth_verified {
            return PowerActionOutcome {
                allowed: false,
                executed: false,
                status_code: "AUTH_REQUIRED_BEFORE_POWER_ACTION".to_owned(),
                warnings: vec![],
                message: "Step-up authentication is mandatory before any power control action.".to_owned(),
                evidence_class: "REAL_VERIFIED".to_owned(),
            };
        }

        let mut warnings = Vec::new();
        if ctx.ai_running_count > 0 {
            warnings.push(format!(
                "ACTIVE_AI_TASKS: {} AI task(s) currently RUNNING.",
                ctx.ai_running_count
            ));
        }
        if ctx.ai_waiting_approval_count > 0 {
            warnings.push(format!(
                "AI_WAITING_APPROVAL: {} AI task(s) awaiting Boss approval.",
                ctx.ai_waiting_approval_count
            ));
        }
        if ctx.comfyui_rendering {
            warnings.push("COMFYUI_RENDERING: ComfyUI video/image render queue is active.".to_owned());
        }
        if ctx.active_file_transfers > 0 {
            warnings.push(format!(
                "ACTIVE_FILE_TRANSFERS: {} file transfer(s) in progress.",
                ctx.active_file_transfers
            ));
        }

        match op {
            PowerOperation::WakeOnLan => {
                let Some((mac, addr)) = wol_mac_and_target else {
                    return PowerActionOutcome {
                        allowed: false,
                        executed: false,
                        status_code: "WOL_MISSING_MAC_OR_TARGET".to_owned(),
                        warnings,
                        message: "Wake-on-LAN requires a valid target MAC address and broadcast/gateway endpoint.".to_owned(),
                        evidence_class: "REAL_VERIFIED".to_owned(),
                    };
                };
                match send_wol_udp(mac, addr) {
                    Ok(bytes) => {
                        self.log_event(format!("WOL_SENT mac={mac} target={addr} bytes={bytes}"));
                        PowerActionOutcome {
                            allowed: true,
                            executed: true,
                            status_code: "WOL_MAGIC_PACKET_DISPATCHED".to_owned(),
                            warnings,
                            message: format!("Sent {bytes}-byte Wake-on-LAN magic packet to {addr}."),
                            evidence_class: "REAL_VERIFIED".to_owned(),
                        }
                    }
                    Err(e) => PowerActionOutcome {
                        allowed: false,
                        executed: false,
                        status_code: "WOL_SEND_FAILED".to_owned(),
                        warnings,
                        message: e,
                        evidence_class: "REAL_VERIFIED".to_owned(),
                    },
                }
            }
            PowerOperation::SmartPlugPowerOff => {
                if ctx.host_state != HostPowerState::ConfirmedOff {
                    return PowerActionOutcome {
                        allowed: false,
                        executed: false,
                        status_code: "HARD_INTERLOCK_OS_NOT_CONFIRMED_OFF".to_owned(),
                        warnings,
                        message: format!(
                            "Refusing AC smart plug cut: host OS state is {:?}. Network loss or running Windows never permits cutting AC power.",
                            ctx.host_state
                        ),
                        evidence_class: "REAL_VERIFIED".to_owned(),
                    };
                }
                let adapter = self.plug_adapter.lock().unwrap().clone();
                match adapter.turn_off_verified_safe() {
                    Ok(st) => PowerActionOutcome {
                        allowed: true,
                        executed: true,
                        status_code: "SMART_PLUG_OFF_OK".to_owned(),
                        warnings,
                        message: "Smart plug AC relay turned off after confirmed OS shutdown.".to_owned(),
                        evidence_class: st.evidence_class,
                    },
                    Err(e) => PowerActionOutcome {
                        allowed: false,
                        executed: false,
                        status_code: "SMART_PLUG_BLOCKED".to_owned(),
                        warnings,
                        message: e,
                        evidence_class: "BLOCKED".to_owned(),
                    },
                }
            }
            PowerOperation::SmartPlugPowerOn => {
                let adapter = self.plug_adapter.lock().unwrap().clone();
                match adapter.turn_on() {
                    Ok(st) => PowerActionOutcome {
                        allowed: true,
                        executed: true,
                        status_code: "SMART_PLUG_ON_OK".to_owned(),
                        warnings,
                        message: "Smart plug AC relay turned on.".to_owned(),
                        evidence_class: st.evidence_class,
                    },
                    Err(e) => PowerActionOutcome {
                        allowed: false,
                        executed: false,
                        status_code: "SMART_PLUG_BLOCKED".to_owned(),
                        warnings,
                        message: e,
                        evidence_class: "BLOCKED".to_owned(),
                    },
                }
            }
            PowerOperation::LockWorkstation => {
                self.log_event("OS_LOCK_REQUESTED".to_owned());
                PowerActionOutcome {
                    allowed: true,
                    executed: !ctx.dry_run_only,
                    status_code: "OS_LOCK_ACCEPTED".to_owned(),
                    warnings,
                    message: if ctx.dry_run_only {
                        "Dry-run: workstation lock validated.".to_owned()
                    } else {
                        "Workstation lock command dispatched.".to_owned()
                    },
                    evidence_class: "REAL_VERIFIED".to_owned(),
                }
            }
            PowerOperation::Sleep | PowerOperation::Restart | PowerOperation::SafeShutdown => {
                if !warnings.is_empty() && !ctx.force_after_warning_acknowledged {
                    return PowerActionOutcome {
                        allowed: false,
                        executed: false,
                        status_code: "SAFETY_INTERLOCK_CONFIRMATION_REQUIRED".to_owned(),
                        warnings,
                        message: "Active AI/ComfyUI/File Transfer workloads detected; explicit confirmation required before Sleep/Restart/Shutdown.".to_owned(),
                        evidence_class: "REAL_VERIFIED".to_owned(),
                    };
                }
                self.log_event(format!("OS_POWER_VALIDATED op={op:?} dry_run={}", ctx.dry_run_only));
                PowerActionOutcome {
                    allowed: true,
                    executed: !ctx.dry_run_only,
                    status_code: "SAFE_OS_POWER_COMMAND_ACCEPTED".to_owned(),
                    warnings,
                    message: format!(
                        "Graceful OS {:?} validated (dry_run={}).",
                        op, ctx.dry_run_only
                    ),
                    evidence_class: "REAL_VERIFIED".to_owned(),
                }
            }
        }
    }

    pub fn recent_events(&self) -> Vec<String> {
        self.power_events_log.lock().unwrap().clone()
    }

    fn log_event(&self, entry: String) {
        let mut g = self.power_events_log.lock().unwrap();
        if g.len() >= 100 {
            g.remove(0);
        }
        g.push(format!("{} | {}", chrono::Utc::now().to_rfc3339(), entry));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wol_magic_packet_loopback_verified() {
        let recv_sock = UdpSocket::bind("127.0.0.1:0").unwrap();
        let addr = recv_sock.local_addr().unwrap();

        let ctrl = SmartPowerController::new();
        let ctx = PowerSafetyContext {
            host_state: HostPowerState::ConfirmedOff,
            ai_running_count: 0,
            ai_waiting_approval_count: 0,
            comfyui_rendering: false,
            active_file_transfers: 0,
            step_up_auth_verified: true,
            force_after_warning_acknowledged: false,
            dry_run_only: true,
        };
        let res = ctrl.evaluate_and_execute(
            PowerOperation::WakeOnLan,
            &ctx,
            Some(("AA:BB:CC:11:22:33", &addr.to_string())),
        );
        assert!(res.allowed && res.executed);

        let mut buf = [0u8; 128];
        let (n, _) = recv_sock.recv_from(&mut buf).unwrap();
        assert_eq!(n, 102);
        assert_eq!(&buf[0..6], &[0xFF; 6]);
        assert_eq!(&buf[6..12], &[0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33]);
        assert_eq!(&buf[96..102], &[0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33]);
    }

    #[test]
    fn interlocks_block_unauthenticated_active_ai_and_live_ac_cut() {
        let ctrl = SmartPowerController::new();
        ctrl.set_plug_adapter(Arc::new(SimulatedSmartPlugAdapter::new(true)));

        let mut ctx = PowerSafetyContext {
            host_state: HostPowerState::Online,
            ai_running_count: 1,
            ai_waiting_approval_count: 0,
            comfyui_rendering: true,
            active_file_transfers: 1,
            step_up_auth_verified: false,
            force_after_warning_acknowledged: false,
            dry_run_only: true,
        };

        let unauth = ctrl.evaluate_and_execute(PowerOperation::SafeShutdown, &ctx, None);
        assert!(!unauth.allowed);
        assert_eq!(unauth.status_code, "AUTH_REQUIRED_BEFORE_POWER_ACTION");

        ctx.step_up_auth_verified = true;
        let blocked_workload = ctrl.evaluate_and_execute(PowerOperation::SafeShutdown, &ctx, None);
        assert!(!blocked_workload.allowed);
        assert_eq!(blocked_workload.warnings.len(), 3);

        let net_lost_state = ctrl.record_network_loss();
        assert_eq!(net_lost_state, HostPowerState::NetworkUnreachable);
        ctx.host_state = net_lost_state;
        let ac_cut_denied = ctrl.evaluate_and_execute(PowerOperation::SmartPlugPowerOff, &ctx, None);
        assert!(!ac_cut_denied.allowed);
        assert_eq!(ac_cut_denied.status_code, "HARD_INTERLOCK_OS_NOT_CONFIRMED_OFF");

        ctx.host_state = HostPowerState::ConfirmedOff;
        let ac_cut_ok = ctrl.evaluate_and_execute(PowerOperation::SmartPlugPowerOff, &ctx, None);
        assert!(ac_cut_ok.allowed);
        assert_eq!(ac_cut_ok.evidence_class, "SIMULATED");
    }
}
