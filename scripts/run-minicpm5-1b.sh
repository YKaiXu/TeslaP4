#!/usr/bin/env bash
# MiniCPM5-1B 启动脚本
# 用法: ./run-minicpm5-1b.sh [cli|server] [ctx_size] [port]
set -e

MODE="${1:-server}"
CTX="${2:-131072}"
PORT="${3:-8067}"

LLAMA_DIR="${HOME}/ai/llama.cpp"
MODEL_PATH="${HOME}/models/MiniCPM5-1B-Q4_K_M.gguf"

if [[ ! -f "$MODEL_PATH" ]]; then
    echo "❌ 模型不存在: $MODEL_PATH"
    echo "   下载/转换命令:"
    echo "   # 方式一：从魔搭下载原始权重"
    echo "   modelscope download --model OpenBMB/MiniCPM5-1B --local_dir ~/models/MiniCPM5-1B/"
    echo ""
    echo "   # 方式二：转换 + 量化（需要 llama.cpp）"
    echo "   cd ~/ai/llama.cpp"
    echo "   source ~/ai/venv/bin/activate"
    echo "   python convert_hf_to_gguf.py ~/models/MiniCPM5-1B/ \\"
    echo "       --outtype auto \\"
    echo "       --outfile ~/models/MiniCPM5-1B-f16.gguf"
    echo "   ./build/bin/llama-quantize \\"
    echo "       ~/models/MiniCPM5-1B-f16.gguf \\"
    echo "       ~/models/MiniCPM5-1B-Q4_K_M.gguf \\"
    echo "       Q4_K_M"
    exit 1
fi

case "$MODE" in
    cli)
        echo "==> 启动交互式对话 (上下文 $CTX)"
        "$LLAMA_DIR/build/bin/llama-cli" \
            -m "$MODEL_PATH" \
            -ngl 99 \
            -c "$CTX" \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --jinja \
            -cnv
        ;;
    server)
        echo "==> 启动 API 服务 (端口 $PORT, 上下文 $CTX)"
        "$LLAMA_DIR/build/bin/llama-server" \
            -m "$MODEL_PATH" \
            -ngl 99 \
            -c "$CTX" \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --jinja \
            -np 1 \
            --host 0.0.0.0 \
            --port "$PORT"
        ;;
    *)
        echo "用法: $0 [cli|server] [ctx] [port]"
        exit 1
        ;;
esac
