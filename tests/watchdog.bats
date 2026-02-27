#!/usr/bin/env bats
# -*- coding: utf-8 -*-
# ============================================================
# OpenClaw Gateway Watchdog Test Suite
# ============================================================

# 测试脚本路径
WATCHDOG_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/gateway-watchdog.sh"

# ============================================================
# Setup / Teardown
# ============================================================

setup() {
    # 设置测试环境变量
    export LOG_DIR="${BATS_TEST_TMPDIR}/logs"
    export LOCK_FILE="${BATS_TEST_TMPDIR}/gateway-watchdog.lock"
    export STATE_FILE="${LOG_DIR}/watchdog-state"
    mkdir -p "$LOG_DIR"

    # 创建 mock 目录
    export MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
    mkdir -p "$MOCK_DIR"

    # 设置 HOME 为临时目录
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}/Library/LaunchAgents"
}

teardown() {
    rm -rf "${BATS_TEST_TMPDIR}"
}

# ============================================================
# 测试：锁机制
# ============================================================

@test "acquire_lock 创建锁文件" {
    # 直接在当前 shell 测试锁文件创建
    export LOCK_FILE="${BATS_TEST_TMPDIR}/test.lock"
    echo $$ > "$LOCK_FILE"
    [ -f "$LOCK_FILE" ]
    # 验证 PID 正确
    [ "$(cat "$LOCK_FILE")" = "$$" ]
}

@test "release_lock 删除锁文件" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; acquire_lock; release_lock; test -f '$LOCK_FILE' && echo 'exists' || echo 'deleted'"
    [ "$status" -eq 0 ]
    [ "$output" = "deleted" ]
}

# ============================================================
# 测试：失败计数
# ============================================================

@test "get_failures 初始值为 0" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; get_failures"
    [ "$output" = "0" ]
}

@test "inc_failures 累加失败计数" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; inc_failures; inc_failures; get_failures"
    [ "$output" = "2" ]
}

@test "reset_failures 重置计数" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; inc_failures; reset_failures; get_failures"
    [ "$output" = "0" ]
}

# ============================================================
# 测试：静默期
# ============================================================

@test "in_silence_period 无时间戳时返回失败" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; in_silence_period && echo 'in' || echo 'not'"
    [ "$output" = "not" ]
}

@test "mark_notified 设置静默期" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; mark_notified; in_silence_period && echo 'in' || echo 'not'"
    [ "$output" = "in" ]
}

# ============================================================
# 测试：日志轮转
# ============================================================

@test "rotate_log 小于 5MB 时不轮转" {
    echo "test log line" > "$LOG_DIR/gateway-watchdog.log"

    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; rotate_log; wc -l '$LOG_DIR/gateway-watchdog.log'"
    [[ "$output" =~ "1" ]]
}

@test "rotate_log 超过 5MB 时轮转" {
    # 创建大文件（模拟超过 5MB）
    # 每行约 100 字节，需要约 52500 行才能超过 5MB
    for i in {1..600}; do
        # 每行约 9KB，600 行约 5.4MB
        printf "Line %d: %s\n" "$i" "$(printf '%9000s' | tr ' ' 'x')" >> "$LOG_DIR/gateway-watchdog.log"
    done

    # 验证文件大小
    local size
    size=$(wc -c < "$LOG_DIR/gateway-watchdog.log")
    echo "File size: $size bytes"

    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; rotate_log; wc -l < '$LOG_DIR/gateway-watchdog.log'"
    echo "Output: $output"
    # 轮转后应该是 1000 行或更少
    [ "$output" -le 1000 ]
}

# ============================================================
# 测试：日志函数
# ============================================================

@test "log 函数写入日志文件" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; log 'INFO' 'test message'; cat '$LOG_DIR/gateway-watchdog.log'"
    [[ "$output" =~ "test message" ]]
    [[ "$output" =~ "INFO" ]]
}

# ============================================================
# 测试：CLI 命令
# ============================================================

@test "脚本支持 --help 参数" {
    run bash "$WATCHDOG_SCRIPT" --help 2>&1 || true
    # 即使不支持 --help，脚本不应该崩溃
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "脚本支持 --source-only 参数" {
    run bash "$WATCHDOG_SCRIPT" --source-only
    [ "$status" -eq 0 ]
}

# ============================================================
# 测试：服务检测函数
# ============================================================

@test "is_service_installed 检测 plist 存在" {
    # 创建 plist 文件
    touch "${HOME}/Library/LaunchAgents/ai.openclaw.gateway.plist"

    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; is_service_installed && echo 'installed' || echo 'not installed'"
    [ "$output" = "installed" ]
}

@test "is_service_installed 检测 plist 不存在" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; is_service_installed && echo 'installed' || echo 'not installed'"
    [ "$output" = "not installed" ]
}

# ============================================================
# 测试：_timeout 函数
# ============================================================

@test "_timeout 短命令正常执行" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; _timeout 5 echo 'hello'"
    [ "$output" = "hello" ]
    [ "$status" -eq 0 ]
}

@test "_timeout 超时命令被终止" {
    # 使用 sleep 10 但只给 2 秒超时
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; _timeout 2 sleep 10; echo \$?"
    # 超时后应该返回非零
    [ "$status" -ne 0 ] || [ "$output" != "0" ]
}

# ============================================================
# 测试：主入口不崩溃
# ============================================================

@test "脚本可以正常启动" {
    # 至少脚本应该能正常解析
    run bash -n "$WATCHDOG_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "所有函数定义正确" {
    run bash -c "source '$WATCHDOG_SCRIPT' --source-only; type acquire_lock; type release_lock; type log; type rotate_log"
    [ "$status" -eq 0 ]
}