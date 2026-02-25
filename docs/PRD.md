# PRD: OpenClaw Gateway Repairer

**Version:** 1.0  
**Author:** gandli  
**Date:** 2026-02-25  
**Status:** Draft

---

## 1. Background

OpenClaw Gateway is the core daemon that manages AI agent sessions, message routing, and tool execution. When it crashes, all connected channels (Telegram, Discord, etc.) go offline until manually restarted.

### Current Pain Points

| Issue | Impact | Frequency |
|-------|--------|-----------|
| Port 18789 occupied by stale process | Gateway fails to start | Weekly |
| Session lock file corruption | Gateway hangs on startup | Occasional |
| Failed brew upgrade leaves zombie | Service unresponsive | On update |
| Network timeout causes watchdog kill | All channels offline | Rare |

### Current Recovery (Manual)

```bash
# SSH into machine, then:
openclaw gateway stop
rm ~/.openclaw/agents/main/sessions/*.js
openclaw gateway start
openclaw doctor --fix
```

**Problem:** Requires human intervention, often at inconvenient hours.

---

## 2. Product Goals

1. **Zero-downtime recovery** — Detect and fix Gateway failures within 2 minutes
2. **Transparency** — Every repair action logged and notified via Telegram
3. **Safety** — AI-generated fixes constrained by allowlist; human escalation on failure
4. **Self-learning** — Repair patterns improve over time via Qwen Code analysis

---

## 3. Target Users

- OpenClaw self-hosters running Gateway on macOS / Linux
- Primary user: the developer (dogfooding)

---

## 4. Core Features

### 4.1 Health Monitoring

**Description:** Continuously monitor Gateway process health.

**Detection Methods:**
| Check | Method | Interval |
|-------|--------|----------|
| Process alive | `pgrep` / `psutil` | 10s |
| Port responsive | TCP connect to 18789 | 30s |
| API health | `GET /health` endpoint | 60s |
| Memory usage | RSS threshold (512MB) | 60s |

**Trigger Conditions:**
- Process not found → immediate Tier 1
- Port not responding for 2 consecutive checks → Tier 1
- API health fail for 3 consecutive checks → Tier 2
- Memory exceeds threshold → log warning, Tier 2 if OOM

### 4.2 Three-Tier Repair Pipeline

#### Tier 1: Quick Fix (< 10s)

**When:** Process missing or port unresponsive  
**Action:**
```bash
openclaw gateway restart
```
**Success Criteria:** API health check passes within 10s  
**On Failure:** Escalate to Tier 2

#### Tier 2: Deep Fix (< 30s)

**When:** Tier 1 failed, or stale files detected  
**Action:**
```bash
openclaw gateway stop
# Kill any lingering processes on port 18789
lsof -ti:18789 | xargs kill -9
# Remove stale session locks
rm ~/.openclaw/agents/main/sessions/*.js
# Restart
openclaw gateway start
# Validate
openclaw doctor --fix
```
**Success Criteria:** API health check passes within 30s  
**On Failure:** Escalate to Tier 3

#### Tier 3: AI Diagnosis (< 2min)

**When:** Tier 2 failed  
**Action:**
1. Collect error context:
   - Gateway logs (last 100 lines)
   - System logs (`journalctl` / `log show`)
   - Process list, port status, disk space
2. Send to Qwen Code CLI:
   ```bash
   qwen-code --task "Diagnose OpenClaw Gateway failure" \
     --context /tmp/gw-diagnostic.json \
     --output /tmp/gw-fix.sh
   ```
3. Validate generated script against allowlist
4. Execute approved commands
5. Verify recovery

**Success Criteria:** API health check passes  
**On Failure:** Notify human via Telegram, enter cooldown

### 4.3 Telegram Bot Interface

**Commands:**

| Command | Description |
|---------|-------------|
| `/status` | Current Gateway status (pid, uptime, memory) |
| `/repair` | Manually trigger repair pipeline |
| `/logs` | Last 10 repair events |
| `/history` | Repair statistics (success rate, avg time) |
| `/config` | View/edit monitoring settings |
| `/pause` | Pause auto-repair (maintenance mode) |
| `/resume` | Resume auto-repair |

