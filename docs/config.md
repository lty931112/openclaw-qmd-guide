# OpenClaw 配置 QMD 记忆后端指南

> 前提：你已在 WSL2 中成功部署 QMD，且 `qmd query "test" -c memory-root --json` 能正常返回结果。
>
> 本文档指导你将 QMD 接入 OpenClaw Gateway，实现自动语义记忆搜索。

---

## 一、整体架构

```
┌──────────────────────────────────────────────────┐
│  Windows 宿主机                                   │
│                                                    │
│  OpenClaw Gateway (Node.js)                        │
│    │                                               │
│    │  memory.backend = "qmd"                       │
│    │  memory.qmd.command = "wsl qmd"               │
│    │                                               │
│    ▼                                               │
│  调用命令: wsl qmd query "用户消息" -c xxx --json   │
│                                                    │
└──────────┬───────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────┐
│  WSL2 (Ubuntu)                                    │
│                                                    │
│  QMD CLI (Bun)                                     │
│    ├── BM25 关键词搜索                              │
│    ├── 向量语义搜索 (embeddinggemma-300M)           │
│    └── LLM 重排序 (qwen3-reranker-0.6b)            │
│                                                    │
│  数据存储:                                          │
│    ├── XDG_CONFIG_HOME/qmd/  (集合配置、索引)       │
│    └── XDG_CACHE_HOME/qmd/  (模型、缓存)           │
│                                                    │
└──────────────────────────────────────────────────┘
```

---

## 二、配置前检查清单

在开始配置之前，逐项确认：

### ✅ 检查 1：QMD 在 WSL2 中能正常工作

```bash
# 在 WSL2 Ubuntu 终端中执行
qmd --version
qmd status
qmd query "test" -c memory-root --json
```

三个命令都能正常执行（不报错），继续下一步。

### ✅ 检查 2：确认 XDG 环境变量

```bash
# 在 WSL2 中执行
echo $XDG_CONFIG_HOME
echo $XDG_CACHE_HOME
```

记下这两个值，后面配置要用。例如：

```
XDG_CONFIG_HOME=/home/lty/.config
XDG_CACHE_HOME=/home/lty/.cache
```

### ✅ 检查 3：确认 WSL2 中的 qmd 能被 Windows 调用

```powershell
# 在 Windows PowerShell 中执行
wsl qmd --version
```

