#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_BIN="$REPO_ROOT/flutter/build/linux/x64/release/bundle/rustdesk"
OUT_DIR="$REPO_ROOT/ARTIFACTS/screenshots"
mkdir -p "$OUT_DIR"

if [[ ! -x "$BUNDLE_BIN" ]]; then
  echo "ERROR: Native Linux release binary not found at $BUNDLE_BIN" >&2
  exit 1
fi

capture_screen() {
  local screen_id="$1"
  local theme_mode="$2"
  local show_toast="$3"
  local out_file="$4"

  echo "Capturing live native binary screenshot: $out_file (screen=$screen_id, theme=$theme_mode, toast=$show_toast)"
  DAUVERSE_INITIAL_SCREEN="$screen_id" \
  DAUVERSE_THEME_MODE="$theme_mode" \
  DAUVERSE_SHOW_SAMPLE_TOAST="$show_toast" \
  xvfb-run -a -s "-screen 0 1600x960x24" bash -c "
    '$BUNDLE_BIN' --dauverse-ui >/tmp/dv_gui.log 2>&1 &
    APP_PID=\$!
    for i in {1..40}; do
      WIN_ID=\$(xdotool search --onlyvisible --pid \$APP_PID 2>/dev/null | head -n 1 || true)
      if [[ -n \"\$WIN_ID\" ]]; then
        xdotool windowmove \"\$WIN_ID\" 0 0 || true
        xdotool windowsize \"\$WIN_ID\" 1600 960 || true
        break
      fi
      sleep 0.25
    done
    for attempt in {1..12}; do
      sleep 1.0
      scrot -o '$OUT_DIR/$out_file'
      FSIZE=\$(stat -c%s '$OUT_DIR/$out_file' 2>/dev/null || echo 0)
      if [[ \"\$FSIZE\" -gt 25000 ]]; then
        break
      fi
    done
    kill \$APP_PID 2>/dev/null || true
    wait \$APP_PID 2>/dev/null || true
  "
}

capture_screen "dashboard" "dark" "1" "01_dashboard_dark_vi_toast.png"
capture_screen "dashboard" "light" "0" "02_dashboard_light_vi.png"
capture_screen "remoteSession" "dark" "0" "03_remote_session_floating_toolbar.png"
capture_screen "miniControl" "dark" "0" "04_mini_control_pip.png"
capture_screen "fileTransfer" "dark" "0" "05_file_transfer_center.png"
capture_screen "aiLiveStatus" "dark" "0" "06_ai_live_status.png"
capture_screen "notificationCenter" "dark" "1" "07_notification_center.png"
capture_screen "hardwareMonitor" "dark" "0" "08_hardware_monitor_live_ffi.png"
capture_screen "smartPower" "dark" "0" "09_smart_power_interlocks.png"
capture_screen "securityCenter" "dark" "0" "10_security_center_shield.png"

ls -lh "$OUT_DIR"/*.png