**Notifications:**
- 🟢 Gateway recovered (Tier N, took Xs)
- 🔴 Gateway down, all tiers failed — human intervention needed
- 🟡 Warning: high memory / slow response

**Inline Buttons:**
```
[🔄 Repair Now]  [📋 View Logs]
[⏸ Pause]        [📊 Stats]
```

---

## 5. Safety Constraints

### 5.1 Command Allowlist

Only these commands are permitted in auto-repair:

```yaml
# config/allowlist.yaml
allowed_commands:
  - openclaw gateway stop
  - openclaw gateway start
  - openclaw gateway restart
  - openclaw doctor --fix
  - rm ~/.openclaw/agents/main/sessions/*.js
  - kill -9 {pid}  # only for processes on port 18789
  - lsof -ti:18789
```

### 5.2 Rate Limiting

- Max **3 auto-repairs per hour**
- After 3 failures → enter cooldown (30min)
- Cooldown notification sent to Telegram

### 5.3 AI Script Validation

Before executing Qwen Code output:
1. Parse generated script line by line
2. Check each command against allowlist
3. Reject any command not in allowlist
4. Log rejected commands for review

### 5.4 Data Protection

- **Never** delete user data directories
- **Never** modify OpenClaw config files
- **Never** expose API keys in logs
- Session lock files are the only deletable artifacts

---

## 6. Technical Design

### 6.1 Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Python 3.10+ |
| Process Monitoring | `psutil` |
| Telegram Bot | `python-telegram-bot` v20+ |
| AI Engine | Qwen Code CLI |
| Service Manager | `launchd` (macOS) / `systemd` (Linux) |
| Logging | `structlog` (JSON) |
| Config | YAML + `.env` |

### 6.2 Configuration

```ini
# .env.example
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
QWEN_API_KEY=your_qwen_key

# Monitoring
HEALTH_CHECK_INTERVAL=10
GATEWAY_PORT=18789
MAX_MEMORY_MB=512

# Repair
MAX_REPAIRS_PER_HOUR=3
COOLDOWN_MINUTES=30
TIER3_ENABLED=true
```

### 6.3 Logging Format

```json
{
  "timestamp": "2026-02-25T03:14:15+08:00",
  "level": "info",
  "event": "repair_completed",
  "tier": 1,
  "duration_ms": 3200,
  "trigger": "auto",
  "success": true,
  "details": "Gateway restarted successfully"
}
```

---

## 7. Milestones

| Phase | Scope | Timeline |
|-------|-------|----------|
| **v0.1** | Health monitoring + Tier 1 + Telegram notifications | 1 day |
| **v0.2** | Tier 2 + Telegram commands (`/status`, `/repair`, `/logs`) | 1 day |
| **v0.3** | Tier 3 (Qwen Code integration) + allowlist validation | 2 days |
| **v1.0** | Service installer + documentation + testing | 1 day |

---

## 8. Success Metrics

| Metric | Target |
|--------|--------|
| Detection latency | < 30s |
| Tier 1 recovery time | < 10s |
| Tier 2 recovery time | < 30s |
| Auto-repair success rate | > 95% |
| False positive rate | < 1% |
| Human escalation rate | < 5% |

---

## 9. Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Repair loop (crash-repair-crash) | Medium | High | Rate limiting + cooldown |
| AI generates harmful command | Low | Critical | Allowlist validation |
| Network down (can't reach Qwen/Telegram) | Medium | Medium | Offline Tier 1/2 still work |
| Script runs during user operation | Low | Medium | Check active sessions before repair |

---

## 10. Future Considerations

- **Web dashboard** for repair history visualization
- **Multi-node support** for distributed OpenClaw deployments
- **Predictive maintenance** — detect degradation before crash
- **Community allowlist** — shared repair patterns from other users
