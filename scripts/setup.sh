#! /usr/bin/env bash
# TeslaP4 一键安装脚本
# 流程: 装驱动(若未装) → 编译 llama.cpp → 下载模型 → 安装 systemd 服务
# 用法: sudo ./setup.sh [--model MiniCPM5-1B|Qwen3-1.7B] [--port 8067] [--ctx 131072] [--no-systemd]
set -e

# 默认参数（推荐 MiniCPM5-1B）
MODEL_NAME="MiniCPM5-1B"
LLAMA_PORT="8067"
LLAMA_CTX="131072"
INSTALL_SYSTEMD="yes"
LLAMA_DIR="${HOME}/ai/llama.cpp"
MODELS_DIR="${HOME}/models"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)  MODEL_ID="$2"; shift 2 ;;
        --port)   LLAMA_PORT="$2"; shift 2 ;;
        --ctx)    LLAMA_CTX="$2"; shift 2 ;;
        --no-systemd) INSTALL_SYSTEMD="no"; shift ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

echo -e "${YELLOW}=== TeslaP4 一键安装 ===${NC}"
echo "模型:   $MODEL_ID"
echo "端口:   $LLAMA_PORT"
echo "上下文: $LLAMA_CTX"
echo "systemd: $INSTALL_SYSTEMD"
echo ""

# 1. 检查 GPU
echo -e "${YELLOW}[1/5] 检查 Tesla P4${NC}"
if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo -e "${RED}❌ 未检测到 nvidia-smi${NC}"
    echo "请先安装 NVIDIA 驱动 (参考 docs/driver-install.md)"
    exit 1
fi

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
echo "  ✅ 检测到 GPU: $GPU_NAME"
if [[ "$GPU_NAME" != *"P4"* ]]; then
    echo -e "${YELLOW}  ⚠️ 不是 Tesla P4，但仍可继续${NC}"
fi

# 2. 检查 llama.cpp
echo -e "${YELLOW}[2/5] 编译 llama.cpp${NC}"
if [[ ! -x "${LLAMA_DIR}/build/bin/llama-server" ]]; then
    if [[ -d "$LLAMA_DIR" ]]; then
        echo "  llama.cpp 目录已存在，跳过克隆"
    else
        echo "  克隆 llama.cpp..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
    fi
    cd "$LLAMA_DIR"
    cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61
    cmake --build build --config Release -j$(nproc)
    echo "  ✅ llama.cpp 编译完成"
else
    echo "  ✅ llama.cpp 已编译: ${LLAMA_DIR}/build/bin/llama-server"
fi

# 3. Python venv
echo -e "${YELLOW}[3/5] Python 环境${NC}"
if [[ ! -d "${HOME}/ai/venv" ]]; then
    python3 -m venv "${HOME}/ai/venv"
    source "${HOME}/ai/venv/bin/activate"
    pip install -U pip
    pip install "huggingface_hub[cli]" gguf
    echo "  ✅ venv 创建完成"
else
    echo "  ✅ venv 已存在: ${HOME}/ai/venv"
fi

# 4. 下载/转换模型
echo -e "${YELLOW}[4/5] 准备模型: $MODEL_NAME${NC}"
source "${HOME}/ai/venv/bin/activate"

case "$MODEL_NAME" in
    MiniCPM5-1B)
        TARGET_GGUF="${MODELS_DIR}/MiniCPM5-1B-Q4_K_M.gguf"
        if [[ ! -f "$TARGET_GGUF" ]]; then
            echo "  从魔搭下载 MiniCPM5-1B 原始权重..."
            python3 -c "
from modelscope import snapshot_download
snapshot_download('OpenBMB/MiniCPM5-1B', cache_dir='${MODELS_DIR}/MiniCPM5-1B/')
" 2>&1 | tail -1
            
            HF_DIR=$(find "${MODELS_DIR}/MiniCPM5-1B/" -name "*.safetensors" -exec dirname {} \; | head -1)
            echo "  转换为 GGUF Q4_K_M..."
            cd "$LLAMA_DIR"
            python convert_hf_to_gguf.py "$HF_DIR" \
                --outtype auto \
                --outfile "${MODELS_DIR}/MiniCPM5-1B-f16.gguf"
            ./build/bin/llama-quantize \
                "${MODELS_DIR}/MiniCPM5-1B-f16.gguf" \
                "$TARGET_GGUF" \
                Q4_K_M
            rm -f "${MODELS_DIR}/MiniCPM5-1B-f16.gguf"
        fi
        ;;
    *)
        # Qwen 或其他已有 GGUF 的模型
        TARGET_GGUF="${MODELS_DIR}/${MODEL_NAME}-Q4_K_M.gguf"
        if [[ ! -f "$TARGET_GGUF" ]]; then
            echo "  下载预量化版本: $MODEL_NAME"
            export HF_ENDPOINT="https://hf-mirror.com"
            huggingface-cli download "unsloth/${MODEL_NAME}-GGUF" "${MODEL_NAME}-Q4_K_M.gguf" \
                --local-dir "$MODELS_DIR" 2>&1 | tail -3
        fi
        ;;
esac

if [[ -f "$TARGET_GGUF" ]]; then
    echo "  ✅ 模型就绪: $TARGET_GGUF"
    MODEL_PATH="$TARGET_GGUF"
else
    echo -e "${RED}❌ 模型下载失败${NC}"
    exit 1
fi

# 5. systemd 服务
echo -e "${YELLOW}[5/5] 安装 systemd 服务${NC}"
if [[ "$INSTALL_SYSTEMD" == "yes" ]]; then
    cd "$(dirname "${BASH_SOURCE[0]}")"
    if [[ "$EUID" -ne 0 ]]; then
        SUDO_CMD="sudo"
    else
        SUDO_CMD=""
    fi
    $SUDO_CMD ./install-systemd.sh "$MODEL_PATH" "$LLAMA_PORT" "$LLAMA_CTX"
else
    echo "  跳过 systemd 安装"
fi

echo ""
echo -e "${GREEN}=== 安装完成 ===${NC}"
echo "模型:   $MODEL_PATH"
echo "API:    http://localhost:${LLAMA_PORT}/v1"
echo "OpenCode 配置: 参考 docs/opencode-integration.md"
