#!/usr/bin/env bash
# 一键转换 HF 模型为 GGUF Q4_K_M
# 用法: ./convert-model.sh <model_id_or_path> [quant] [output_dir]
set -e

MODEL_ID="${1:?请提供模型 ID 或路径，如 Qwen/Qwen3-1.7B}"
QUANT="${2:-Q4_K_M}"
OUT_DIR="${3:-${HOME}/models}"
WORK_DIR="$(mktemp -d -t gguf-conv-XXXXXX)"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 工具路径
LLAMA_DIR="${LLAMA_DIR:-${HOME}/ai/llama.cpp}"
LLAMA_QUANTIZE="${LLAMA_DIR}/build/bin/llama-quantize"
CONVERT_SCRIPT="${LLAMA_DIR}/convert_hf_to_gguf.py"

cleanup() {
    if [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

echo -e "${YELLOW}=== GGUF 转换工具 ===${NC}"
echo "模型:   $MODEL_ID"
echo "量化:   $QUANT"
echo "输出:   $OUT_DIR"
echo ""

if [[ ! -f "$CONVERT_SCRIPT" ]]; then
    echo -e "${RED}❌ 转换脚本不存在: $CONVERT_SCRIPT${NC}"
    exit 1
fi

if [[ ! -x "$LLAMA_QUANTIZE" ]]; then
    echo -e "${RED}❌ llama-quantize 不存在: $LLAMA_QUANTIZE${NC}"
    exit 1
fi

# 1. 检测是否已是 GGUF 文件
if [[ "$MODEL_ID" == *.gguf ]]; then
    echo -e "${YELLOW}==> 直接下载 GGUF: $MODEL_ID${NC}"
    mkdir -p "$OUT_DIR"
    BASENAME=$(basename "$MODEL_ID")
    if command -v huggingface-cli >/dev/null 2>&1; then
        huggingface-cli download "$(dirname "$MODEL_ID")" "$BASENAME" \
            --local-dir "$OUT_DIR"
    else
        curl -L -o "${OUT_DIR}/${BASENAME}" \
            "https://huggingface.co/$(dirname "$MODEL_ID")/resolve/main/${BASENAME}"
    fi
    echo -e "${GREEN}✅ 完成: ${OUT_DIR}/${BASENAME}${NC}"
    ls -lh "${OUT_DIR}/${BASENAME}"
    exit 0
fi

# 2. 激活环境
if [[ -f "${HOME}/ai/venv/bin/activate" ]]; then
    source "${HOME}/ai/venv/bin/activate"
fi

# 3. 下载模型
echo -e "${YELLOW}==> 下载模型: $MODEL_ID${NC}"
mkdir -p "$WORK_DIR"

if command -v huggingface-cli >/dev/null 2>&1; then
    # 优先 HF-Mirror 镜像
    export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
    echo "使用 HF_ENDPOINT=$HF_ENDPOINT"
    huggingface-cli download "$MODEL_ID" \
        --local-dir "$WORK_DIR" \
        --include "*.safetensors" "*.json" "*.txt" "tokenizer.*" 2>&1 | tail -5
else
    echo -e "${RED}❌ 需要 huggingface-cli（pip install huggingface_hub）${NC}"
    exit 1
fi

# 4. 转换为 F16 GGUF
echo -e "${YELLOW}==> 转换为 FP16 GGUF${NC}"
cd "$LLAMA_DIR"
python3 "$CONVERT_SCRIPT" \
    "$WORK_DIR" \
    --outfile "${WORK_DIR}/model-f16.gguf" \
    --outtype f16

# 5. 量化
SAFE_NAME=$(echo "$MODEL_ID" | tr '/' '-')
OUT_FILE="${OUT_DIR}/${SAFE_NAME}-${QUANT}.gguf"
mkdir -p "$OUT_DIR"

echo -e "${YELLOW}==> 量化到 $QUANT -> $OUT_FILE${NC}"
"$LLAMA_QUANTIZE" \
    "${WORK_DIR}/model-f16.gguf" \
    "$OUT_FILE" \
    "$QUANT"

echo ""
echo -e "${GREEN}✅ 转换完成${NC}"
ls -lh "$OUT_FILE"
echo ""
echo "下一步:"
echo "  ./run-qwen3-1.7b.sh server 32768 8066   # 启动 API"
echo "  sudo ./install-systemd.sh $OUT_FILE 8066 32768  # 持久化"
