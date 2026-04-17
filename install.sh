#!/bin/bash
# install.sh — Install Pritunl VPN Auto-Reconnect Monitor
# Usage: curl -fsSL https://raw.githubusercontent.com/ashwinikumar7/pritunl-monitor/master/install.sh | bash

set -euo pipefail

CONFIG_DIR="$HOME/.pritunl-monitor"
PLIST_NAME="com.user.pritunl-monitor"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
PRITUNL_CLIENT="/Applications/Pritunl.app/Contents/Resources/pritunl-client"
BASE_URL="https://raw.githubusercontent.com/ashwinikumar7/pritunl-monitor/master"

info()  { printf '\033[32m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[33m[WARN]\033[0m  %s\n' "$*"; }
error() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()   { error "$*"; exit 1; }

echo ""
echo "  Pritunl VPN Auto-Reconnect Monitor"
echo "  ==================================="
echo ""

[[ "$(uname)" != "Darwin" ]] && die "macOS only"

if ! command -v oathtool &>/dev/null; then
    if command -v brew &>/dev/null; then
        info "Installing oathtool..."
        brew install oath-toolkit
    else
        die "oathtool not found. Install Homebrew (https://brew.sh) then: brew install oath-toolkit"
    fi
fi

[[ ! -x "$PRITUNL_CLIENT" ]] && die "Pritunl not found at $PRITUNL_CLIENT"

echo ""
read -rp "Path to your Pritunl profile (.tar file): " PROFILE_PATH </dev/tty
[[ -z "$PROFILE_PATH" || ! -f "$PROFILE_PATH" ]] && die "File not found: $PROFILE_PATH"

IMPORT_FILE="$PROFILE_PATH"
TAR_TMP=""
if [[ "$PROFILE_PATH" != *.tar ]]; then
    TAR_TMP="$(mktemp -d)/profile.tar"
    tar -cf "$TAR_TMP" -C "$(dirname "$PROFILE_PATH")" "$(basename "$PROFILE_PATH")"
    IMPORT_FILE="$TAR_TMP"
fi

info "Importing profile..."
"$PRITUNL_CLIENT" add "$IMPORT_FILE" || die "Failed to import profile"
[[ -n "$TAR_TMP" ]] && rm -f "$TAR_TMP"

sleep 2
PROFILE_ID=$("$PRITUNL_CLIENT" list -j 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data: print(data[-1]['id'])
else: sys.exit(1)
" 2>/dev/null) || die "Failed to discover profile ID"
info "Profile ID: $PROFILE_ID"

echo ""
read -rp "Static PIN: " STATIC_PIN </dev/tty
read -rp "TOTP Secret (base32): " TOTP_SECRET </dev/tty
[[ -z "$STATIC_PIN" || -z "$TOTP_SECRET" ]] && die "Both are required"

oathtool --totp --base32 "$TOTP_SECRET" &>/dev/null || die "Invalid TOTP secret"
info "TOTP verified"

mkdir -p "$CONFIG_DIR"

info "Downloading scripts..."
curl -fsSL "$BASE_URL/pritunl-monitor.sh" -o "$CONFIG_DIR/pritunl-monitor.sh"
curl -fsSL "$BASE_URL/uninstall.sh" -o "$CONFIG_DIR/uninstall.sh"
chmod +x "$CONFIG_DIR/pritunl-monitor.sh" "$CONFIG_DIR/uninstall.sh"
info "Scripts installed to $CONFIG_DIR"

cat > "$CONFIG_DIR/config" <<CFGEOF
PROFILE_ID="$PROFILE_ID"
STATIC_PIN="$STATIC_PIN"
TOTP_SECRET="$TOTP_SECRET"
PRITUNL_CLIENT="$PRITUNL_CLIENT"
# CHECK_INTERVAL=30
# INITIAL_BACKOFF=10
# MAX_BACKOFF=300
# MAX_RETRIES=10
CFGEOF
chmod 600 "$CONFIG_DIR/config"
info "Config saved"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_DST" <<PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.pritunl-monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/.pritunl-monitor/pritunl-monitor.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>$HOME/.pritunl-monitor/monitor.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.pritunl-monitor/monitor.stderr.log</string>
</dict>
</plist>
PEOF
info "LaunchAgent installed"

ZSHRC="$HOME/.zshrc"
if ! grep -q "pritunl-monitor aliases" "$ZSHRC" 2>/dev/null; then
    cat >> "$ZSHRC" <<'ALIASEOF'

# --- pritunl-monitor aliases ---
alias vpn-stop='launchctl unload ~/Library/LaunchAgents/com.user.pritunl-monitor.plist 2>/dev/null; echo "Auto-reconnect stopped"'
alias vpn-start='launchctl load ~/Library/LaunchAgents/com.user.pritunl-monitor.plist 2>/dev/null; echo "Auto-reconnect started"'
alias vpn-logs='tail -f ~/.pritunl-monitor/monitor.log'
alias vpn-status='launchctl list 2>/dev/null | grep pritunl-monitor || echo "Not running"'
alias vpn-uninstall='~/.pritunl-monitor/uninstall.sh'
ALIASEOF
    info "Aliases added to ~/.zshrc"
else
    warn "Aliases already in ~/.zshrc"
fi

launchctl load "$PLIST_DST" 2>/dev/null && info "Monitor started" || warn "May already be loaded"

echo ""
echo "  Done! Open a new terminal or run: source ~/.zshrc"
echo ""
echo "  Commands:"
echo "    vpn-stop      Stop auto-reconnect"
echo "    vpn-start     Resume auto-reconnect"
echo "    vpn-logs      Tail the monitor log"
echo "    vpn-status    Check if monitor is running"
echo "    vpn-uninstall Remove everything"
echo ""
