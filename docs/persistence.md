# 持久化部署：systemd 服务 + 开机自启

> 本文说明如何让 llama-server 以 systemd 服务形式运行，开机自启，崩溃自动重启。

## 1. 部署位置约定

| 项目 | 路径（推荐） |
|------|-------------|
| 模型文件 | `/home/yupeng/models/MiniCPM5-1B-Q4_K_M.gguf` |
| llama.cpp 构建 | `/home/yupeng/ai/llama.cpp/build/bin/llama-server` |
| systemd 单元 | `/etc/systemd/system/llama-server.service` |
| 日志 | `journalctl -u llama-server` |
| 配置 | `/etc/systemd/system/llama-server.service` 内的 `Environment=` |

> 所有路径可按需修改，但需同步更新 systemd 单元文件。

---

## 2. systemd 服务文件

### 2.1 创建单元文件

```bash
sudo tee /etc/systemd/system/llama-server.service > /dev/null <<'EOF'
[Unit]
Description=llama-server - MiniCPM5-1B on Tesla P4
After=network-online.target nvidia-persistenced.service
Wants=network-online.target

[Service]
Type=simple
User=yupeng
Group=yupeng

# 模型路径
Environment=LLAMA_MODEL=/home/yupeng/models/MiniCPM5-1B-Q4_K_M.gguf
# 监听端口
Environment=LLAMA_PORT=8067
# 上下文长度（128K 是 MiniCPM5-1B 的训练上限）
Environment=LLAMA_CTX=131072

ExecStart=/home/yupeng/ai/llama.cpp/build/bin/llama-server \
    -m ${LLAMA_MODEL} \
    -ngl 99 \
    -c ${LLAMA_CTX} \
    --host 0.0.0.0 \
    --port ${LLAMA_PORT} \
    --jinja \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    -np 1

# 崩溃自动重启
Restart=on-failure
RestartSec=5

# 资源限制
LimitNOFILE=65536
LimitMEMLOCK=infinity

# 等待 NVIDIA 驱动就绪
ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5; do nvidia-smi >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'

[Install]
WantedBy=multi-user.target
EOF
```

### 2.2 关键参数解释

| 参数 | 作用 |
|------|------|
| `After=nvidia-persistenced.service` | 等待 NVIDIA 持久化守护进程就绪 |
| `Environment=LLAMA_*` | 用变量管理端口/模型路径，方便切换 |
| `--jinja` | 启用 Jinja chat template（**工具调用必须**） |
| `--cache-type-k q8_0` | K 缓存量化为 Q8，省显存 |
| `--cache-type-v q8_0` | V 缓存量化为 Q8，省显存 |
| `-np 1` | 单并发，避免 OOM |
| `Restart=on-failure` | 失败自动重启 |
| `ExecStartPre=...nvidia-smi` | 启动前确认驱动可用，避免开机时序问题 |

---

## 3. 启用与操作

### 3.1 重载 + 启动

```bash
sudo systemctl daemon-reload
sudo systemctl enable llama-server.service   # 开机自启
sudo systemctl start  llama-server.service
```

### 3.2 状态查询

```bash
# 服务状态
systemctl status llama-server

# 健康检查
curl http://localhost:8067/health

# 实时日志
journalctl -u llama-server -f

# 最近 50 行日志
journalctl -u llama-server -n 50 --no-pager
```

### 3.3 切换模型

只改模型路径，**无需改服务文件**：

```bash
# 临时切换（立即生效）
sudo systemctl set-environment LLAMA_MODEL=/home/yupeng/models/Qwen3-1.7B-Q4_K_M.gguf
sudo systemctl restart llama-server

# 永久切换（写入 override.conf）
sudo systemctl edit llama-server
# 弹出编辑器，写入：
# [Service]
# Environment=LLAMA_MODEL=/path/to/new-model.gguf
```

### 3.4 调整上下文长度

```bash
sudo systemctl set-environment LLAMA_CTX=65536
sudo systemctl restart llama-server
```

---

## 4. 显存调优

### 4.1 MiniCPM5-1B 显存占用（推荐配置）

| 配置 | 显存占用 | 状态 |
|------|---------|------|
| 1B + 128K + Q8 KV | **2.6 GB** | ✅ 极省 |
| 1B + 64K + Q8 KV | **1.6 GB** | ✅ 更省 |
| 1B + 32K + Q8 KV | **1.1 GB** | ✅ 最省 |

