#!/usr/bin/env bash
# Qwen3.5-2B 启动脚本（向后兼容，推荐改用 run-qwen3-1.7b.sh）
# 用法: ./run-qwen35.sh [cli|server] [ctx_size] [port]
set -e

MODE="${1:-server}"
CTX="${2:-16384}"
PORT="${3:-8066}"

LLAMA_DIR="${HOME}/ai/llama.cpp"
MODEL_PATH="${HOME}/models/Qwen3.5-2B-Q4_K_M.gguf"

if [[ ! -f "$MODEL_PATH" ]]; then
    echo "❌ 模型不存在: $MODEL_PATH"
    exit 1
fi

case "$MODE" in
    cli)
        "$LLAMA_DIR/build/bin/llama-cli" \
            -m "$MODEL_PATH" -ngl 99 -c "$CTX" --jinja -cnv
        ;;
    server)
        "$LLAMA_DIR/build/bin/llama-server" \
            -m "$MODEL_PATH" -ngl 99 -c "$CTX" --jinja -np 1 \
            --host 0.0.0.0 --port "$PORT"
        ;;
    *)
        echo "用法: $0 [cli|server] [ctx] [port]"
        exit 1
        ;;
esac
