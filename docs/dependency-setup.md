## 依赖环境配置指南

## 1. 安装编译工具链

```bash
sudo apt update
sudo apt install -y build-essential cmake git

# 验证
cmake --version
```

## 2. 安装 Python 环境

### 安装 pip 和虚拟环境

```bash
sudo apt install -y python3-pip python3.14-venv

# 创建虚拟环境（推荐，避免系统包冲突）
python3 -m venv ~/ai/venv
source ~/ai/venv/bin/activate

# 安装 modelscope（用于国内下载模型）
pip install modelscope
```

## 3. 编译 llama.cpp（核心步骤）

> **为什么必须自己编译？**
> Tesla P4 基于 Pascal 架构（CC 6.1），预编译的 llama.cpp 通常针对较新的 GPU 架构优化。自行编译可以指定 sm_61 以获得最佳性能。

### 克隆仓库

```bash
cd ~/ai
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
```

### 编译（启用 CUDA，针对 Tesla P4）

```bash
cmake -B build \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=61 \
  -DGGML_CUDA_F16=ON

cmake --build build --config Release -j$(nproc)
```

> **参数说明**：
> - `-DGGML_CUDA=ON`：启用 CUDA 后端
> - `-DCMAKE_CUDA_ARCHITECTURES=61`：指定编译为 Tesla P4 (Pascal, sm_61) 的 CUDA 代码
> - `-DGGML_CUDA_F16=ON`：启用 FP16 加速
> - `-j$(nproc)`：使用所有 CPU 核心并行编译

### 验证编译成功

```bash
ls -lh build/bin/
# 应该能看到 llama-cli, llama-server, llama-bench 等可执行文件

# 测试 CUDA 后端是否工作
./build/bin/llama-bench -m /dev/null 2>&1 | head -5
# 输出应包含: "found 1 CUDA devices" "Tesla P4"
```

## 4. 下载模型

### 从 ModelScope（国内推荐，速度快）

```bash
# 先激活虚拟环境
source ~/ai/venv/bin/activate

mkdir -p ~/models

# Qwen3.5-2B Q4_K_M（本机实测最佳）
modelscope download \
  --model unsloth/Qwen3.5-2B-GGUF \
  Qwen3.5-2B-Q4_K_M.gguf \
  --local_dir ~/models/
```

### 从 HuggingFace

```bash
sudo apt install -y git-lfs
git lfs install

# Qwen3.5-2B Q4_K_M:
git lfs clone https://huggingface.co/unsloth/Qwen3.5-2B-GGUF
cp unsloth/Qwen3.5-2B-GGUF/Qwen3.5-2B-Q4_K_M.gguf ~/models/
```

## 5. 性能基准测试

```bash
cd ~/ai/llama.cpp

# 测试 prompt 处理和生成速度
./build/bin/llama-bench \
  -m ~/models/Qwen3.5-2B-Q4_K_M.gguf \
  -ngl 99 \
  -p 64 -n 128
```

预期结果（Tesla P4）：
```
| model                   |       size |  params | backend | ngl |    test |              t/s |
| ----------------------- | ---------: | ------: | ------: | --: | ------: | ---------------: |
| qwen35 2B Q4_K - Medium |   1.18 GiB | 1.88 B  | CUDA    |  99 |    pp64 |     1215 ± 1.82 |
| qwen35 2B Q4_K - Medium |   1.18 GiB | 1.88 B  | CUDA    |  99 |   tg128 |      67.0 ± 0.12 |
```

## 配置文件速查

### 常用 llama-cli 参数

```bash
./build/bin/llama-cli \
  -m ~/models/Qwen3.5-2B-Q4_K_M.gguf  # 模型路径
  -ngl 99                               # GPU 卸载层数（99 = 全部）
  -c 8192                               # 上下文窗口大小
  -cnv                                  # 交互式对话模式
  --temp 0.7                            # 温度参数
  --chat-template chatml                 # 对话模板
```

### 常用 llama-server 参数

```bash
./build/bin/llama-server \
  -m ~/models/Qwen3.5-2B-Q4_K_M.gguf
  -ngl 99
  -c 8192
  --host 0.0.0.0
  --port 8066
  --mlock                               # 锁定内存，防止交换
  --no-warmup                           # 跳过预热（避免 Xorg 冲突）
```
