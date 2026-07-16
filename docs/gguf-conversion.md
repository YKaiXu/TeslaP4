# Hugging Face 模型转换为 GGUF 格式

> 当 Hugging Face 上只有原生权重（safetensors）时，需要转换为 llama.cpp 的 GGUF 格式才能在 Tesla P4 上运行。

## 1. 为什么需要 GGUF

- llama.cpp 原生格式，加载速度比 safetensors 快 5-10 倍
- 支持 Q4_K_M、Q5_K_M 等量化（safetensors 不支持）
- 体积更小（Q4_K_M 后约原始 FP16 的 1/4）

## 2. 前置环境

```bash
# 激活 llama.cpp 自带的虚拟环境
source ~/ai/venv/bin/activate

# 确认转换脚本存在
ls ~/ai/llama.cpp/convert_hf_to_gguf.py
# 期望: /home/yupeng/ai/llama.cpp/convert_hf_to_gguf.py

# 安装依赖
pip install -U "transformers[torch]" gguf
```

## 3. 转换流程

### 3.1 下载 Hugging Face 模型（国内加速）

**Hugging Face 官方（限速严重）**：
```bash
huggingface-cli download Qwen/Qwen3-1.7B \
    --local-dir ~/models/Qwen3-1.7B \
    --include "*.safetensors" "*.json" "*.txt" "tokenizer.*"
```

**ModelScope 镜像（国内推荐）**：
```bash
pip install modelscope
python3 -c "
from modelscope import snapshot_download
snapshot_download('Qwen/Qwen3-1.7B', cache_dir='~/models/Qwen3-1.7B')
"
```

### 3.2 转换为 FP16 GGUF

```bash
cd ~/ai/llama.cpp

python3 convert_hf_to_gguf.py \
    ~/models/Qwen3-1.7B \
    --outfile ~/models/Qwen3-1.7B-F16.gguf \
    --outtype f16
```

**耗时**：1.7B 模型约 2-3 分钟。

### 3.3 量化为 Q4_K_M

```bash
cd ~/ai/llama.cpp/build/bin

./llama-quantize \
    ~/models/Qwen3-1.7B-F16.gguf \
    ~/models/Qwen3-1.7B-Q4_K_M.gguf \
    Q4_K_M
```

**量化级别速查**：

| 级别 | 体积（相对 FP16） | 质量损失 | 推荐 |
|------|-------------------|----------|------|
| Q2_K | 1/5 | 10% | ❌ |
| Q3_K_M | 1/4 | 5% | ⚠️ |
| **Q4_K_M** | 1/3 | ~2% | ✅ |
| Q5_K_M | 2/5 | 1% | ✅ |
| Q6_K | 1/2 | <0.5% | ⚠️（接近 FP16） |
| Q8_0 | 2/3 | 极小 | ❌（省不了多少） |
| F16 | 1 | 0 | ❌（8GB 装不下大模型） |

### 3.4 验证量化后模型

```bash
# 启动测试（CPU 模式快速验证）
./llama-cli -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -p "你好" -n 20 --no-display-prompt
```

期望看到中文回答。

## 4. 一键转换脚本

保存为 `scripts/convert-model.sh`：

```bash
#!/usr/bin/env bash
# 一键转换 HF 模型为 GGUF Q4_K_M
# 用法: ./convert-model.sh <model_id_or_path> [quant]
set -e

MODEL_ID="${1:?请提供模型 ID 或路径，如 Qwen/Qwen3-1.7B}"
QUANT="${2:-Q4_K_M}"
WORK_DIR="${HOME}/models/conv-$$"

# 1. 下载
echo "==> 下载模型: $MODEL_ID"
mkdir -p "$WORK_DIR"
huggingface-cli download "$MODEL_ID" \
    --local-dir "$WORK_DIR" \
    --include "*.safetensors" "*.json" "*.txt" "tokenizer.*"

# 2. 转 GGUF
echo "==> 转换为 FP16 GGUF"
cd ~/ai/llama.cpp
python3 convert_hf_to_gguf.py \
    "$WORK_DIR" \
    --outfile "${WORK_DIR}/model-f16.gguf" \
    --outtype f16

# 3. 量化
OUT_NAME=$(basename "$MODEL_ID")-${QUANT}.gguf
echo "==> 量化到 $QUANT -> ~/models/$OUT_NAME"
./build/bin/llama-quantize \
    "${WORK_DIR}/model-f16.gguf" \
    "${HOME}/models/${OUT_NAME}" \
    "$QUANT"

# 4. 清理
rm -rf "$WORK_DIR"
echo ""
echo "✅ 完成: ~/models/$OUT_NAME"
ls -lh "${HOME}/models/${OUT_NAME}"
```

