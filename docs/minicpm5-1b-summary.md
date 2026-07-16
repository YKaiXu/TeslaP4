# MiniCPM5-1B on Tesla P4 实战总结

> 基于真实环境（Ubuntu 26.04, Tesla P4 8GB, Intel Xeon D-1581）的完整实测报告。
> 日期：2026-07-15

---

## 为什么选择 llama.cpp 而非 PyTorch/vLLM/SGLang

Tesla P4 基于 Pascal 架构（Compute Capability 6.1），这直接决定了推理框架的选择。

### 各框架对 P4 的支持情况

| 框架 | P4 支持 | 原因 |
|------|---------|------|
| **llama.cpp** | ✅ **完美支持** | 专门针对 GGUF 量化模型优化，支持 CC 6.1 |
| **PyTorch + Transformers** | ⚠️ 可用但极慢 | BF16/FP16 推理 < 5 t/s；不支持量化模型推理优化 |
| **Ollama** | ✅ 可用 | 底层基于 llama.cpp，本质相同 |
| **vLLM** | ❌ 不支持 | 2025 年起放弃 CC < 7.0 支持 |
| **SGLang** | ❌ 不支持 | 需要 Ampere 架构 (CC 8.0+) |
| **TensorRT-LLM** | ❌ 不支持 | 需要现代 GPU 架构 |
| **MS-Swift** | ⚠️ 理论上可运行 | PyTorch 后端，P4 装不下 Phi-4-mini BF16（7.6GB > 8GB） |

### llama.cpp 的核心优势

1. **GGUF 量化**：Q4_K_M 后模型体积缩小至原来的 1/4，这是 8GB 显存能跑任何模型的先决条件
2. **KV Cache 量化**：`--cache-type-k q8_0 --cache-type-v q8_0` 将长上下文显存减半
3. **CPU+GPU 混合推理**：超出显存的部分自动回退到 CPU 计算
4. **纯 C/C++ 实现**：无 Python GIL 开销，启动速度 < 3 秒
5. **OpenAI 兼容 API**：`/v1/chat/completions` 直接对接任何 OpenAI 兼容客户端

### 为什么不选 PyTorch

- MiniCPM5-1B BF16 权重 2.1GB，PyTorch 加载后约 4GB（含优化器状态）
- 加上 KV Cache 后超过 8GB
- Transformers 推理速度仅 3-5 t/s，远不如 llama.cpp 的 90+ t/s
- PyTorch 2.5+ 已不官方支持 CC 6.1，可能出现 `no kernel image` 错误

### 为什么不选 Ollama

Ollama 底层就是 llama.cpp，本质没有差别。但 llama-server 更轻量、控制更细（KV Cache 量化、并发控制等），适合作为服务长期运行。

---

## 背景

在 Tesla P4 (8GB, Pascal CC 6.1) 上部署本地大模型用于 OpenCode 编程代理，此前使用 Qwen3-1.7B 作为主力模型。通过系统的模型选型测试，最终选定 **MiniCPM5-1B** 作为最优方案。

## 探索过程

### 已测试的模型

| 模型 | 状态 | 结论 |
|------|------|------|
| **Qwen3-1.7B**（原主力） | ❌ 淘汰 | 上下文仅 32K，显存 6.5GB，速度 65 t/s |
| **Qwen3-4B** | ⚠️ 备选 | 智商强但只有 8K 上下文，速度 35 t/s |
| **Gemma 3 4B** | ❌ 淘汰 | 工具调用不可用（直接编答案） |
| **Gemma 3 1B** | ❌ 淘汰 | 数学算错（5-2+3=10），工具调用不可用 |
| **Phi-4-mini** | ❌ 淘汰 | 工具调用在 llama.cpp 上有 bug |
| **DeepSeek-R1-Distill-Qwen-1.5B** | ⚠️ 备选 | 推理强但知识面窄 |
| **MiniCPM5-1B** | ✅ **首选** | 全面胜出 |

### 最终选择：MiniCPM5-1B

**关键发现**：该模型由 OpenBMB（面壁智能 + 清华大学）于 2026 年 5 月发布，1B 参数，128K 原生上下文，LlamaForCausalLM 标准架构。在同尺寸开源模型中达到 SOTA，优势在工具调用、代码生成和复杂推理上尤为明显。

