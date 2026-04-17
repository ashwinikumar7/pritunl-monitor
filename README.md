# Pritunl VPN Auto-Reconnect Monitor

Monitors your Pritunl VPN connection on macOS and auto-reconnects when it drops — handling PIN + TOTP authentication automatically.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/ashwinikumar7/pritunl-monitor/master/install.sh | bash
```

The installer will:
1. Install `oathtool` if missing (via Homebrew)
2. Import your Pritunl `.tar` profile into the CLI
3. Prompt for your static PIN and TOTP base32 secret
4. Download and install the monitor script
5. Set up a LaunchAgent (auto-starts on login)
6. Add shell aliases to `~/.zshrc`

### Prerequisites

- macOS with [Pritunl Client](https://client.pritunl.com/) installed
- Your Pritunl profile `.tar` file (from the Pritunl server web console)
- Your static PIN and TOTP base32 secret
- [Homebrew](https://brew.sh)

## Commands

After installation, open a new terminal (or `source ~/.zshrc`):

| Command | Description |
|---|---|
| `vpn-stop` | Stop auto-reconnect |
| `vpn-start` | Resume auto-reconnect |
| `vpn-logs` | Tail the monitor log |
| `vpn-status` | Check if monitor is running |
| `vpn-uninstall` | Remove everything |

## Configuration

Config file: `~/.pritunl-monitor/config`

| Parameter | Required | Default | Description |
|---|---|---|---|
| `PROFILE_ID` | Yes | (auto) | CLI-assigned profile ID |
| `STATIC_PIN` | Yes | — | Your Pritunl static PIN |
| `TOTP_SECRET` | Yes | — | Base32 TOTP secret |
| `CHECK_INTERVAL` | No | 30 | Seconds between health checks |
| `INITIAL_BACKOFF` | No | 10 | Initial retry delay (seconds) |
| `MAX_BACKOFF` | No | 300 | Max retry delay cap (seconds) |
| `MAX_RETRIES` | No | 10 | Failures before 15-min cooldown |

## File Locations

| File | Path |
|---|---|
| Monitor script | `~/.pritunl-monitor/pritunl-monitor.sh` |
| Config | `~/.pritunl-monitor/config` |
| Log | `~/.pritunl-monitor/monitor.log` |
| LaunchAgent | `~/Library/LaunchAgents/com.user.pritunl-monitor.plist` |
| Uninstall | `~/.pritunl-monitor/uninstall.sh` |

## Uninstall

```bash
vpn-uninstall
```

Or directly:

```bash
~/.pritunl-monitor/uninstall.sh
```
