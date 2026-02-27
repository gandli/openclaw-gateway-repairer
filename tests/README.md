# OpenClaw Gateway Watchdog Tests

基于 [bats-core](https://github.com/bats-core/bats-core) 的自动化测试套件。

## 安装

```bash
# macOS
brew install bats-core

# Linux
npm install -g bats
```

## 运行测试

```bash
# 运行所有测试
bats tests/

# 运行单个测试文件
bats tests/watchdog.bats

# 详细输出
bats --tap tests/
```

## 测试覆盖

| 模块 | 测试内容 |
|------|----------|
| 辅助函数 | `_timeout` 超时终止 |
| 状态检查 | `check_status_text`, `check_health_rpc` |
| 服务检测 | `is_service_installed`, `is_service_loaded` |
| 锁机制 | `acquire_lock`, `release_lock` 并发保护 |
| 失败计数 | `inc_failures`, `reset_failures`, 静默期 |
| 日志轮转 | 超过 5MB 时保留最近 1000 行 |
| CLI | `status`, `health`, `check` 命令 |
| 主流程 | 健康检查成功/失败路径 |

## Mock 策略

测试使用环境变量控制 mock 行为：

- `MOCK_HEALTH_FAIL=1` — 模拟 RPC 健康检查失败
- `MOCK_STATUS_FAIL=1` — 模拟状态检查失败
- `MOCK_PLIST_EXISTS=1` — 模拟 plist 文件存在
- `MOCK_SERVICE_LOADED=1` — 模拟服务已加载
- `MOCK_RESTART_FAIL=1` — 模拟重启失败

## CI/CD

GitHub Actions 自动运行测试（见 `.github/workflows/test.yml`）。