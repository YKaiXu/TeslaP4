# Tesla P4 踩坑与技巧大全

> 基于真实环境（Ubuntu 26.04, Tesla P4 8GB）的实战经验总结。

## 🚨 硬件避坑

### 1. 散热（最重要）

**问题**：Tesla P4 是被动散热卡，无内置风扇。在普通台式机箱中，没有风道直吹会在 5 分钟内达到 85°C+ 并降频。

**解决方案**：
```bash
# 监控温度
watch -n 1 nvidia-smi

# 物理散热方式：
# 1. 使用 12cm 高风压风扇直接对准 P4 散热片吹
# 2. 使用服务器机箱（1U/2U）自带风道
# 3. 3D 打印导风罩 + 涡轮风扇
# 4. 确保稳定的气流路径，不要有障碍物阻挡
```

**正常温度范围**：
- 空闲：35-45°C
- 推理负载：55-70°C
- 警戒线：>85°C（开始降频）

### 2. 电源

- P4 TDP 为 75W，PCIe 插槽供电足够
- 多卡使用需注意主板 PCIe 供电能力
- 不需要外接 6-pin/8-pin 电源

### 3. PCIe 兼容性

- P4 支持 PCIe 3.0 x16
- 在 PCIe 4.0/5.0 插槽上兼容（向下兼容）
- 某些旧主板可能需要更新 BIOS
- **不要**在 P4 所在插槽附近安装其他大卡（阻碍风道）

## 🚨 软件避坑

### 1. 框架选择

```
❌ vLLM - Pascal 架构不支持（2025年起放弃 CC 6.1）
❌ SGLang - Pascal 架构不支持
❌ HuggingFace Transformers - 可以运行，但速度极慢（<5 t/s）
❌ TensorRT-LLM - 需要现代 GPU
✅ llama.cpp - **唯一推荐选项**
✅ Ollama - 基于 llama.cpp，简化版
```

### 2. 编译 llama.cpp 时必须指定架构

```bash
# ❌ 错误：默认编译可能不含 sm_61，导致 CUDA 后端不可用
cmake -B build -DGGML_CUDA=ON

# ✅ 正确：明确指定 Tesla P4 的架构
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61
```

### 3. Flash Attention 不可用

Pascal 架构不支持 Flash Attention（需要 CC 7.0+）。

解决方案：
- 限制上下文长度（推荐 ≤32K tokens）
- 使用 TurboQuant 分支（社区 fork，支持 Pascal 的 KV cache 压缩）
  ```bash
  git clone https://github.com/TheTom/llama-cpp-turboquant
  cd llama-cpp-turboquant
  cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61
  ```

### 4. 显存不足 (OOM)

**现象**：
```
ggml_backend_cuda_buffer_type_alloc_buffer: allocating 3584.00 MiB on device 0: cudaMalloc failed: out of memory
```

**排查**：
```bash
nvidia-smi --query-gpu=memory.used --format=csv,noheader
journalctl -u llama-server -n 30 --no-pager
```

**解决**：
1. **首选：开启 KV Cache 量化**
   ```bash
   --cache-type-k q8_0 --cache-type-v q8_0
   ```
   32K 上下文从 3.5GB 降到 2.0GB。

2. 减小上下文长度（`-c 16384` 代替 `-c 32768`）
3. 减少 GPU 层数（`-ngl 80` 代替 `-ngl 99`）
4. 使用更小模型（Qwen3-1.7B 代替 Qwen3-4B）
5. 关闭其他占用显存的进程

### 5. Xorg 冲突

**问题**：如果 P4 是唯一 GPU 且被 Xorg 占用，llama.cpp 可能无法获得全部显存

**解决**：
```bash
sudo lsof /dev/nvidia*
# 杀掉占用进程
```

### 6. 国内下载 Hugging Face 慢/失败

**现象**：`huggingface-cli download` 卡死或 `HTTPError 403`

