#!/bin/bash
# pritunl-monitor.sh — Pritunl VPN Auto-Reconnect Monitor
# Monitors Pritunl VPN connection and auto-reconnects with TOTP-based MFA.

# --- Ensure Homebrew is in PATH (launchd uses minimal PATH) ---
if [[ -x /opt/homebrew/bin/brew ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
elif [[ -x /usr/local/bin/brew ]]; then
    export PATH="/usr/local/bin:$PATH"
fi

# --- Defaults ---
DEFAULT_CHECK_INTERVAL=30
DEFAULT_INITIAL_BACKOFF=10
DEFAULT_MAX_BACKOFF=300
DEFAULT_MAX_RETRIES=10
DEFAULT_MAX_LOG_SIZE=10485760
DEFAULT_LOG_ROTATE_COUNT=3
DEFAULT_LOG_FILE="$HOME/.pritunl-monitor/monitor.log"
DEFAULT_PID_FILE="$HOME/.pritunl-monitor/monitor.pid"
DEFAULT_PRITUNL_CLIENT="/Applications/Pritunl.app/Contents/Resources/pritunl-client"

# validate_numeric VALUE
# Returns 0 if VALUE is a positive integer (>0), 1 otherwise.
validate_numeric() {
    local val="$1"
    if [[ -z "$val" ]]; then
        return 1
    fi
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if (( val <= 0 )); then
        return 1
    fi
    return 0
}

# --- Logging ---

rotate_log() {
    [[ -f "$LOG_FILE" ]] || return 0
    local file_size
    file_size=$(stat -f%z "$LOG_FILE" 2>/dev/null) || return 0
    if (( file_size <= MAX_LOG_SIZE )); then
        return 0
    fi
    local oldest="${LOG_FILE}.${LOG_ROTATE_COUNT}"
    [[ -f "$oldest" ]] && rm -f "$oldest"
    local i
    for (( i = LOG_ROTATE_COUNT - 1; i >= 1; i-- )); do
        local src="${LOG_FILE}.${i}"
        local dst="${LOG_FILE}.$(( i + 1 ))"
        [[ -f "$src" ]] && mv -f "$src" "$dst"
    done
    mv -f "$LOG_FILE" "${LOG_FILE}.1"
}

log_msg() {
    local level="$1"; shift
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[${timestamp}] [${level}] $*"
    echo "$line"
    rotate_log
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null
    if echo "$line" >> "$LOG_FILE" 2>/dev/null; then
        : # success
    else
        echo "$line" >&2
    fi
}

load_config() {
    local config_file="${1:-$HOME/.pritunl-monitor/config}"
    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
    fi
    CHECK_INTERVAL="${CHECK_INTERVAL:-$DEFAULT_CHECK_INTERVAL}"
    INITIAL_BACKOFF="${INITIAL_BACKOFF:-$DEFAULT_INITIAL_BACKOFF}"
    MAX_BACKOFF="${MAX_BACKOFF:-$DEFAULT_MAX_BACKOFF}"
    MAX_RETRIES="${MAX_RETRIES:-$DEFAULT_MAX_RETRIES}"
    MAX_LOG_SIZE="${MAX_LOG_SIZE:-$DEFAULT_MAX_LOG_SIZE}"
    LOG_ROTATE_COUNT="${LOG_ROTATE_COUNT:-$DEFAULT_LOG_ROTATE_COUNT}"
    LOG_FILE="${LOG_FILE:-$DEFAULT_LOG_FILE}"
    PRITUNL_CLIENT="${PRITUNL_CLIENT:-$DEFAULT_PRITUNL_CLIENT}"
    PID_FILE="${PID_FILE:-$DEFAULT_PID_FILE}"
    local missing=0
    if [[ -z "${STATIC_PIN:-}" ]]; then
        log_msg "ERROR" "Required configuration missing: STATIC_PIN"
        missing=1
    fi
    if [[ -z "${TOTP_SECRET:-}" ]]; then
        log_msg "ERROR" "Required configuration missing: TOTP_SECRET"
        missing=1
    fi
    if [[ -z "${PROFILE_ID:-}" ]]; then
        log_msg "ERROR" "Required configuration missing: PROFILE_ID"
        missing=1
    fi
    if (( missing == 1 )); then
        return 1
    fi
    if ! validate_numeric "$CHECK_INTERVAL"; then
        log_msg "WARN" "Invalid CHECK_INTERVAL='$CHECK_INTERVAL', using default $DEFAULT_CHECK_INTERVAL"
        CHECK_INTERVAL="$DEFAULT_CHECK_INTERVAL"
    fi
    if ! validate_numeric "$INITIAL_BACKOFF"; then
        log_msg "WARN" "Invalid INITIAL_BACKOFF='$INITIAL_BACKOFF', using default $DEFAULT_INITIAL_BACKOFF"
        INITIAL_BACKOFF="$DEFAULT_INITIAL_BACKOFF"
    fi
    if ! validate_numeric "$MAX_BACKOFF"; then
        log_msg "WARN" "Invalid MAX_BACKOFF='$MAX_BACKOFF', using default $DEFAULT_MAX_BACKOFF"
        MAX_BACKOFF="$DEFAULT_MAX_BACKOFF"
    fi
    if ! validate_numeric "$MAX_RETRIES"; then
        log_msg "WARN" "Invalid MAX_RETRIES='$MAX_RETRIES', using default $DEFAULT_MAX_RETRIES"
        MAX_RETRIES="$DEFAULT_MAX_RETRIES"
    fi
    if ! validate_numeric "$MAX_LOG_SIZE"; then
        log_msg "WARN" "Invalid MAX_LOG_SIZE='$MAX_LOG_SIZE', using default $DEFAULT_MAX_LOG_SIZE"
        MAX_LOG_SIZE="$DEFAULT_MAX_LOG_SIZE"
    fi
    if ! validate_numeric "$LOG_ROTATE_COUNT"; then
        log_msg "WARN" "Invalid LOG_ROTATE_COUNT='$LOG_ROTATE_COUNT', using default $DEFAULT_LOG_ROTATE_COUNT"
        LOG_ROTATE_COUNT="$DEFAULT_LOG_ROTATE_COUNT"
    fi
    return 0
}

# --- PID File Management ---

write_pid() {
    local pid_dir
    pid_dir="$(dirname "$PID_FILE")"
    [[ -d "$pid_dir" ]] || mkdir -p "$pid_dir" 2>/dev/null
    echo $$ > "$PID_FILE"
}

check_pid() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            local proc_cmd
            proc_cmd=$(ps -p "$pid" -o args= 2>/dev/null || true)
            if [[ "$proc_cmd" == *"pritunl-monitor"* ]]; then
                log_msg "ERROR" "Another instance is already running (PID: $pid)"
                return 1
            else
                log_msg "WARN" "PID $pid exists but is not pritunl-monitor (reused PID), removing stale PID file"
                rm -f "$PID_FILE"
                return 0
            fi
        else
            log_msg "WARN" "Stale PID file found (PID: $pid), removing"
            rm -f "$PID_FILE"
            return 0
        fi
    fi
    return 0
}

cleanup() {
    [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
    log_msg "INFO" "Monitor shutting down"
}

trap cleanup SIGTERM SIGINT

# --- Health Check ---

check_status() {
    local json_output
    json_output=$("$PRITUNL_CLIENT" list -j 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$json_output" ]]; then
        log_msg "ERROR" "Failed to get status from pritunl-client"
        echo "Disconnected"
        return 1
    fi
    local status
    status=$(echo "$json_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data:
    if p.get('id','').startswith('$PROFILE_ID') or '$PROFILE_ID'.startswith(p.get('id','')):
        if p.get('connected', False):
            print('Connected')
        elif p.get('run_state','') == 'Active':
            print('Connecting')
        else:
            print('Disconnected')
        sys.exit(0)
print('NOT_FOUND')
" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$status" ]]; then
        log_msg "ERROR" "Failed to parse pritunl-client JSON output"
        echo "Disconnected"
        return 1
    fi
    if [[ "$status" == "NOT_FOUND" ]]; then
        log_msg "ERROR" "Profile ID not found in pritunl-client output: $PROFILE_ID"
        return 1
    fi
    echo "$status"
    return 0
}

# --- Authentication ---

generate_totp() {
    local totp_code
    totp_code=$(oathtool --totp --base32 "$TOTP_SECRET" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$totp_code" ]]; then
        log_msg "ERROR" "TOTP generation failed"
        return 1
    fi
    echo "$totp_code"
    return 0
}

build_password() {
    local totp_code
    totp_code=$(generate_totp)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    echo "${STATIC_PIN}${totp_code}"
    return 0
}

# --- Reconnection State ---
retry_count=0
current_backoff=0
disconnect_time=0

calculate_backoff() {
    local initial="$1"
    local max="$2"
    local attempt="$3"
    local backoff=$(( initial * (1 << attempt) ))
    if (( backoff > max )); then
        backoff=$max
    fi
    echo "$backoff"
}

verify_connection() {
    local elapsed=0
    local poll_interval=2
    local timeout=30
    while (( elapsed < timeout )); do
        local status
        status=$(check_status)
        if [[ "$status" == "Connected" ]]; then
            return 0
        fi
        sleep "$poll_interval"
        elapsed=$(( elapsed + poll_interval ))
    done
    return 1
}

reconnect() {
    local auth_password
    auth_password=$(build_password)
    if [[ $? -ne 0 ]] || [[ -z "$auth_password" ]]; then
        log_msg "ERROR" "Failed to generate auth password — skipping reconnect attempt"
        retry_count=$(( retry_count + 1 ))
        return 1
    fi
    log_msg "INFO" "Starting reconnection (attempt $((retry_count + 1)))"
    "$PRITUNL_CLIENT" start "$PROFILE_ID" --password "$auth_password" 2>/dev/null
    if verify_connection; then
        local now
        now=$(date +%s)
        local downtime=0
        if (( disconnect_time > 0 )); then
            downtime=$(( now - disconnect_time ))
        fi
        log_msg "INFO" "Reconnection successful (downtime: ${downtime}s)"
        return 0
    else
        log_msg "ERROR" "Reconnection failed: connection timeout after 30s"
        return 1
    fi
}

# --- Main Loop ---

main_loop() {
    while true; do
        local status
        status=$(check_status)
        if [[ "$status" == "Connected" ]]; then
            log_msg "INFO" "Health check: Connected"
            retry_count=0
            current_backoff=0
            disconnect_time=0
            sleep "$CHECK_INTERVAL"
        else
            if (( disconnect_time == 0 )); then
                disconnect_time=$(date +%s)
            fi
            if (( retry_count >= MAX_RETRIES )); then
                log_msg "WARN" "Max retries reached, pausing for 15 minutes"
                sleep 900
                retry_count=0
                continue
            fi
            current_backoff=$(calculate_backoff "$INITIAL_BACKOFF" "$MAX_BACKOFF" "$retry_count")
            log_msg "WARN" "Health check: Disconnected — initiating reconnect (attempt $((retry_count+1)), backoff ${current_backoff}s)"
            if reconnect; then
                retry_count=0
                current_backoff=0
                disconnect_time=0
            else
                retry_count=$(( retry_count + 1 ))
                sleep "$current_backoff"
            fi
        fi
    done
}

# --- Script Entrypoint ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if ! load_config "$@"; then
        exit 1
    fi
    if [[ ! -x "$PRITUNL_CLIENT" ]]; then
        log_msg "ERROR" "pritunl-client not found or not executable: $PRITUNL_CLIENT"
        exit 1
    fi
    if ! command -v oathtool &>/dev/null; then
        log_msg "ERROR" "oathtool not found in PATH — install via: brew install oath-toolkit"
        exit 1
    fi
    if ! check_pid; then
        exit 1
    fi
    write_pid
    trap 'log_msg "INFO" "Reloading configuration"; load_config' SIGHUP
    log_msg "INFO" "Monitor started (PID: $$, Profile: $PROFILE_ID)"
    main_loop
fi