**用法**：
```bash
chmod +x scripts/convert-model.sh
./scripts/convert-model.sh Qwen/Qwen3-1.7B Q4_K_M
./scripts/convert-model.sh unsloth/Qwen3-1.7B-GGUF Q4_K_M   # 已量化则跳过转换
```

## 5. 常见错误

### 5.1 `KeyError: 'qwen3'` 或类似

**原因**：llama.cpp 版本过旧，不识别新模型架构。
**解决**：
```bash
cd ~/ai/llama.cpp
git pull
cmake --build build --config Release
```

### 5.2 OOM（转换时内存爆掉）

**原因**：F16 转换需要约 2× 模型体积的 RAM。
**解决**：
- 减小 `--split-max-size` 分片
- 或直接用别人预转换好的 GGUF（如 `unsloth/Qwen3-1.7B-GGUF`）

### 5.3 `ModuleNotFoundError: No module named 'gguf'`

```bash
source ~/ai/venv/bin/activate
pip install gguf
```

### 5.4 tokenizer 报错

通常是 `tokenizer.model` 或 `tokenizer.json` 缺失：
```bash
huggingface-cli download <model_id> --include "tokenizer*"
```

## 6. 国内推荐：直接下预量化版本

| 模型 | 预量化仓库 | 备注 |
|------|-----------|------|
| MiniCPM5-1B | ⚠️ 需自行转换（见下方步骤） | [魔搭 OpenBMB/MiniCPM5-1B](https://www.modelscope.cn/models/OpenBMB/MiniCPM5-1B) |
| Qwen3-1.7B | [unsloth/Qwen3-1.7B-GGUF](https://huggingface.co/unsloth/Qwen3-1.7B-GGUF) | 推荐 Q4_K_M |
| Qwen3.5-2B | [bartowski/Qwen3.5-2B-GGUF](https://huggingface.co/bartowski/Qwen3.5-2B-GGUF) | 推荐 Q4_K_M |
| Qwen3-4B | [Qwen/Qwen3-4B-GGUF](https://huggingface.co/Qwen/Qwen3-4B-GGUF) | 推荐 Q4_K_M |

### MiniCPM5-1B 转换步骤

MiniCPM5-1B 目前没有预量化 GGUF，需要自行从 safetensors 转换：

```bash
# 1. 从魔搭下载原始权重（约 2.1 GB）
source ~/ai/venv/bin/activate
modelscope download --model OpenBMB/MiniCPM5-1B --local_dir ~/models/MiniCPM5-1B/

# 2. 转换为 BF16 GGUF（约 2.2 GB）
cd ~/ai/llama.cpp
python convert_hf_to_gguf.py ~/models/MiniCPM5-1B/ \
    --outtype auto \
    --outfile ~/models/MiniCPM5-1B-f16.gguf

# 3. 量化为 Q4_K_M（约 0.65 GB）
./build/bin/llama-quantize \
    ~/models/MiniCPM5-1B-f16.gguf \
    ~/models/MiniCPM5-1B-Q4_K_M.gguf \
    Q4_K_M

# 4. 清理临时文件
rm ~/models/MiniCPM5-1B-f16.gguf
```

国内镜像站：
- ModelScope：搜 `MiniCPM5-1B`（原始权重）
- HF-Mirror.com：`https://hf-mirror.com/openbmb/MiniCPM5-1B`

```bash
# 用 HF-Mirror 下载原始权重
HF_ENDPOINT=https://hf-mirror.com huggingface-cli download \
    openbmb/MiniCPM5-1B --local-dir ~/models/MiniCPM5-1B/
```