来源：[魔搭 OpenBMB/MiniCPM5-1B](https://www.modelscope.cn/models/OpenBMB/MiniCPM5-1B)

---

## 部署过程

### 方式一：下载预量化 GGUF（推荐）

```bash
# 魔搭上有官方预量化版本（688 MB）
modelscope download --model OpenBMB/MiniCPM5-1B-GGUF \
  MiniCPM5-1B-Q4_K_M.gguf \
  --local_dir ~/models/
```

### 方式二：从原始权重自行转换

```bash
# 1. 从魔搭下载原始权重（约 2.1 GB）
source ~/ai/venv/bin/activate
modelscope download --model OpenBMB/MiniCPM5-1B \
  --local_dir ~/models/MiniCPM5-1B/

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
```

### 启动命令

```bash
cd ~/ai/llama.cpp && ./build/bin/llama-server \
  -m ~/models/MiniCPM5-1B-Q4_K_M.gguf \
  -ngl 99 \
  -c 131072 \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --jinja \
  --host 0.0.0.0 \
  --port 8067
```

关键参数说明：
- `-c 131072`：128K 上下文（模型训练上限）
- `--cache-type-k q8_0 --cache-type-v q8_0`：KV Cache 量化为 Q8，节省显存
- `--jinja`：启用 Jinja chat template，工具调用必须
- `-ngl 99`：全部层卸载到 GPU

---

## 性能测试

### 上下文极限测试

| 设置 | 实际可用 | 显存 | 速度 | 状态 |
|------|---------|------|------|------|
| 32K | 32K | 1.1 GB | 90 t/s | ✅ |
| 64K | 64K | 1.6 GB | 88 t/s | ✅ |
| **128K** | **128K（最大）** | **2.6 GB** | **74-88 t/s** | ✅ **推荐** |
| 256K | 128K（被截断） | 4.5 GB | ~65 t/s | ⚠️ 浪费显存 |

**说明**：MiniCPM5-1B 训练上限为 131072 tokens。超过此值的请求会被 llama.cpp 自动截断，无法真正利用。

### 单次输出上限

| 条件 | 实际输出 | 结束原因 |
|------|---------|---------|
| 普通 prompt | ~1100 tokens | 模型自动结束 |
| 强制长文 prompt | ~1558 tokens（约 4000 字） | 模型自动结束 |

模型约 1500 tokens 自然收尾，这对编码场景（单次改一个函数/修一个 bug）足够使用。

### 速度测试

| 上下文 | 生成速度 | Prompt 处理 |
|--------|---------|------------|
| 32K | 90-101 t/s | 1000+ t/s |
| 128K | 74-88 t/s | 1000+ t/s |

### 显存占用

| 配置 | 显存 | 比例 |
|------|------|------|
| 128K + Q8 KV | 2.6 GB | 32% of 8GB |
| 64K + Q8 KV | 1.6 GB | 20% |
| 32K + Q8 KV | 1.1 GB | 14% |

GPU 温度：空闲 44°C，负载 62°C。

---

## 日常使用测试

### 知识理解（4/4 ✅）

| 测试 | 结果 |
|------|------|
| 水在多少度结冰？ | ✅ 正确回答 0°C |
| 第二次世界大战哪年开始？ | ✅ 正确回答 1939 年 |
| 光合作用产物？ | ✅ 正确回答氧气和葡萄糖 |
| 《红楼梦》作者？ | ✅ 正确回答曹雪芹 |

### 逻辑推理（3/3 ✅）

| 测试 | 结果 |
|------|------|
| 5个苹果-2+3=？ | ✅ 正确回答 6，一步步推理 |
| 身高三段论 | ✅ 正确推理出结论 |
| 3盏灯关1盏剩几盏？ | ✅ 正确回答 3 盏 |

### 代码生成（3/3 ✅）

| 测试 | 结果 |
|------|------|
| 写质数判断函数 | ✅ 完整代码 + 注释 + 时间复杂度分析 |
| 写装饰器 | ✅ 含 time 模块的正确实现 |
| 代码理解 | ✅ 正确解释文件读取代码 |

### 创意写作（3/3 ✅）

| 测试 | 结果 |
|------|------|
| 一句话描述春天 | ✅ 38字通顺句子 |
| 商品文案（智能手表） | ✅ 包含防水、心率等特性 |
| 比喻解释 API | ✅ 有形象比喻 |

### 多轮对话（1/2 ⚠️）

| 测试 | 结果 |
|------|------|
| 记住用户名字 | ⚠️ 需要更明确的上下文提示 |
| 偏好推理（喜欢火锅→推荐火锅） | ✅ 正确推荐火锅相关 |

---

## 工具调用测试

### 8 项专项测试

| 测试 | 结果 | 调用 |
|------|------|------|
| 天气查询（中文城市） | ✅ | `get_weather({"city":"北京"})` |
| 多工具选-计算 | ✅ | `calculate({"expr":"123 * 456"})` |
| 多工具选-天气 | ✅ | `get_weather({"city":"上海"})` |
| 网络搜索 | ✅ | `web_search({"query":"2026 FIFA世界杯新闻"})` |
| 混合对话（上下文保持） | ✅ | `get_weather({"city":"北京"})` |
| 英文城市查询 | ✅ | `get_weather({"city":"Tokyo"})` |
| 搜索需求 | ✅ | `search_web({"q":"latest AI news"})` |
| 不应触发场景 | ✅ | 正常聊天，没有误触发 |

**工具调用准确率：100%。** 多工具选择合理、中英文都稳、多轮对话上下文保持正常。

### 与其它模型对比

| 模型 | 工具调用 | 备注 |
|------|----------|------|
| **MiniCPM5-1B** | ✅ 完美 | 8/8 场景通过 |
| Qwen3-1.7B | ✅ 完美 | 稳定 |
| Qwen3-4B | ✅ 良好 | 稳定 |
| Gemma 3 4B | ❌ 失败 | 不触发，直接编答案 |
| Phi-4-mini | ❌ 失败 | llama.cpp chat template bug |

---

## 与其他模型的全面对比

| 维度 | MiniCPM5-1B | Qwen3-1.7B（原主力） | Qwen3-4B | Gemma 3 4B |
|------|------------|---------------------|----------|------------|
| **参数** | 1B | 1.7B | 4B | 4B |
| **量化** | Q4_K_M | Q4_K_M | Q4_K_M | Q4_K_M |
| **模型大小** | 0.65 GB | 1.1 GB | 3.9 GB | 2.5 GB |
| **P4 上下文** | **128K** | 32K | 8K | 32K |
| **显存占用** | **2.6 GB** | 6.5 GB | 5.5 GB | 3.3 GB |
| **生成速度** | **90-101 t/s** | 65 t/s | 35 t/s | 50 t/s |
| **工具调用** | ✅ 完美 | ✅ 完美 | ✅ 良好 | ❌ |
| **中文** | ✅ 好 | ✅ 好 | ✅ 好 | ⚠️ 一般 |

---

## OpenCode 配置

### 配置文件（`~/.config/opencode/opencode.json`）

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "本地 P4 模型",
      "options": {
        "baseURL": "http://192.168.10.20:8067/v1"
      },
      "models": {
        "default": {
          "id": "local-model",
          "name": "P4 本地模型",
          "limit": {
            "context": 131072,
            "output": 4096
          }
        }
      }
    }
  }
}
```

**重要**：这个配置文件一旦设置完成，**永远不需要修改**。以后换模型时，只需在 P4 主机上停止 llama-server、换 GGUF 文件路径重启即可，Opencode 端无需任何变动。

### 思考模式

MiniCPM5-1B 默认启用思考模式（`<think>`），会导致回复为空（只有 `reasoning_content` 字段）。

**解决方案**：在请求时传入：
```json
{
  "chat_template_kwargs": {"enable_thinking": false}
}
```

或在 OpenCode 系统提示中加入："不要使用思考模式，直接回答"。

---

## systemd 持久化部署

创建 `/etc/systemd/system/llama-server.service`：

```ini
[Unit]
Description=llama-server - MiniCPM5-1B on Tesla P4
After=network-online.target nvidia-persistenced.service

