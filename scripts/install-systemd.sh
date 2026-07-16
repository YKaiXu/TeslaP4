#!/usr/bin/env bash
# 安装 llama-server systemd 服务
# 用法: sudo ./install-systemd.sh [模型路径] [端口] [上下文]
set -e

MODEL_PATH="${1:-/home/yupeng/models/Qwen3-1.7B-Q4_K_M.gguf}"
LLAMA_PORT="${2:-8066}"
LLAMA_CTX="${3:-32768}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_BIN="${LLAMA_BIN:-${HOME}/ai/llama.cpp/build/bin/llama-server}"
SERVICE_FILE="/etc/systemd/system/llama-server.service"

# 自动检测用户
RUN_USER="${SUDO_USER:-${USER}}"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== llama-server systemd 安装 ===${NC}"
echo "模型:    $MODEL_PATH"
echo "二进制:  $LLAMA_BIN"
echo "端口:    $LLAMA_PORT"
echo "上下文:  $LLAMA_CTX"
echo "用户:    $RUN_USER"
echo ""

# 校验
if [[ ! -f "$MODEL_PATH" ]]; then
    echo -e "${RED}❌ 模型文件不存在: $MODEL_PATH${NC}"
    echo "   请先下载模型 (参考 docs/gguf-conversion.md)"
    exit 1
fi

if [[ ! -x "$LLAMA_BIN" ]]; then
    echo -e "${RED}❌ llama-server 不存在或不可执行: $LLAMA_BIN${NC}"
    echo "   请先编译 llama.cpp (参考 docs/dependency-setup.md)"
    exit 1
fi

# 生成 unit 文件
echo -e "${YELLOW}==> 生成 systemd 单元: $SERVICE_FILE${NC}"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=llama-server - Qwen3-1.7B on Tesla P4
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

# 启用
systemctl daemon-reload
systemctl enable llama-server.service
systemctl restart  llama-server.service

# 等待启动
echo -e "${YELLOW}==> 等待服务就绪...${NC}"
for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -s "http://localhost:${LLAMA_PORT}/health" | grep -q '"status":"ok"'; then
        echo -e "${GREEN}✅ 服务已就绪${NC}"
        break
    fi
    sleep 2
done

echo ""
echo -e "${GREEN}=== 安装完成 ===${NC}"
echo "状态:   systemctl status llama-server"
echo "日志:   journalctl -u llama-server -f"
echo "健康:   curl http://localhost:${LLAMA_PORT}/health"
echo "模型:   curl http://localhost:${LLAMA_PORT}/v1/models"
echo "测试:   curl http://localhost:${LLAMA_PORT}/v1/chat/completions -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}'"
