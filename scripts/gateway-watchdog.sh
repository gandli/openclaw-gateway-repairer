#!/bin/bash
# ============================================================
# OpenClaw Gateway 智能监控系统 v4
# ============================================================

# 注意：不使用 set -e，因为健康检查命令在服务异常时必然返回非零

# ============================================================
# 配置
# ============================================================
LOG_DIR="${LOG_DIR:-$HOME/.openclaw/logs}"
LOG_FILE="${LOG_DIR}/gateway-watchdog.log"
LOCK_FILE="/tmp/gateway-watchdog.lock"
QWEN_CLI="${QWEN_CLI:-/opt/homebrew/bin/qwen}"
NOTIFICATION_CHAT_ID="${NOTIFICATION_CHAT_ID:-944783507}"
OPENCLAW_SERVICE="ai.openclaw.gateway"
GATEWAY_LOG="/tmp/openclaw/openclaw-$(date '+%Y-%m-%d').log"
STATE_FILE="${LOG_DIR}/watchdog-state"
MAX_LOG_BYTES=$((5 * 1024 * 1024))   # 5MB 日志轮转阈值
SILENCE_PERIOD=600                    # 连续失败静默期（秒），避免重复通知

# ============================================================
# macOS 兼容：可靠的 _timeout 实现（后台进程 + kill，不依赖 perl）
# 用法：_timeout <秒数> <命令> [参数...]
# ============================================================
_timeout() {
    local t=$1; shift
    if command -v gtimeout &>/dev/null; then
        gtimeout "$t" "$@"
    elif command -v timeout &>/dev/null; then
        timeout "$t" "$@"
    else
        # 纯 bash 实现：后台运行命令，$t 秒后 kill
        "$@" &
        local pid=$!
        (
            sleep "$t"
            kill "$pid" 2>/dev/null
        ) &
        local watcher=$!
        wait "$pid" 2>/dev/null
        local rc=$?
        kill "$watcher" 2>/dev/null
        return $rc
    fi
}

# ============================================================
# 日志轮转：超过 5MB 时保留最近 1000 行
# ============================================================
rotate_log() {
    [ -f "$LOG_FILE" ] || return
    local size
    size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$MAX_LOG_BYTES" ]; then
        local tmp; tmp=$(mktemp)
        tail -1000 "$LOG_FILE" > "$tmp" && mv "$tmp" "$LOG_FILE"
        log "INFO" "日志已轮转（超过 5MB，保留最近 1000 行）"
    fi
}

# ============================================================
# 连续失败计数 + 静默期
# ============================================================
get_failures() {
    local f="${STATE_FILE}.failures"
    [ -f "$f" ] && cat "$f" 2>/dev/null || echo 0
}
inc_failures() {
    local f="${STATE_FILE}.failures"
    echo $(( $(get_failures) + 1 )) > "$f"
}
reset_failures() {
    rm -f "${STATE_FILE}.failures" "${STATE_FILE}.last_notify"
}
in_silence_period() {
    local ts_file="${STATE_FILE}.last_notify"
    [ -f "$ts_file" ] || return 1
    local last now
    last=$(cat "$ts_file" 2>/dev/null || echo 0)
    now=$(date +%s)
    [ $(( now - last )) -lt "$SILENCE_PERIOD" ]
}
mark_notified() {
    date +%s > "${STATE_FILE}.last_notify"
}

# ============================================================
log() {
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2"
    echo "$line" >> "$LOG_FILE"
    # 仅在交互终端时输出到 stdout（避免 LaunchAgent 双写）
    [ -t 1 ] && echo "$line"
}

# ============================================================
# 锁（原子性，防止并发）
# ============================================================
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "INFO" "已有实例运行 (PID=$pid)，退出"
            exit 0
        fi
        log "WARN" "清理过期锁文件"
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}
release_lock() { rm -f "$LOCK_FILE"; }

# ============================================================
# 检查函数
# ============================================================

# 检查 LaunchAgent 是否已加载（通过 launchctl list | grep）
is_service_loaded() {
    launchctl list 2>/dev/null | grep -q "$OPENCLAW_SERVICE"
}

# 检查 LaunchAgent 是否已安装（plist 文件存在）
is_service_installed() {
    [ -f "$HOME/Library/LaunchAgents/${OPENCLAW_SERVICE}.plist" ]
}

# 健康检查：通过 RPC 探测 WebSocket 连通性
# openclaw health --json 失败 → gateway 无响应
check_health_rpc() {
    openclaw health --json >/dev/null 2>&1
}

