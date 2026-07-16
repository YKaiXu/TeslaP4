# Tesla P4 模型选型推荐

> Tesla P4 拥有 8GB 显存、Pascal 架构 (CC 6.1)，选择模型时需要考虑显存限制和架构特性。

## 核心原则

1. **必须量化**：8GB 显存无法运行任何 FP16 模型（除 1.7B 以下的），必须使用 GGUF Q4_K_M 或更低精度
2. **优先 Dense 模型**：MoE 模型即使总参数小，完整权重通常也超过 8GB
3. **推荐 1B-4B 参数范围**：量化后 0.7-3.9GB 显存占用，留有足够空间给 KV Cache
4. **只能用 llama.cpp**：Pascal 架构不支持 vLLM / SGLang 等现代框架
5. **KV Cache 量化很关键**：长上下文（≥16K）必须用 `--cache-type-k q8_0 --cache-type-v q8_0` 节省显存

---

## 推荐模型排行

### 🥇 首选：MiniCPM5-1B（**最新推荐 2026-07**）

| 项目 | 数据 |
|------|------|
| **参数** | 1B (Dense) |
| **架构** | LlamaForCausalLM（标准架构） |
| **量化** | Q4_K_M |
| **模型大小** | **0.65 GB** |
| **上下文（实际可用）** | **128K tokens**（KV Cache Q8 量化） |
| **原生上下文** | 128K（训练上限） |
| **显存占用** | **2.6 GB / 8 GB** |
| **生成速度** | **90-101 t/s** |
| **Prompt 处理速度** | 1000+ t/s |
| **工具调用（OpenAI 格式）** | ✅ 完美支持（7/7 场景通过） |
| **思考模式** | 可通过 `enable_thinking: false` 关闭 |
| **来源** | [OpenBMB/MiniCPM5-1B](https://www.modelscope.cn/models/OpenBMB/MiniCPM5-1B) (魔搭) |
| **GGUF** | 需自行转换（详见 [gguf-conversion.md](gguf-conversion.md)） |

**优点**：
- 128K 超大上下文（P4 上唯一 4B 以下能跑 128K 的模型）
- 工具调用准确率 100%（多工具选择、中英文、多轮对话均通过）
- 速度 90+ t/s，远超阅读阈值
- 显存仅 2.6 GB，可同时运行其他任务
- OpenBMB 国产模型，中文优秀
- 2026 年 5 月最新发布的模型

**缺点**：
- 1B 参数在极端复杂推理上有限
- 单次输出约 1500 tokens 自动收尾（对编码场景够用）
- 需自行从 HF safetensors 转换为 GGUF

**实测启动命令**：
```bash
llama-server -m ~/models/MiniCPM5-1B-Q4_K_M.gguf \
    -ngl 99 -c 131072 --host 0.0.0.0 --port 8067 \
    --jinja --cache-type-k q8_0 --cache-type-v q8_0 -np 1
```

**OpenCode 配置**（详见 [opencode-integration.md](opencode-integration.md)）：
```json
{
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "本地 P4 模型",
      "options": { "baseURL": "http://192.168.10.20:8067/v1" },
      "models": {
        "default": {
          "name": "P4 本地模型",
          "limit": { "context": 131072, "output": 4096 }
        }
      }
    }
  }
}
```

**详细的日常使用测试结果**：

| 类别 | 通过率 | 详情 |
|------|--------|------|
| 知识理解 | 3/4 ✅ | 常识✓ 历史✗ 科学✓ 文化✓ |
| 逻辑推理 | 3/3 ✅ | 数学✓ 三段论✓ 脑筋急转弯✓ |
| 代码生成 | 3/3 ✅ | 写函数✓ 装饰器✓ 代码理解✓ |
| 创意写作 | 3/3 ✅ | 造句✓ 文案✓ 比喻✓ |
| 工具调用 | 5/6 ✅ | 天气✓ 计算✓ 搜索✓ 多轮✓ 误触发✗ |
| 性能 | **101 t/s** | 2.6 GB 显存, 62°C |

---

### 🥈 备选：Qwen3-1.7B（**上一代推荐**）

| 项目 | 数据 |
|------|------|
| **参数** | 1.7B (Dense) |
| **量化** | Q4_K_M |
| **模型大小** | 1.1 GB |
| **上下文（实际可用）** | **32K tokens**（KV Cache Q8 量化） |
| **原生上下文** | 128K（受显存限制实际用 32K） |
| **显存占用** | **6.47 GB / 7.68 GB** |
| **生成速度** | **65.8 t/s** |
| **Prompt 处理速度** | 668 t/s |
| **工具调用（OpenAI 格式）** | ✅ 完美支持 |
| **思考模式** | 可通过 `/no_think` 系统提示关闭 |
| **来源** | [unsloth/Qwen3-1.7B-GGUF](https://huggingface.co/unsloth/Qwen3-1.7B-GGUF) / ModelScope 镜像 |

**优点**：
- 32K 上下文适合编程代理
- 工具调用稳定
- 有现成 GGUF 可直接下载

**缺点**：
- 上下文只有 MiniCPM5-1B 的 1/4
- 速度慢 40%（65 vs 101 t/s）
- 显存占用高 2.5 倍（6.5 vs 2.6 GB）
- 2025 年发布的旧模型

### 🥉 可行：Qwen3-4B（重型任务）

| 项目 | 数据 |
|------|------|
| **参数** | 4B (Dense) |
| **量化** | Q4_K_M |
| **模型大小** | ~3.9 GB |
| **显存占用** | ~5.5 GB |
| **生成速度** | ~35 t/s |
| **上下文** | 8K（32K 会 OOM） |

**优点**：推理能力更强
**缺点**：上下文受限，仅 8K，不适合长文档场景

### ❌ 已淘汰的模型

| 模型 | 淘汰原因 | 替代 |
|------|---------|------|
| **Qwen3-1.7B** | 显存高、上下文短、速度慢 | MiniCPM5-1B |
| **Qwen3.5-2B** | 多模态场景极少，上下文受限 16K | MiniCPM5-1B |
| **Gemma 3 4B** | 工具调用不可用 | MiniCPM5-1B |
| **Phi-4-mini** | llama.cpp chat template bug，工具调用失败 | MiniCPM5-1B |
| **Gemma 3 1B** | 智商低，数学算错，工具调用不可用 | MiniCPM5-1B |
| **Dolphin 3.0 3B** | 对工具描述语言敏感 | MiniCPM5-1B |

---

## 不适合 P4 的模型

| 模型 | 原因 |
|------|------|
| **Qwen3-8B+** | 量化后仍超 6GB，+KV Cache 超 8GB |
| **Qwen3-30B-A3B** | MoE 模型，全部权重约 17GB，远超 8GB |
| **Llama-3-8B** | Q4_K_M 后 5.5GB，显存不足 |
| **DeepSeek-R1 (蒸馏)** | 最小 7B 版本仍需 > 8GB |
| **FP16 精度任意模型** | 4B 模型 FP16 就需要 8GB |

---

## 量化级别选择指南

| 量化级别 | 精度损失 | 推荐场景 |
|----------|----------|----------|
| **Q4_K_M** | ~2% | ⭐ 首选，最佳性价比 |
| Q5_K_M | ~1% | 显存有余量时可选 |
| Q3_K_M | ~5% | 极限压缩，用于 6B-7B 模型 |
| Q2_K | ~10% | 不推荐，质量下降明显 |
| Q8_0 | <0.5% | 用于 KV Cache（不是模型权重） |

---

## KV Cache 量化：长上下文的必选

**显存预算（Tesla P4 7.68GB 实际可用）：**

| 模型权重 | 32K KV Cache (FP16) | 128K KV Cache (Q8) |
|----------|---------------------|-------------------|
| 0.65 GB (MiniCPM5-1B) | 3.5 GB | **2.6 GB ✅** |
| 1.1 GB (Qwen3-1.7B) | 3.5 GB | 6.5 GB ⚠️ |
| 3.9 GB (Qwen3-4B) | OOM | OOM |

**结论**：MiniCPM5-1B 是唯一能在 P4 上跑 128K 上下文的模型。
不量化 KV Cache 直接 OOM（实测崩溃）。

**启用方式**：
```bash
--cache-type-k q8_0 --cache-type-v q8_0
```

---

## 模型趋势建议

> 截至 2026 年 7 月，MiniCPM5-1B 是 Tesla P4 的最佳选择。

1. **MiniCPM5-1B（首选）**：128K 上下文、工具调用完美、速度 90+ t/s、显存仅 2.6 GB
2. **Qwen3-1.7B（备选）**：32K 上下文、工具调用完美、速度 65 t/s
3. **Qwen3-4B（重推理）**：速度 35 t/s，上下文仅 8K

**实测结论**：
- **OpenCode 编程代理场景** → **MiniCPM5-1B**（128K + 工具调用是刚需）
- **长文档分析** → **MiniCPM5-1B**（唯一能跑 128K 的）
- **日常对话/代码辅助** → **MiniCPM5-1B**（速度最快）

---

## 工具调用（Function Calling）实测

| 模型 | 工具调用 | 备注 |
|------|----------|------|
| **MiniCPM5-1B** | ✅ 完美 | 7/7 场景通过，多工具选择、多轮对话均正确 |
| Qwen3-1.7B | ✅ 完美 | 输出标准 OpenAI `tool_calls` JSON |
| Qwen3-4B | ✅ 良好 | 同上 |
| Gemma 3 4B | ❌ 失败 | 不触发工具调用，直接编答案 |
| Phi-4-mini | ❌ 失败 | llama.cpp chat template bug |

**MiniCPM5-1B 工具调用响应示例**：
```json
{
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "",
      "tool_calls": [{
        "type": "function",
        "function": {
          "name": "get_weather",
          "arguments": "{\"city\": \"北京\"}"
        }
      }]
    }
  }]
}
```

> 启动时**必须**加 `--jinja` 才能正确渲染工具定义。
