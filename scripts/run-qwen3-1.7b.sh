#!/usr/bin/env bash
# Qwen3-1.7B 启动脚本
# 用法: ./run-qwen3-1.7b.sh [cli|server] [ctx_size] [port]
set -e

MODE="${1:-server}"
CTX="${2:-32768}"
PORT="${3:-8066}"

LLAMA_DIR="${HOME}/ai/llama.cpp"
MODEL_PATH="${HOME}/models/Qwen3-1.7B-Q4_K_M.gguf"

if [[ ! -f "$MODEL_PATH" ]]; then
    echo "❌ 模型不存在: $MODEL_PATH"
    echo "   下载命令:"
    echo "   export HF_ENDPOINT=https://hf-mirror.com"
    echo "   huggingface-cli download unsloth/Qwen3-1.7B-GGUF Qwen3-1.7B-Q4_K_M.gguf --local-dir ~/models/"
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
