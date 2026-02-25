# 🛠️ OpenClaw Gateway Repairer

Auto-repair script for OpenClaw Gateway with dual-trigger mechanism: automatic fault detection + Telegram manual control, powered by Qwen Code CLI for intelligent diagnostics.

> *"The best repair is the one you sleep through."* — 🦞

## 🎯 Problem

OpenClaw Gateway occasionally crashes due to port conflicts, stale processes, or failed updates. Currently, recovery requires manual SSH access — not ideal at 3 AM.

## ✨ Features

- **🔍 Real-time Monitoring** — Health check every 60s (process + RPC probe)
- **🧠 Qwen AI Auto-Repair** — AI diagnoses errors and generates fixes dynamically
- **🔧 Three-Tier Pipeline** — Quick restart → Deep clean → AI diagnosis
- **🤖 Telegram Notifications** — Push alerts on repair events
- **🛡️ Safety First** — Lock file prevents concurrent runs, timeout limits

## 🚀 Quick Start

### 1. Install the watchdog script

```bash
# Clone
git clone https://github.com/gandli/openclaw-gateway-repairer.git
cd openclaw-gateway-repairer

# Copy script to OpenClaw scripts directory
mkdir -p ~/.openclaw/scripts
cp scripts/gateway-watchdog.sh ~/.openclaw/scripts/
chmod +x ~/.openclaw/scripts/gateway-watchdog.sh
```

### 2. Install as launchd service (macOS)

```bash
# Copy plist
cp config/ai.openclaw.watchdog.plist ~/Library/LaunchAgents/

# Load (immediate + auto-start on login)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.watchdog.plist

# Verify
launchctl list | grep openclaw.watchdog
```

### 3. Manual commands

```bash
# Check status
~/.openclaw/scripts/gateway-watchdog.sh status

# Health check (RPC probe)
~/.openclaw/scripts/gateway-watchdog.sh health

# Full check (status + RPC)
~/.openclaw/scripts/gateway-watchdog.sh check

# Trigger Qwen AI diagnosis
~/.openclaw/scripts/gateway-watchdog.sh diagnose

# Manual repair
~/.openclaw/scripts/gateway-watchdog.sh repair
```

## 🏗️ How It Works

```
Every 60s (launchd)
  │
  ├─ Health Check (status text + RPC probe)
  │   ├── ✅ Healthy → exit
  │   └── ❌ Failed ↓
  │
  ├─ Tier 1: Qwen AI Diagnosis (yolo mode)
  │   ├── Qwen analyzes logs & runs fix commands
  │   ├── ✅ RPC recovered → notify & exit
  │   └── ❌ Failed ↓
  │
  └─ Tier 2: Standard Repair Pipeline
      ├── Service not installed → `openclaw gateway install`
      ├── Service not loaded → `openclaw gateway install`
      └── Service loaded but unresponsive → `restart` or `reinstall`
          ├── ✅ Fixed → Telegram notification
          └── ❌ Failed → Telegram alert for human
```

## 📁 Project Structure

```
openclaw-gateway-repairer/
├── README.md
├── docs/
│   └── PRD.md                              # Product Requirements
├── scripts/
│   └── gateway-watchdog.sh                 # Main watchdog script
└── config/
    └── ai.openclaw.watchdog.plist          # macOS launchd config
```

## ⚙️ Configuration

Environment variables (set in plist or shell):

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_DIR` | `~/.openclaw/logs` | Log directory |
| `QWEN_CLI` | `/opt/homebrew/bin/qwen` | Qwen Code CLI path |
| `NOTIFICATION_CHAT_ID` | — | Telegram chat ID for alerts |

## 📋 Requirements

- macOS (launchd) or Linux (systemd)
- [OpenClaw](https://github.com/openclaw/openclaw) installed
- [Qwen Code CLI](https://github.com/QwenLM/qwen-code) (optional, for AI diagnosis)

## 📄 Documentation

- [PRD — Product Requirements Document](docs/PRD.md)

## 📄 License

MIT
