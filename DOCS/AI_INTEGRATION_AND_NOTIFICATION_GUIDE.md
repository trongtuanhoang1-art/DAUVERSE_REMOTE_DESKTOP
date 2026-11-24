# AI EVENT BRIDGE, LIVE STATUS & NOTIFICATION CENTER GUIDE

## 1. Strategic Architecture (Sections 19, 20, 21)

`DAUVERSE REMOTE DESKTOP V1.0` includes a dedicated, authenticated **AI Event Bridge** (`src/dauverse/ai_bridge.rs`) and **Notification Center** (`src/dauverse/notifications.rs`) that operate independently of continuous screen streaming.

### Hard Safety & Truthfulness Rules
1. **No Second AI Controller:** Strictly read-only observation of AI tools and existing `DAUVERSE AI Controller` logs. Never modifies external AI controllers, queues, or workspaces.
2. **Zero Credential Harvesting:** Never reads OAuth tokens, browser cookies, session keys, or paid AI API keys. Automatically scrubs accidental tokens (`sk-...`, `ghp_...`, `Bearer ...`) via `redact_sensitive`.
3. **No Fake Completion or Fake Progress:**
   - A `PROCESS_EXITED` event with `exit_code == 0` without verified completion evidence is normalized to **`UNKNOWN`**, never `COMPLETED`.
   - `progress` is `None` unless backed by verified quantitative data (e.g., ComfyUI step `k/N`).
   - Test pass badges (e.g., `128/128 tests PASS`) render **only** when `provenance.evidence_verified == true`.
4. **No Notification Auto-Approval:** Clicking a notification can open the Remote Session or Status Panel, but `attempt_ai_approval_via_notification` is hard-blocked in Rust.

---

## 2. Configuring Official Hook Adapters

Set a shared 32-byte HMAC secret on your Home AI PC:
```powershell
[Environment]::SetEnvironmentVariable("DAUVERSE_EVENT_HMAC_KEY", "<generate-random-32-byte-hex>", "User")
```

### A. Claude Code (`~/.claude/settings.json`)
Wire [`scripts/hooks/claude_code_hook.py`](../scripts/hooks/claude_code_hook.py) into Claude Code's official `Stop` and `Notification` hooks:
```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "python E:/DAUVERSE_REMOTE_DESKTOP/scripts/hooks/claude_code_hook.py" }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "python E:/DAUVERSE_REMOTE_DESKTOP/scripts/hooks/claude_code_hook.py" }] }]
  }
}
```

### B. Codex CLI (`~/.codex/config.toml`)
Wire [`scripts/hooks/codex_notify_hook.py`](../scripts/hooks/codex_notify_hook.py):
```toml
notify = ["python", "E:/DAUVERSE_REMOTE_DESKTOP/scripts/hooks/codex_notify_hook.py"]
```

### C. Build / QA / Render / PowerShell Jobs
Wrap long builds or QA runs with [`scripts/hooks/dauverse_job_wrapper.ps1`](../scripts/hooks/dauverse_job_wrapper.ps1):
```powershell
.\scripts\hooks\dauverse_job_wrapper.ps1 -ProjectId "DAUVERSE-FT004" -TaskName "Full QA Suite" -JobKind "QA" -CommandToRun "cargo test --release"
```

### D. Unsupported / Proprietary Desktop Apps
Sources without official hooks or structured logs (e.g., closed GUI chat windows) are honestly reported as **`UNKNOWN`** or **`UNSUPPORTED`**.
