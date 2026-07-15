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

**现象**：启动时出现 `CUDA OOM` 或 `out of memory`

**排查**：
```bash
# 查看显存使用
nvidia-smi

# 确认当前使用量
nvidia-smi --query-gpu=memory.used --format=csv,noheader
```

**解决**：
- 使用更低量化的模型（Q3_K_M 代替 Q4_K_M）
- 减小上下文长度（`-c 4096` 代替 `-c 8192`）
- 减少 GPU 层数（`-ngl 80` 代替 `-ngl 99`）
- 关闭其他占用显存的进程

### 5. Xorg 冲突

**问题**：如果 P4 是唯一 GPU 且被 Xorg 占用，llama.cpp 可能无法获得全部显存

**解决**：
```bash
# 添加启动参数
--no-warmup

# 或者查看 Xorg 是否占用
sudo lsof /dev/nvidia*
```

## ⚡ 性能优化技巧

### 1. 关键启动参数

| 参数 | 作用 | 推荐值 |
|------|------|--------|
| `-ngl 99` | 全部层卸载到 GPU | 99 |
| `-c` | 上下文窗口 | 4096-8192 |
| `--mlock` | 锁定内存防交换 | 启用 |
| `--threads` | CPU 线程数 | CPU 物理核心数 |

### 2. 上下文长度与显存关系

| 上下文长度 | 额外显存消耗（2B 模型） |
|-----------|----------------------|
| 4K | ~0.5 GB |
| 8K | ~1 GB |
| 16K | ~2 GB |
| 32K | ~4 GB（可能 OOM） |

### 3. 不同量化级别的显存占用（预估）

| 模型 | Q4_K_M | Q3_K_M | Q2_K |
|------|--------|--------|------|
| Qwen3.5-2B | **2.9 GB** | 2.2 GB | 1.7 GB |
| Qwen3-4B | 5.5 GB | 4.2 GB | 3.2 GB |

## 📊 性能参考

### Qwen3.5-2B Q4_K_M on Tesla P4

| 指标 | 数值 |
|------|------|
| Prompt 处理速度 | 1215 t/s |
| 文本生成速度 | 67 t/s |
| 模型加载时间 | ~3 秒 |
| 首 token 延迟 | < 200 ms |
| GPU 显存占用 | 2.9 GB / 7.5 GB |
| GPU 温度 | 44°C (空闲) / 55-65°C (负载) |
| 系统内存占用 | ~2.8 GB |

## 🔧 故障排除速查

```bash
# CUDA 不可用
ggml_cuda_init: found 0 CUDA devices
# -> 检查 nvidia-smi, 确认驱动安装
# -> 重新编译: cmake -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61

# OOM 错误
CUDA error: out of memory
# -> 降低上下文长度 -c 4096
# -> 使用更小模型或更低量化
# -> 减少 ngl 层数

# 编译错误
nvcc fatal: Unsupported gpu architecture 'compute_61'
# -> 检查 CUDA Toolkit 版本（需 ≥ 11.0）
# -> nvcc --version

# 模型加载报错
unknown model architecture: 'qwen3.5'
# -> llama.cpp 版本过旧，需要 ≥ b10020
# -> git pull && cmake --build build

# 生成质量差
# -> 调整温度: --temp 0.3-0.7
# -> 尝试非思考模式（如果模型支持）
```
