# 🛠️ OpenClaw Gateway Repairer

Auto-repair script for OpenClaw Gateway with dual-trigger mechanism: automatic fault detection + Telegram manual control, powered by Qwen Code CLI for intelligent diagnostics.

> *"The best repair is the one you sleep through."* — 🦞

## 🎯 Problem

OpenClaw Gateway occasionally crashes due to port conflicts, stale processes, or failed updates. Currently, recovery requires manual SSH access — not ideal at 3 AM.

## ✨ Features

- **🔍 Real-time Monitoring** — Continuous health check, auto-trigger on failure
- **🤖 Telegram Control** — Menu-based manual repair, status check, log viewer
- **🧠 AI Diagnosis** — Qwen Code CLI analyzes errors and generates fixes
- **🛡️ Safety First** — Command allowlist, rate limiting, human escalation

## 🏗️ Architecture

```
Monitoring Daemon (launchd/systemd)
├── Health Checker ──▶ Repair Pipeline
│                     ├── Tier 1: Quick Fix (restart)
├── Telegram Bot ────▶├── Tier 2: Deep Fix (clean + restart)
│                     └── Tier 3: AI Diagnosis (Qwen Code)
└── Notification ◀────────────┘
```

## 🚀 Quick Start

```bash
git clone https://github.com/gandli/openclaw-gateway-repairer.git
cd openclaw-gateway-repairer
pip install -r requirements.txt
cp .env.example .env  # Configure Telegram Bot Token & Qwen API Key
python repairer.py
```

## 📁 Project Structure

```
openclaw-gateway-repairer/
├── README.md
├── docs/
│   └── PRD.md               # Product Requirements Document
├── requirements.txt
├── .env.example
├── repairer.py               # Main entry point
├── monitor/
│   ├── health_check.py       # Gateway health monitoring
│   └── process.py            # Process management
├── repair/
│   ├── pipeline.py           # Three-tier repair pipeline
│   ├── quick_fix.py          # Tier 1: restart
│   ├── deep_fix.py           # Tier 2: clean + restart
│   └── ai_diagnosis.py       # Tier 3: Qwen Code CLI
├── telegram/
│   ├── bot.py                # Telegram bot handler
│   └── menus.py              # Interactive menus
├── config/
│   ├── allowlist.yaml        # Allowed repair commands
│   └── settings.py           # Configuration
└── install_service.py        # Service installer
```

## 📄 Documentation

- [PRD — Product Requirements Document](docs/PRD.md)

## 📄 License

MIT
