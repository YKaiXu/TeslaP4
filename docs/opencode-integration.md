# OpenCode 接入本地 llama-server 完整指南

> 本文档说明如何把部署在 Tesla P4 上的 llama-server 接入到 OpenCode 编程代理，覆盖**本机**和**局域网**两种场景。

## 1. 前置条件

- Tesla P4 已完成模型部署（推荐 MiniCPM5-1B，参考 [model-selection.md](model-selection.md)）
- `llama-server` 正在监听 `0.0.0.0:8067`
- OpenAI 兼容 API 已启用（llama-server 默认行为）

**验证服务可用**：
```bash
curl http://localhost:8067/health
# 期望: {"status":"ok"}

curl http://localhost:8067/v1/models
# 期望: {"object":"list","data":[{"id":"...MiniCPM5-1B...",...}]}
```

---

## 2. 获取本机 IP（局域网场景）

OpenCode 不在本机时需要本机内网 IP：

```bash
ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v 127.0.0.1
```

假设本机 IP 为 `192.168.10.20`，下文以此为例。

---

## 3. OpenCode 配置文件

### 3.1 配置文件位置

| 用途 | 路径 |
|------|------|
| 用户级 | `~/.config/opencode/opencode.json` |
| 授权文件 | `~/.local/share/opencode/auth.json` |

### 3.2 完整配置示例（推荐）

**这个配置固定后永远不需要改**——换模型时只在 P4 主机上改 llama-server 的启动命令即可。

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "本地 P4 模型",
      "options": {
        "baseURL": "http://192.168.10.20:8067/v1"
      },
      "models": {
        "default": {
          "id": "local-model",
          "name": "P4 本地模型",
          "limit": {
            "context": 131072,
            "output": 4096
          }
        }
      }
    }
  }
}
```

> 请把 `192.168.10.20` 替换为你的 P4 主机实际 IP。

### 3.3 本机版（OpenCode 直接跑在 P4 主机上）

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "本地 P4 模型",
      "options": {
        "baseURL": "http://localhost:8067/v1"
      },
      "models": {
        "default": {
          "id": "local-model",
          "name": "P4 本地模型",
          "limit": {
            "context": 131072,
            "output": 4096
          }
        }
      }
    }
  }
}
```

### 3.4 鉴权文件（auth.json）

llama-server 默认无 API Key，填占位符即可：

```json
{
  "local": { "type": "api", "key": "sk-no-auth-needed" }
}
```

> 生产环境建议在 llama-server 启动时加 `--api-key <your-secret>`，并把同样字符串填到这里。

---

## 4. MiniCPM5-1B 的思考模式

MiniCPM5-1B 支持混合推理（`<think>` 模式），默认开启。

**如果 OpenCode 回复为空（只看到 reasoning_content）**，需要在 OpenCode 系统提示里关闭思考模式：

```text
You are a coding assistant running on Tesla P4.
When responding, never use thinking/reasoning mode.
Always respond directly.
```

或者在 llama-server 启动时用一个定制的 chat template 文件（参考 [pitfalls-and-tips.md](pitfalls-and-tips.md#9-minicpm5-1b-思考模式)）。

---

## 5. 上下文与输出设置

### 5.1 上下文

llama-server 启动时设了 `-c 131072`（128K），OpenCode 端不需要重复配置，**模型上下文以服务端为准**。

### 5.2 输出上限

MiniCPM5-1B 单次输出约 1500 tokens 自动收尾（模型主动结束，非截断）。`output: 4096` 只是一个安全上限。

---

## 6. 验证流程

### 6.1 启动 OpenCode

```bash
opencode
```

### 6.2 让 OpenCode 选模型

按 `Ctrl+P` → **Switch model** → 选择 `P4 本地模型`。

### 6.3 测试对话

```
写一个 Python 脚本，列出当前目录所有 .py 文件并显示行数
```

预期：OpenCode 调用工具读目录，然后生成 Python 代码。

### 6.4 测试工具调用

```
北京今天天气怎么样？
```

如果 OpenCode 配置了天气工具，应触发 tool_call 请求，返回 `get_weather({"city":"北京"})`。

---

## 7. 日常使用性能参考（MiniCPM5-1B）

| 指标 | 数值 |
|------|------|
| **生成速度** | 90-101 t/s |
| **上下文** | 128K |
| **显存占用** | 2.6 GB / 8 GB |
| **工具调用准确率** | ~100% |
| **单次输出** | ~1500 tokens |

---

## 8. 常见问题

### Q1: OpenCode 报 "connection refused"

**排查**：
```bash
# 服务端
systemctl status llama-server
curl http://localhost:8067/health

# 客户端
curl http://192.168.10.20:8067/health
```

- 服务没启动 → `systemctl start llama-server`
- 局域网不通 → 检查防火墙 `sudo ufw status` 或 `sudo iptables -L`
- baseURL 写错 → 必须以 `/v1` 结尾

### Q2: OpenCode 报 "401 Unauthorized"

llama-server 启动了 `--api-key` 但 OpenCode 没传：
- 删除 `--api-key` 参数（最简方案）
- 或在 `auth.json` 里填入同样的 key

### Q3: 模型回复为空（只有 reasoning_content）

**原因**：MiniCPM5-1B 默认开启思考模式。
**解决**：在 OpenCode 系统提示里加"不要使用思考模式，直接回答"。

### Q4: 局域网访问很慢

- 确认走的是千兆网（`iperf3` 测试）
- 避免 OpenCode 走 VPN 隧道
- 检查 llama-server 是否被限速（默认无限制）

### Q5: 显存 OOM

MiniCPM5-1B 仅 2.6 GB 显存占用，几乎不会 OOM。如遇 OOM：
- 确认 `--cache-type-k q8_0 --cache-type-v q8_0` 已加
- 降低 `-c` 到 65536
- 检查是否还有其他进程占用显存

---

## 9. 完整一键配置脚本

把下面保存为 `setup-opencode.sh`：

```bash
#!/usr/bin/env bash
# 部署到 OpenCode 用户配置目录
set -e

OPENCODE_DIR="${HOME}/.config/opencode"
AUTH_DIR="${HOME}/.local/share/opencode"
mkdir -p "$OPENCODE_DIR" "$AUTH_DIR"

# 检测本机 IP
LOCAL_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v 127.0.0.1 | head -1)

cat > "$OPENCODE_DIR/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "P4 本地模型",
      "options": { "baseURL": "http://${LOCAL_IP}:8067/v1" },
      "models": {
        "default": {
          "id": "local-model",
          "name": "P4 本地模型",
          "limit": { "context": 131072, "output": 4096 }
        }
      }
    }
  }
}
EOF

cat > "$AUTH_DIR/auth.json" <<EOF
{
  "local": { "type": "api", "key": "sk-no-auth-needed" }
}
EOF

echo "✅ OpenCode 配置完成: $OPENCODE_DIR/opencode.json"
echo "   baseURL: http://${LOCAL_IP}:8067/v1"
```

运行：

```bash
chmod +x setup-opencode.sh
./setup-opencode.sh
```