# 状态检查：解析 gateway status 输出判断服务状态
# 关键词：若输出含 "not loaded" / "not installed" / "Service unit not found" → 异常
check_status_text() {
    local output
    output=$(openclaw gateway status 2>&1)
    # 若含异常关键词则返回失败
    if echo "$output" | grep -qE "not loaded|not installed|Service unit not found|RPC probe: failed"; then
        return 1
    fi
    return 0
}

# 综合健康检查（双重验证）
health_check() {
    log "INFO" "开始健康检查..."

    # 1. 文本状态检查
    if ! check_status_text; then
        log "WARN" "❌ gateway status 检测到异常"
        return 1
    fi

    # 2. RPC 连通性检查
    if ! check_health_rpc; then
        log "WARN" "❌ RPC 探测失败（WebSocket 无响应）"
        return 1
    fi

    log "INFO" "✅ Gateway 状态正常，RPC 探测成功"
    return 0
}

# ============================================================
# qwen 智能诊断 + 直接执行修复
# 返回值：0=qwen 修复成功并验证通过，1=失败或跳过
# ============================================================

qwen_diagnose_and_fix() {
    log "INFO" "qwen yolo 代理修复启动..."

    [ -x "$QWEN_CLI" ] || { log "WARN" "qwen CLI 未找到，跳过"; return 1; }

    # ── qwen yolo 模式：最简 prompt + 完整命令参考，让 qwen 自己探索 ──
    local prompt
    prompt='修复 openclaw gateway，让它恢复正常运行。

🔍 检查状态
  openclaw status              显示 Gateway 和通道健康状态
  openclaw status --deep       深度检查（含通道探测）
  openclaw gateway status      Gateway 服务状态 + 探测
  openclaw gateway probe       探测 Gateway 可达性
  openclaw gateway health      获取 Gateway 健康状态
  openclaw health              从运行中的 Gateway 获取健康快照
  openclaw health --json       JSON 格式健康状态

🔧 修复/诊断
  openclaw doctor              健康检查 + 快速修复
  openclaw doctor --fix        自动修复问题
  openclaw doctor --deep       深度扫描系统服务
  openclaw doctor --force      激进修复（覆盖自定义配置）

🚀 启动/停止
  openclaw gateway             前台运行 Gateway
  openclaw gateway --force     强制启动（kill 占用端口的进程）
  openclaw gateway start       启动服务
  openclaw gateway stop        停止服务
  openclaw gateway restart     重启服务
  openclaw gateway install     安装为系统服务

📊 日志/监控
  openclaw logs                实时查看 Gateway 日志
  openclaw gateway usage-cost  获取使用成本摘要'

    log "INFO" "=== 启动 qwen yolo 代理 ==="
    local tmp_log
    tmp_log=$(mktemp /tmp/openclaw-qwen-yolo-XXXXXX.log)

    # -y = yolo 模式，自动批准所有工具调用（Shell/ReadFile/Edit）
    # 在 ~/.openclaw 目录下运行，qwen 可直接 @引用目录内文件
    # macOS 无 GNU timeout，用后台进程 + watcher kill 实现 300s 超时
    (
        cd "$HOME/.openclaw" || exit 1
        "$QWEN_CLI" -y -p "$prompt" &
        _qpid=$!
        ( sleep 300; kill "$_qpid" 2>/dev/null ) &
        _wpid=$!
        wait "$_qpid" 2>/dev/null
        kill "$_wpid" 2>/dev/null
        wait "$_wpid" 2>/dev/null
    ) > "$tmp_log" 2>&1


    local exit_code=$?

    cat "$tmp_log" >> "$LOG_FILE"
    log "INFO" "qwen 代理退出码: ${exit_code}"
    rm -f "$tmp_log"

    # ── 验证修复结果 ─────────────────────────────────────────────
    log "INFO" "验证 RPC 是否恢复..."
    local waited=0
    while [ "$waited" -lt 20 ]; do
        sleep 3; waited=$((waited + 3))
        if check_health_rpc; then
            log "INFO" "✅ qwen yolo 修复成功（${waited}s）"
            return 0
        fi
    done

    log "WARN" "qwen yolo 代理执行后 RPC 仍无响应"
    return 1
}


