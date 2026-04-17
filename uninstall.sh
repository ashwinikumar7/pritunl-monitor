#!/bin/bash
# uninstall.sh — Uninstall Pritunl VPN Auto-Reconnect Monitor
# Unloads LaunchAgent, removes plist, optionally removes config directory.

set -euo pipefail

PLIST_NAME="com.user.pritunl-monitor"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
CONFIG_DIR="$HOME/.pritunl-monitor"

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; }

# --- Unload LaunchAgent ---
if [[ -f "$PLIST_DST" ]]; then
    info "Unloading LaunchAgent..."
    launchctl unload "$PLIST_DST" 2>/dev/null && info "LaunchAgent unloaded" || warn "LaunchAgent was not loaded"
    rm -f "$PLIST_DST"
    info "Removed plist: $PLIST_DST"
else
    warn "Plist not found at $PLIST_DST — skipping unload"
fi

# --- Remove PID file if present ---
PID_FILE="$CONFIG_DIR/monitor.pid"
if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        info "Stopping running monitor (PID: $pid)..."
        kill "$pid" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$PID_FILE"
fi

# --- Optionally remove config directory ---
if [[ -d "$CONFIG_DIR" ]]; then
    echo ""
    read -rp "Remove config directory $CONFIG_DIR? This deletes your config and logs. [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        info "Removed $CONFIG_DIR"
    else
        info "Kept $CONFIG_DIR"
    fi
else
    info "Config directory not found — nothing to remove"
fi

info "Uninstall complete."