**解决**：
```bash
# 方法 1：HF-Mirror 镜像
export HF_ENDPOINT=https://hf-mirror.com
huggingface-cli download unsloth/Qwen3-1.7B-GGUF Qwen3-1.7B-Q4_K_M.gguf --local-dir ~/models/

# 方法 2：ModelScope（更稳）
pip install modelscope
python3 -c "from modelscope import snapshot_download; snapshot_download('unsloth/Qwen3-1.7B-GGUF', cache_dir='~/models/')"

# 方法 3：wget + 手动重试
wget -c <hf_url> -O ~/models/model.gguf
# -c 支持断点续传
```

### 7. systemd 服务启动顺序问题

**现象**：重启系统后 llama-server 启动失败，journal 显示 `Failed with result 'core-dump'` 或 `nvidia-smi not found`

**解决**：在 unit 文件中加 `ExecStartPre`：
```ini
[Service]
ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5; do nvidia-smi >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'
After=nvidia-persistenced.service
```

### 8. 工具调用失败：模型看不到工具定义

**现象**：调 `/v1/chat/completions` 加 `tools` 参数，模型输出普通文本而非 `tool_calls` JSON

**根因**：llama.cpp 默认 chat template 不能正确渲染工具定义。

**解决**：启动时加 `--jinja`：
```bash
llama-server --jinja -m model.gguf ...
```

验证方法：
```bash
curl http://localhost:8066/v1/chat/completions -d '{
  "messages": [{"role":"user","content":"北京天气"}],
  "tools": [{"type":"function","function":{"name":"get_weather","parameters":{...}}}]
}'
# 期望返回 tool_calls 字段
```

### 9. MiniCPM5-1B 思考模式

MiniCPM5-1B 也支持混合推理（`<think>` 模式），默认开启。

**现象**：请求返回 content 为空，只有 `reasoning_content` 字段有内容。

**解决**：在请求时加 `chat_template_kwargs`：
```json
{
  "chat_template_kwargs": {"enable_thinking": false}
}
```

或者在 llama-server 启动时用定制的 chat template 文件（见下方）。

### 10. Qwen3 思考模式把 token 用光

**现象**：模型输出 `reasoning_content` 占满 500 tokens 没产出实际内容，`finish_reason: "length"`

**根因**：Qwen3 默认开启 thinking mode，把所有 token 用于内部推理。

**解决**：在 system prompt 加 `/no_think`：
```text
/no_think
```

或在 OpenCode 系统提示词里设置。

### 10. mlock 错误（Qwen3.5-2B 24K 上下文）

**现象**：
```
cannot mlock 4194304 bytes: Cannot allocate memory
```

**根因**：默认 `--mlock` 强制锁内存，24K 上下文超过系统可用内存。

**解决**：
- 降回 16K 上下文
- 或启动加 `--no-mlock`

---

## ⚡ 性能优化技巧

### 1. 关键启动参数

| 参数 | 作用 | 推荐值 |
|------|------|--------|
| `-ngl 99` | 全部层卸载到 GPU | 99 |
| `-c` | 上下文窗口 | 16384-32768 |
| `--mlock` | 锁定内存防交换 | 默认开（如报错则关） |
| `--threads` | CPU 线程数 | CPU 物理核心数 |
| `--jinja` | 启用 Jinja chat template | **必加**（工具调用） |
| `--cache-type-k q8_0` | K 缓存量化 | **长上下文必加** |
| `--cache-type-v q8_0` | V 缓存量化 | **长上下文必加** |
| `-np 1` | 并发数 | 1（避免 OOM） |

### 2. 上下文长度与显存关系（1.7B 模型）

| 上下文 | FP16 KV | Q8 KV |
|--------|---------|-------|
| 4K | 0.4 GB | 0.2 GB |
| 8K | 0.8 GB | 0.5 GB |
| 16K | 1.7 GB | 1.0 GB |
| 32K | 3.5 GB | 2.0 GB |

### 3. 不同量化级别的显存占用