[Service]
Type=simple
User=yupeng
Environment=LLAMA_MODEL=/home/yupeng/models/MiniCPM5-1B-Q4_K_M.gguf
Environment=LLAMA_PORT=8067
Environment=LLAMA_CTX=131072

ExecStart=/home/yupeng/ai/llama.cpp/build/bin/llama-server \
    -m ${LLAMA_MODEL} -ngl 99 -c ${LLAMA_CTX} \
    --host 0.0.0.0 --port ${LLAMA_PORT} \
    --jinja --cache-type-k q8_0 --cache-type-v q8_0 -np 1

Restart=on-failure
RestartSec=5
ExecStartPre=/bin/sh -c 'for i in 1 2 3 4 5; do nvidia-smi >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'

[Install]
WantedBy=multi-user.target
```

---

## 警告与避坑

### 1. SFT 版本转换问题

MiniCPM5-1B-SFT（仅 SFT 阶段，无 RL/OPD）在转换为 GGUF 后输出乱码（`<reserved_xxx>` 保留 token），**无法正常使用**。如需使用请等待社区修复或官方更新。

### 2. 思考模式导致回复为空

模型默认启用混合推理（`<think>` 模式）。如果收到空回复（仅有 `reasoning_content`），需传 `enable_thinking: false`。

### 3. 单次输出上限

模型约 1500 tokens 后自动收尾（`finish_reason: "stop"`），这是模型主动判断回答完整后的自然结束，不是截断。对于编码场景的增量修改完全够用。

### 4. 训练上下文上限

MiniCPM5-1B 训练上下文为 131072 tokens。超过此值会被 llama.cpp 自动截断，分配更多显存但没有实际收益。

---

## 最终结论

**MiniCPM5-1B 是 Tesla P4 8GB 上当前最优的本地模型选择。**

- ✅ **128K 超大上下文** — P4 上唯一能跑满 128K 的 1B 模型
- ✅ **90+ t/s 高速推理** — 远超可读阈值，体验流畅
- ✅ **工具调用完美** — 100% 通过率，兼容 OpenAI 格式
- ✅ **显存仅 2.6 GB** — 占用 32%，留有充足余量
- ✅ **中文优秀** — 国内团队原生优化
- ✅ **Apache 2.0 开源协议** — 可商用

替代 Qwen3-1.7B 后，在上下文（4x）、速度（1.5x）、显存（2.5x 省）三个维度都有显著提升。
