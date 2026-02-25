# 🛠️ OpenClaw Gateway Repairer

Auto-repair script for OpenClaw Gateway with dual-trigger mechanism: automatic fault detection + Telegram manual control, powered by Qwen Code CLI for intelligent diagnostics.

## 🎯 Problem

OpenClaw Gateway occasionally crashes due to:
- Port conflicts (stale daemon processes)
- Session lock file corruption
- Failed updates leaving zombie processes
- Network timeouts causing unresponsive states

Currently, recovery requires manual SSH access and running repair commands — not ideal at 3 AM.

## ✨ Features

### 1. 🔍 Real-time Monitoring
- Continuous health check of OpenClaw Gateway process
- Port availability detection (default: 18789)
- Response latency monitoring
- Automatic trigger when service stops or becomes unresponsive

### 2. 🤖 Telegram Interactive Control
- Menu-based interface for manual operations
- `/status` — View current Gateway status
- `/repair` — Trigger manual repair
- `/logs` — View recent repair logs
- `/strategy` — Manage repair strategies
- Push notifications on auto-repair events

### 3. 🧠 Qwen Code CLI Integration
- AI-powered fault diagnosis from error logs
- Dynamic repair script generation
- Escalation: simple fixes first, AI diagnosis for complex failures
- Learn from past repairs to improve future responses

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│           Monitoring Daemon              │
│  (launchd/systemd service)              │
├─────────────────────────────────────────┤
│                                         │
│  ┌───────────┐    ┌──────────────────┐  │
│  │ Health    │───▶│ Repair Pipeline  │  │
│  │ Checker   │    │                  │  │
│  └───────────┘    │ 1. Quick Fix     │  │
│                   │    (restart)      │  │
│  ┌───────────┐    │ 2. Deep Fix      │  │
│  │ Telegram  │───▶│    (clean+restart)│  │
│  │ Bot       │    │ 3. AI Diagnosis  │  │
│  └───────────┘    │    (Qwen Code)   │  │
│                   └──────────────────┘  │
│                          │              │
│                   ┌──────▼──────┐       │
│                   │ Notification │       │
│                   │ (Telegram)   │       │
│                   └─────────────┘       │
└─────────────────────────────────────────┘
```

## 🔧 Repair Pipeline

Three-tier escalation strategy:

### Tier 1: Quick Fix (< 10s)
```bash
openclaw gateway restart
```

### Tier 2: Deep Fix (< 30s)
```bash
openclaw gateway stop
rm ~/.openclaw/agents/main/sessions/*.js
openclaw gateway start
openclaw doctor --fix
```

### Tier 3: AI Diagnosis (< 2min)
```bash
# Collect error context
openclaw gateway logs --tail 50 > /tmp/gw-error.log

# Qwen Code CLI analyzes and generates fix
qwen-code --task "Diagnose OpenClaw Gateway failure" \
  --context /tmp/gw-error.log \
  --output /tmp/gw-fix.sh

# Review and execute (with safety constraints)
bash /tmp/gw-fix.sh
```

## 🛡️ Safety Constraints

- **Allowlist only**: AI-generated scripts can only run pre-approved commands
- **No data deletion**: Never `rm -rf` user data directories
- **Rollback**: Each repair creates a snapshot for rollback
- **Rate limit**: Max 3 auto-repairs per hour (prevents repair loops)
- **Human escalation**: If all tiers fail, notify via Telegram and wait for manual intervention

## 📋 Tech Stack

- **Language**: Python 3.10+
- **Monitoring**: `psutil` + subprocess
- **Telegram Bot**: `python-telegram-bot`
- **AI Engine**: Qwen Code CLI
- **Service Manager**: launchd (macOS) / systemd (Linux)
- **Logging**: structured JSON logs

## 🚀 Quick Start

```bash
# Clone
git clone https://github.com/gandli/openclaw-gateway-repairer.git
cd openclaw-gateway-repairer

# Install dependencies
pip install -r requirements.txt

# Configure
cp .env.example .env
# Edit .env with your Telegram Bot Token and Qwen API Key

# Install as service
python install_service.py

# Or run manually
python repairer.py
```

## 📁 Project Structure

```
openclaw-gateway-repairer/
├── README.md
├── requirements.txt
├── .env.example
├── repairer.py          # Main entry point
├── monitor/
│   ├── health_check.py  # Gateway health monitoring
│   └── process.py       # Process management
├── repair/
│   ├── pipeline.py      # Three-tier repair pipeline
│   ├── quick_fix.py     # Tier 1: restart
│   ├── deep_fix.py      # Tier 2: clean + restart
│   └── ai_diagnosis.py  # Tier 3: Qwen Code CLI
├── telegram/
│   ├── bot.py           # Telegram bot handler
│   └── menus.py         # Interactive menu definitions
├── config/
│   ├── allowlist.yaml   # Allowed repair commands
│   └── settings.py      # Configuration management
└── install_service.py   # Service installer
```

## 📊 Four-Dimension Evaluation

| Dimension | Score | Note |
|-----------|-------|------|
| **Value Clarity** | 💪 Strong | "Gateway crashes? Auto-fixed. Check Telegram." |
| **Value Timeline** | ⚡ Instant | Detection in seconds, repair in minutes |
| **Value Perception** | 💪 Strong | Telegram notifications on every repair event |
| **Value Discovery** | 🔧 Self-use | Born from real midnight debugging pain (Day 6) |

## 📄 License

MIT

---

> *"The best repair is the one you sleep through."* — 🦞