| 模型 | Q4_K_M | Q3_K_M | Q2_K |
|------|--------|--------|------|
| MiniCPM5-1B | **0.65 GB** | 0.5 GB | 0.4 GB |
| Qwen3-1.7B | **1.1 GB** | 0.9 GB | 0.7 GB |
| Qwen3.5-2B | **1.2 GB** | 1.0 GB | 0.8 GB |
| Qwen3-4B | 3.9 GB | 3.0 GB | 2.2 GB |

---

## 📊 性能参考

### MiniCPM5-1B Q4_K_M on Tesla P4（实测 2026-07-15）🔥 推荐

| 指标 | 数值 |
|------|------|
| 配置 | 128K 上下文 + Q8 KV Cache + 1 并发 |
| Prompt 处理速度 | 1000+ t/s |
| 文本生成速度 | **90-101 t/s** |
| 模型加载时间 | ~3 秒 |
| 首 token 延迟 | < 200 ms |
| GPU 显存占用 | **2.6 GB** / 8 GB |
| GPU 温度 | 44°C (空闲) / 60-68°C (负载) |
| 工具调用 | ✅ 7/7 场景完美通过 |

### Qwen3-1.7B Q4_K_M on Tesla P4（实测 2026-07-15）

| 指标 | 数值 |
|------|------|
| 配置 | 32K 上下文 + Q8 KV Cache + 1 并发 |
| Prompt 处理速度 | 668 t/s |
| 文本生成速度 | **65.8 t/s** |
| 模型加载时间 | ~3 秒 |
| 首 token 延迟 | < 200 ms |
| GPU 显存占用 | 6.47 GB / 7.68 GB |
| GPU 温度 | 44°C (空闲) / 60-68°C (负载) |
| 系统内存占用 | ~2.8 GB |
| 工具调用 | ✅ OpenAI 格式 JSON |

### Qwen3.5-2B Q4_K_M on Tesla P4

| 指标 | 数值 |
|------|------|
| 上下文 | 16K（24K+ 会 mlock 失败） |
| Prompt 处理速度 | 1215 t/s |
| 文本生成速度 | 67 t/s |
| 显存占用 | 2.9 GB / 7.5 GB |

### Qwen3-4B Q4_K_M on Tesla P4

| 指标 | 数值 |
|------|------|
| 上下文 | 8K（32K OOM） |
| 文本生成速度 | ~35 t/s |
| 显存占用 | 5.5 GB / 7.5 GB |

---

## 🔧 故障排除速查

```bash
# CUDA 不可用
ggml_cuda_init: found 0 CUDA devices
# -> 检查 nvidia-smi, 确认驱动安装
# -> 重新编译: cmake -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61

# OOM 错误
CUDA error: out of memory
# -> 加 --cache-type-k q8_0 --cache-type-v q8_0
# -> 降低 -c 到 16384
# -> 使用更小模型

# 编译错误
nvcc fatal: Unsupported gpu architecture 'compute_61'
# -> 检查 CUDA Toolkit 版本（需 ≥ 11.0）
# -> nvcc --version

# 模型加载报错
unknown model architecture: 'qwen3.5'
# -> llama.cpp 版本过旧，需要 ≥ b10020
# -> cd ~/ai/llama.cpp && git pull && cmake --build build

# 模型一直"思考"不输出
finish_reason: "length" + reasoning_content 占满 tokens
# -> system prompt 加 /no_think

# 工具调用没触发
模型返回普通文本而非 tool_calls
# -> 启动时加 --jinja
# -> 确认请求的 tools 数组格式正确

# mlock 错误
cannot mlock N bytes: Cannot allocate memory
# -> 启动加 --no-mlock
# -> 或降低 -c 上下文
```

## 🔗 相关文档

- [驱动安装](driver-install.md) - 驱动 + CUDA Toolkit
- [依赖环境](dependency-setup.md) - llama.cpp 编译
- [模型选型](model-selection.md) - 推荐模型与对比
- [GGUF 转换](gguf-conversion.md) - HF 模型转 GGUF
- [持久化部署](persistence.md) - systemd 服务
- [OpenCode 接入](opencode-integration.md) - OpenCode 配置