应输出 QMD 版本号。如果报错，说明 WSL2 的 PATH 配置有问题，参考 [附录 A](#附录-a-wsl-qmd-命令找不到)。

### ✅ 检查 4：确认 OpenClaw Gateway 在运行

```powershell
# 在 Windows PowerShell 中执行
openclaw status
```

---

## 三、核心配置

### 步骤 1：定位 openclaw.json

| 系统 | 路径 |
|------|------|
| Windows | `C:\Users\<你的用户名>\.openclaw\openclaw.json` |

### 步骤 2：编辑 openclaw.json

用任意文本编辑器打开 `C:\Users\<你的用户名>\.openclaw\openclaw.json`，添加或修改以下配置：

#### 最小配置（先跑起来）

```json
{
  "memory": {
    "backend": "qmd",
    "qmd": {
      "command": "wsl bash -c 'export XDG_CONFIG_HOME=/home/lty/.config XDG_CACHE_HOME=/home/lty/.cache && qmd'",
      "limits": {
        "timeoutMs": 8000
      }
    }
  }
}
```

> **关键**：`command` 字段必须包含 `export XDG_CONFIG_HOME=... XDG_CACHE_HOME=...`，否则 OpenClaw 调用 WSL 中的 qmd 时，环境变量不会自动传递，QMD 会找不到模型和索引。

#### 完整推荐配置

```json
{
  "memory": {
    "backend": "qmd",
    "citations": "auto",
    "qmd": {
      "command": "wsl bash -c 'export XDG_CONFIG_HOME=/home/lty/.config XDG_CACHE_HOME=/home/lty/.cache && qmd'",
      "includeDefaultMemory": true,
      "searchMode": "search",
      "update": {
        "interval": "5m",
        "debounceMs": 15000,
        "onBoot": true,
        "waitForBootSync": false
      },
      "limits": {
        "maxResults": 6,
        "timeoutMs": 8000
      },
      "scope": {
        "default": "deny",
        "rules": [
          { "action": "allow", "match": { "chatType": "direct" } }
        ]
      }
    }
  }
}
```

### 步骤 3：参数说明

| 参数 | 值 | 说明 |
|------|---|------|
| `memory.backend` | `"qmd"` | 切换记忆后端为 QMD |
| `memory.citations` | `"auto"` | 自动在回复中标注引用来源 |
| `qmd.command` | `"wsl bash -c '...'"` | **最关键**：通过 WSL 调用 QMD 并传递环境变量 |
| `qmd.includeDefaultMemory` | `true` | 自动索引 `MEMORY.md` 和 `memory/*.md` |
| `qmd.searchMode` | `"search"` | 搜索模式：`search`(关键词) / `vsearch`(语义) / `query`(混合+重排序) |
| `qmd.update.interval` | `"5m"` | 自动重新索引间隔 |
| `qmd.update.onBoot` | `true` | 启动时自动刷新索引 |
| `qmd.update.waitForBootSync` | `false` | 后台刷新，不阻塞聊天启动 |
| `qmd.limits.maxResults` | `6` | 每次搜索最多返回 6 条结果 |
| `qmd.limits.timeoutMs` | `8000` | 搜索超时 8 秒（首次建议设大一些） |
| `qmd.scope` | 见上 | 默认只在私聊中启用搜索 |

### 步骤 4：替换你的实际路径

将配置中的路径替换为你 WSL2 中的实际值：

```bash
# 在 WSL2 中查看
echo "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
echo "XDG_CACHE_HOME=$XDG_CACHE_HOME"
```

然后替换 `command` 中的值。例如如果你的 XDG 路径是：

```
XDG_CONFIG_HOME=/home/lty/.config
XDG_CACHE_HOME=/home/lty/.cache
```

则 `command` 为：

```
wsl bash -c 'export XDG_CONFIG_HOME=/home/lty/.config XDG_CACHE_HOME=/home/lty/.cache && qmd'
```

### 步骤 5：重启 OpenClaw Gateway

```powershell
# 在 Windows PowerShell 中执行
openclaw gateway restart
```

---

## 四、验证配置是否生效

### 验证 1：查看日志

```powershell
openclaw gateway logs
```

在日志中搜索以下关键词：

| 关键词 | 含义 |
|--------|------|
| `Using QMD memory backend` | ✅ QMD 已成功启用 |
| `QMD subprocess exited` | ❌ QMD 进程崩溃 |
| `falling back to builtin` | ⚠️ QMD 失败，回退到内置 SQLite |

### 验证 2：对话测试

在 OpenClaw 对话中发送：

```
确认你是否启用了 QMD 记忆后端，给出当前状态报告。
```

Agent 应该能报告它正在使用 QMD。

### 验证 3：记忆搜索测试

1. 先让 OpenClaw 记住一些信息：
   ```
   请记住：我最喜欢的编程语言是 Python，我的项目代号是 Phoenix。
   ```

2. 等待几分钟（让 QMD 索引更新），然后在新对话中问：
   ```
   我之前说过我喜欢什么编程语言？
   ```

3. 如果 QMD 工作正常，Agent 应该能从记忆中检索到答案。

---

## 五、索引额外的文档目录

如果你想让 QMD 索引 OpenClaw workspace 之外的其他 Markdown 文件（如知识库、笔记等）：

编辑 `openclaw.json`，在 `memory.qmd` 中添加 `paths`：

```json
{
  "memory": {
    "backend": "qmd",
    "qmd": {
      "command": "wsl bash -c 'export XDG_CONFIG_HOME=/home/lty/.config XDG_CACHE_HOME=/home/lty/.cache && qmd'",
      "includeDefaultMemory": true,
      "paths": [
        {
          "name": "my-notes",
          "path": "/mnt/c/Users/17640/Documents/我的笔记",
          "pattern": "**/*.md"
        },
        {
          "name": "project-docs",
          "path": "/mnt/c/Users/17640/Projects/docs",
          "pattern": "**/*.md"
        }
      ]
    }
  }
}
```

> **注意**：`path` 使用 WSL2 格式（`/mnt/c/...`），不是 Windows 格式（`C:\...`）。

修改后重启 Gateway：

```powershell
openclaw gateway restart
```

---

## 六、开启会话历史索引（可选）

让 QMD 也索引你的历史对话记录，实现"搜索过去的对话"：

```json
{
  "memory": {
    "backend": "qmd",
    "qmd": {
      "command": "wsl bash -c 'export XDG_CONFIG_HOME=/home/lty/.config XDG_CACHE_HOME=/home/lty/.cache && qmd'",
      "sessions": {
        "enabled": true,
        "retentionDays": 30
      }
    }
  }
}
```

| 参数 | 说明 |
|------|------|
| `sessions.enabled` | `true` 开启会话索引 |
| `sessions.retentionDays` | 保留最近 30 天的会话记录 |

---

## 七、调优指南

### 搜索结果太多噪音？

```json
{
  "qmd": {
    "limits": {
      "maxResults": 3,
      "timeoutMs": 4000
    }
  }
}
```

### 搜索结果不够相关？

```json
{
  "qmd": {
    "searchMode": "query",
    "limits": {
      "maxResults": 8
    }
  }
}
```

`searchMode` 对比：

| 模式 | 命令 | 速度 | 质量 | 说明 |
|------|------|------|------|------|
| `search` | `qmd search` | ⚡ 最快 | ⭐⭐⭐ | BM25 关键词匹配 |
| `vsearch` | `qmd vsearch` | 🔄 中等 | ⭐⭐⭐⭐ | 纯向量语义搜索 |
| `query` | `qmd query` | 🐢 最慢 | ⭐⭐⭐⭐⭐ | 混合搜索 + LLM 重排序 |

### 首次搜索很慢？

正常现象。首次搜索需要加载 3 个 GGUF 模型到内存（约 2GB），后续查询会很快。

可以手动预热：

```bash
# 在 WSL2 中执行
qmd query "预热" -c memory-root --json > /dev/null 2>&1
```

### 想在群聊中也启用搜索？

```json
{
  "qmd": {
    "scope": {
      "default": "allow"
    }
  }
}
```

---

## 八、回退方案

如果 QMD 出现问题，随时可以回退到内置 SQLite：

编辑 `openclaw.json`，删除 `memory` 块或改为：

```json
{
  "memory": {
    "backend": "sqlite"
  }
}
```

然后重启：

```powershell
openclaw gateway restart
```

> **安全机制**：当 QMD 子进程异常时，OpenClaw 会**自动回退**到内置 SQLite，不会影响正常使用。

---

## 九、完整配置模板（复制即用）

> ⚠️ 替换 `/home/lty/.config` 和 `/home/lty/.cache` 为你的实际 XDG 路径。

```json
{
  "memory": {
    "backend": "qmd",
    "citations": "auto",
    "qmd": {
      "command": "wsl bash -c 'export XDG_CONFIG_HOME=/home/lty/.config XDG_CACHE_HOME=/home/lty/.cache && qmd'",
      "includeDefaultMemory": true,
      "searchMode": "search",
      "update": {
        "interval": "5m",
        "debounceMs": 15000,
        "onBoot": true,
        "waitForBootSync": false
      },
      "limits": {
        "maxResults": 6,
        "timeoutMs": 8000
      },
      "sessions": {
        "enabled": false,
        "retentionDays": 30
      },
      "paths": [],
      "scope": {
        "default": "deny",
        "rules": [
          { "action": "allow", "match": { "chatType": "direct" } }
        ]
      }
    }
  }
}
```

---

## 附录 A：WSL `qmd` 命令找不到

在 Windows PowerShell 中执行 `wsl qmd --version` 报错时：

```powershell
# 测试
wsl which qmd
wsl echo $PATH
```

如果找不到，在 WSL2 中确保 PATH 配置正确：

```bash
# 编辑 ~/.bashrc
nano ~/.bashrc

# 确保包含以下行：
export PATH="$HOME/.bun/bin:$PATH"

# 保存后
source ~/.bashrc

# 验证
which qmd
qmd --version
```

然后回到 Windows PowerShell 验证：

```powershell
wsl qmd --version
```

## 附录 B：command 字段的常见写法

根据你的环境选择一种：

```json
// 写法 1：指定 XDG 路径（推荐，最可靠）
"command": "wsl bash -c 'export XDG_CONFIG_HOME=/home/lty/.config XDG_CACHE_HOME=/home/lty/.cache && qmd'"

// 写法 2：如果 XDG 已在 ~/.bashrc 中设置，且 --login 会加载它
"command": "wsl bash --login -c 'qmd'"

// 写法 3：如果 bun 的 bin 不在默认 PATH 中
"command": "wsl bash -c 'export PATH=$HOME/.bun/bin:$PATH XDG_CONFIG_HOME=/home/lty/.config XDG_CACHE_HOME=/home/lty/.cache && qmd'"
```

## 附录 C：配置文件合并说明

如果你的 `openclaw.json` 中已有其他配置（如 `agents`、`models`、`plugins` 等），只需在顶层添加 `memory` 块即可，不要覆盖已有配置。例如：

```json
{
  "models": {
    "providers": { ... }
  },
  "agents": {
    "defaults": { ... }
  },
  "plugins": { ... },

  "memory": {
    "backend": "qmd",
    "qmd": {
      "command": "wsl bash -c 'export XDG_CONFIG_HOME=/home/lty/.config XDG_CACHE_HOME=/home/lty/.cache && qmd'",
      "limits": { "timeoutMs": 8000 }
    }
  }
}
```

---

*本文档基于 OpenClaw Memory 文档和 QMD 官方文档编写。*
*参考：[OpenClaw Memory Docs](https://github.com/openclaw/openclaw/blob/main/docs/concepts/memory.md)、[QMD GitHub](https://github.com/tobi/qmd)、[Clawee QMD 指南](https://clawee.dev/guides/qmd-install-config)*