MiniCPM5-1B 显存占用极低，几乎不会 OOM。

### 4.2 OOM 应急

如果使用其他模型（如 Qwen3-1.7B / Qwen3-4B）时 OOM：

**步骤 1：降上下文**
```bash
sudo systemctl set-environment LLAMA_CTX=16384
sudo systemctl restart llama-server
```

**步骤 2：加 KV 量化**（默认已加）

**步骤 3：换更小模型**
```bash
sudo systemctl set-environment LLAMA_MODEL=/home/yupeng/models/MiniCPM5-1B-Q4_K_M.gguf
sudo systemctl restart llama-server
```

---

## 5. 开机自启验证

```bash
# 重启系统
sudo reboot

# 重新登录后
systemctl is-active llama-server
# 期望: active

curl http://localhost:8067/health
# 期望: {"status":"ok"}
```

如果重启后没自启：

```bash
# 1. 确认已 enable
systemctl is-enabled llama-server
# 期望: enabled

# 2. 查看为什么没起来
journalctl -u llama-server -b --no-pager
# 常见原因：
#   - nvidia-persistenced 没起来 → After 顺序问题
#   - 模型文件路径错 → 绝对路径写死
#   - nvidia-smi 不可用 → 驱动没装好
```

---

## 6. 一键安装脚本

`scripts/install-systemd.sh`（项目自带）：

```bash
#!/usr/bin/env bash
# 安装 llama-server systemd 服务
# 用法: sudo ./install-systemd.sh [模型路径] [端口] [上下文]
set -e

MODEL_PATH="${1:-/home/yupeng/models/MiniCPM5-1B-Q4_K_M.gguf}"
LLAMA_PORT="${2:-8067}"
LLAMA_CTX="${3:-131072}"
LLAMA_BIN="$(dirname $(realpath $0))/../llama.cpp/build/bin/llama-server"
SERVICE_FILE="/etc/systemd/system/llama-server.service"

# 自动检测用户
RUN_USER="${SUDO_USER:-$USER}"

if [[ ! -f "$MODEL_PATH" ]]; then
    echo "❌ 模型文件不存在: $MODEL_PATH"
    echo "   请先下载模型 (见 docs/model-selection.md)"
    exit 1
fi

if [[ ! -x "$LLAMA_BIN" ]]; then
    echo "❌ llama-server 不存在: $LLAMA_BIN"
    echo "   请先编译 llama.cpp (见 docs/dependency-setup.md)"
    exit 1
fi

echo "📝 生成 systemd 单元: $SERVICE_FILE"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=llama-server - MiniCPM5-1B on Tesla P4
After=network-online.target nvidia-persistenced.service
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER

Environment=LLAMA_MODEL=$MODEL_PATH
Environment=LLAMA_PORT=$LLAMA_PORT
Environment=LLAMA_CTX=$LLAMA_CTX

ExecStart=$LLAMA_BIN \\
    -m \${LLAMA_MODEL} \\
    -ngl 99 \\
    -c \${LLAMA_CTX} \\
    --host 0.0.0.0 \\
    --port \${LLAMA_PORT} \\
    --jinja \\
    --cache-type-k q8_0 \\
    --cache-type-v q8_0 \\
    -np 1

Restart=on-failure
RestartSec=5
LimitNOFILE=65536
LimitMEMLOCK=infinity

ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5; do nvidia-smi >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable llama-server.service
systemctl restart  llama-server.service

echo ""
echo "✅ 服务已启动"
echo "   状态: systemctl status llama-server"
echo "   日志: journalctl -u llama-server -f"
echo "   健康: curl http://localhost:${LLAMA_PORT}/health"
```

### 用法

```bash
# 默认参数（MiniCPM5-1B, 端口 8067, 128K 上下文）
sudo ./scripts/install-systemd.sh

# 自定义模型/端口/上下文
sudo ./scripts/install-systemd.sh \
    /home/yupeng/models/Qwen3-1.7B-Q4_K_M.gguf \
    8066 \
    32768
```

---

## 7. 卸载

```bash
sudo systemctl stop    llama-server
sudo systemctl disable llama-server
sudo rm /etc/systemd/system/llama-server.service
sudo systemctl daemon-reload
```
