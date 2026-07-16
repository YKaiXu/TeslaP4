# NVIDIA Tesla P4 大模型部署完全指南

![License](https://img.shields.io/badge/license-Apache%202.0-blue)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Ubuntu%2026.04-orange)
![GPU](https://img.shields.io/badge/GPU-Tesla%20P4%20(8GB)-green)

## 项目简介

本项目是面向 **NVIDIA Tesla P4 (8GB GDDR5, Pascal 架构, CC 6.1)** 显卡的大模型本地部署完整指南。基于真实的硬件环境和实战经验，提供从驱动安装、环境配置、模型选型、推理运行、到 OpenCode 接入的全流程指导。

### 为什么选择 Tesla P4？

| 项目 | 参数 |
|------|------|
| **显存** | 8 GB GDDR5 |
| **架构** | Pascal (Compute Capability 6.1) |
| **CUDA 核心** | 2560 |
| **二手价格** | 约 ¥300-500（极具性价比） |
| **功耗** | 75W TDP（无需外接供电） |
| **适合** | 轻量级 LLM 推理、AI 实验、原型开发、OpenCode 编程代理 |

### 本项目已通过真实环境验证

| 组件 | 型号/版本 |
|------|-----------|
| GPU | Tesla P4 (8GB) |
| 系统 | Ubuntu 26.04 LTS |
| 驱动 | NVIDIA 580.159.03 (CUDA 13.0) |
| CPU | Intel Xeon D-1581 (16核 @ 1.80GHz) |
| 内存 | 9.2 GB |

### 已实测模型性能（2026-07-15 更新）

| 模型 | 量化 | 上下文 | KV Cache | 显存占用 | 生成速度 | 工具调用 |
|------|------|--------|----------|----------|----------|----------|
| **MiniCPM5-1B** 🔥 | Q4_K_M | **128K** | Q8 | **2.6 GB** | **101 t/s** | ✅ 完美 |
| Qwen3-1.7B | Q4_K_M | 32K | Q8 | 6.5 GB | 65 t/s | ✅ 完美 |
| Qwen3-4B | Q4_K_M | 8K | FP16 | 5.5 GB | ~35 t/s | ✅ 良好 |

---

## 快速开始

### 一键安装（Ubuntu）

```bash
# 下载项目
git clone https://github.com/YKaiXu/TeslaP4.git
cd TeslaP4
# 编译 llama.cpp + 下载模型 + 安装 systemd 服务
sudo ./scripts/setup.sh
```

### 手动安装（分步说明）

详见各文档：

| 文档 | 说明 |
|------|------|
| [驱动安装指南](docs/driver-install.md) | NVIDIA 驱动 + CUDA Toolkit 安装 |
| [依赖环境配置](docs/dependency-setup.md) | 编译工具链、Python 环境、llama.cpp 编译 |
| [模型选型推荐](docs/model-selection.md) | 哪些模型最适合 Tesla P4 |
| [GGUF 转换指南](docs/gguf-conversion.md) | HuggingFace 模型转 GGUF |
| [持久化部署](docs/persistence.md) | systemd 服务，开机自启 |
| [OpenCode 接入](docs/opencode-integration.md) | 本机/局域网 OpenCode 接入 |
| [MiniCPM5-1B 实战总结](docs/minicpm5-1b-summary.md) | 完整实测报告、对比、配置 |
| [避坑与技巧](docs/pitfalls-and-tips.md) | 常见问题、散热、性能调优 |

### 快速启动 MiniCPM5-1B 推理（推荐）

```bash
# 交互式对话
cd ~/ai/llama.cpp
./build/bin/llama-cli -m ~/models/MiniCPM5-1B-Q4_K_M.gguf \
    -ngl 99 -c 131072 --cache-type-k q8_0 --cache-type-v q8_0 \
    --jinja -cnv

# API 服务（端口 8067，OpenAI 兼容）
./build/bin/llama-server -m ~/models/MiniCPM5-1B-Q4_K_M.gguf \
    -ngl 99 -c 131072 --cache-type-k q8_0 --cache-type-v q8_0 \
    --jinja -np 1 \
    --host 0.0.0.0 --port 8067

# 测试 API
curl http://localhost:8067/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"你好"}],"stream":false}'

# 持久化部署（开机自启 + 崩溃自重启）
sudo ./scripts/install-systemd.sh
    
# 也可用项目自带的启动脚本
chmod +x scripts/run-minicpm5-1b.sh
./scripts/run-minicpm5-1b.sh server 131072 8067
```

---

## 项目结构

```
TeslaP4/
├── README.md                       # 本文件：项目总览
├── LICENSE                         # Apache 2.0
├── docs/
│   ├── driver-install.md            # 驱动安装指南
│   ├── dependency-setup.md          # 依赖环境配置
│   ├── model-selection.md           # 模型选型推荐
│   ├── gguf-conversion.md           # HF 模型转 GGUF
│   ├── persistence.md               # systemd 持久化服务
│   ├── opencode-integration.md      # OpenCode 接入配置
│   └── pitfalls-and-tips.md         # 避坑与技巧
├── scripts/
│   ├── setup.sh                     # 一键安装脚本
│   ├── install-systemd.sh           # systemd 服务安装
│   ├── run-minicpm5-1b.sh           # MiniCPM5-1B 启动脚本（推荐）
│   ├── run-qwen3-1.7b.sh            # Qwen3-1.7B 启动脚本（备选）
│   └── convert-model.sh             # HF → GGUF 转换脚本
└── LICENSE
```

---

## Tesla P4 核心要点

### 硬件须知

- **被动散热**：P4 无内置风扇，需要机箱风道直吹或加装主动散热
- **无需外接供电**：75W TDP，直接从 PCIe 插槽取电
- **无显示输出**：纯计算卡，需搭配亮机卡或集显使用

### 软件须知

- **不支持 Flash Attention**：Pascal 架构 (CC 6.1) 不支持
- **不支持 vLLM / SGLang**：最新版本已放弃 Pascal 支持
- **推荐框架**：**llama.cpp**（唯一经过充分验证的选择）
- **必须量化**：8GB 显存只能运行 Q4_K_M 或更低精度模型
- **长上下文必须量化 KV Cache**：32K + Q8 KV 是 1.7B 模型的最佳平衡点

---

## 推荐工作流

1. **硬件准备**：P4 装好 + 散热风扇直吹
2. **驱动安装**：参考 [driver-install.md](docs/driver-install.md)
3. **编译 llama.cpp**：参考 [dependency-setup.md](docs/dependency-setup.md)
4. **下载模型**：参考 [gguf-conversion.md](docs/gguf-conversion.md) 或直接下预量化版本
5. **持久化运行**：`sudo ./scripts/install-systemd.sh`
6. **OpenCode 接入**：参考 [opencode-integration.md](docs/opencode-integration.md)

---

## 社区经验

- [P40 24GB 大模型部署实战](https://gitcode.csdn.net/69c8222254b52172bc652cb1.html) - 多卡 P40 方案
- [Opteia Blog: Self-Hosted AI on P40](https://opteia.com/blog/self-hosted-ai-8b-to-30b-same-gpu) - P40 上运行 30B MoE 模型
- [TurboQuant 分支](https://github.com/TheTom/llama-cpp-turboquant) - 解决 Pascal 架构长上下文问题

---

## License

Apache 2.0