# ============================================================
# 修复流程
# ============================================================
repair_gateway() {
    log "INFO" "开始修复流程..."

    # 场景 A/B 合并：未安装或未加载 → gateway install（统一处理）
    if ! is_service_installed || ! is_service_loaded; then
        log "WARN" "⚠️  LaunchAgent 未安装/未加载，执行 openclaw gateway install..."
        if openclaw gateway install >> "$LOG_FILE" 2>&1; then
            log "INFO" "install 完成，等待启动..."
            sleep 5
        else
            log "ERROR" "❌ openclaw gateway install 失败"
            send_notification "❌ Gateway 安装失败" "请手动运行: openclaw gateway install"
            return 1
        fi

    # 场景 C：服务已加载但 RPC 无响应 → restart，若 restart 报 not loaded 则降级为 reinstall
    else
        log "WARN" "⚠️  服务已加载但 RPC 无响应，执行 openclaw gateway restart..."
        local restart_out
        restart_out=$(openclaw gateway restart 2>&1 || true)
        echo "$restart_out" >> "$LOG_FILE"
        if echo "$restart_out" | grep -qi "not loaded"; then
            log "WARN" "restart 报告服务未加载，降级为 uninstall + install"
            openclaw gateway uninstall >> "$LOG_FILE" 2>&1 || true
            openclaw gateway install   >> "$LOG_FILE" 2>&1 || true
        fi
        log "INFO" "等待 Gateway 重启（最多 30 秒）..."
        local waited=0
        while [ $waited -lt 30 ]; do
            sleep 5; waited=$((waited + 5))
            if check_health_rpc; then
                log "INFO" "✅ RPC 已恢复（${waited}s）"
                break
            fi
            log "INFO" "仍在等待... (${waited}s)"
        done
    fi

    # 验证修复结果
    if health_check; then
        log "INFO" "✅ Gateway 修复成功"
        send_notification "✅ Gateway 已自动修复" "服务已恢复正常运行"
        return 0
    else
        log "ERROR" "❌ Gateway 修复失败，需要人工介入"
        send_notification "❌ Gateway 修复失败" "自动修复无效，请手动检查"
        return 1
    fi
}

# ============================================================
# 通知
# ============================================================
send_notification() {
    local title="$1" message="$2"

    # macOS 系统通知
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true

    # Telegram（仅在 Gateway 可用时尝试）
    if check_health_rpc; then
        openclaw send --to "$NOTIFICATION_CHAT_ID" "$title

$message" 2>/dev/null || true
    fi
}

# ============================================================
# 主函数
# ============================================================
main() {
    mkdir -p "$LOG_DIR"
    acquire_lock
    trap release_lock EXIT
    rotate_log

    log "INFO" "========== 健康检查 =========="

    if health_check; then
        reset_failures
        exit 0
    fi

    # 健康检查失败：累积计数
    inc_failures
    local fail_count; fail_count=$(get_failures)
    log "WARN" "检测到问题（连续第 ${fail_count} 次），启动 qwen 智能修复..."

    # 优先让 qwen 诊断并执行修复命令
    if qwen_diagnose_and_fix; then
        log "INFO" "✅ qwen 修复成功"
        reset_failures
        send_notification "✅ Gateway 已自动修复" "qwen 智能修复成功（连续失败 ${fail_count} 次后）"
        exit 0
    fi

    # qwen 不可用或修复失败 → 降级到固定修复流程
    log "WARN" "qwen 修复未生效，执行标准修复流程..."
    if repair_gateway; then
        reset_failures
    else
        # 修复失败：静默期内不重复通知
        if ! in_silence_period; then
            send_notification "❌ Gateway 修复失败（连续 ${fail_count} 次）" "自动修复无效，请手动检查"
            mark_notified
        else
            log "INFO" "静默期内，跳过重复通知（连续失败 ${fail_count} 次）"
        fi
    fi
}

# ============================================================
# 命令行接口
# ============================================================
case "${1:-}" in
    status)
        check_status_text && echo "✅ 状态正常" || echo "❌ 状态异常"
        ;;
    health)
        check_health_rpc && echo "✅ RPC 健康" || echo "❌ RPC 不健康"
        ;;
    check)
        health_check && echo "✅ 综合检查通过" || echo "❌ 综合检查失败"
        ;;
    diagnose)
        mkdir -p "$LOG_DIR"
        qwen_diagnose_and_fix
        ;;
    repair)
        mkdir -p "$LOG_DIR"
        acquire_lock
        trap release_lock EXIT
        repair_gateway
        ;;
    *)
        main
        ;;
esac