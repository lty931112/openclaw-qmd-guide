# 🦞 OpenClaw QMD Setup Guide

> **Windows + WSL2 一键部署 QMD 记忆后端，接入 OpenClaw（龙虾）**

[![Platform](https://img.shields.io/badge/Platform-Windows%20%2B%20WSL2-blue)]()
[![OpenClaw](https://img.shields.io/badge/OpenClaw-QMD%20Memory%20Backend-green)]()
[![License](https://img.shields.io/badge/License-MIT-yellow)]()

---

## 📖 这是什么？

[QMD](https://github.com/tobi/qmd) 是 Shopify 创始人 Tobi Lütke 开发的**本地混合语义搜索引擎**，结合了三层搜索机制：

| 搜索层 | 技术 | 擅长 |
|--------|------|------|
| BM25 | 关键词匹配 | 精确词、ID、代码符号 |
| Vector | 向量语义搜索 | 同义表达、概念匹配 |
| LLM Reranker | 重排序 | 综合排序、精准召回 |

接入 [OpenClaw](https://github.com/openclaw/openclaw) 后，你的 AI 助手可以**秒级检索**所有历史记忆和文档，不再受上下文窗口限制。

### 效果对比

| 指标 | 无 QMD | 有 QMD |
|------|--------|--------|
| 响应速度 | 慢（长上下文） | **快 5-50 倍** |
| Token 消耗 | 高（全量注入） | **降低 90-99%** |
| 搜索精度 | 一般 | **更高（噪音更少）** |
| 上下文溢出 | 经常发生 | **不再发生** |

---

## 🚀 快速开始

### 前置条件

- Windows 10/11
- 已安装 [OpenClaw](https://github.com/openclaw/openclaw) Gateway
- 已配置 Git + GitHub 认证

### 一键部署

```powershell
# 1. 克隆仓库
git clone https://github.com/<你的用户名>/openclaw-qmd-guide.git
cd openclaw-qmd-guide

# 2. 以管理员身份运行 PowerShell，执行一键部署
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-qmd-openclaw.ps1
```

脚本会自动完成所有 12 个步骤（约 10-15 分钟，取决于网速）。

### 自定义参数

```powershell
.\install-qmd-openclaw.ps1 `
  -WinUser "你的Windows用户名" `
  -WslUser "你的WSL用户名" `
  -OpenClawDir "D:\openclaw" `
  -QmdHttpPort "18923"
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-WinUser` | Windows 用户名 | 自动检测 |
| `-WslUser` | WSL2 Linux 用户名 | 自动检测 |
| `-OpenClawDir` | OpenClaw 安装目录 | 自动检测 |
| `-QmdHttpPort` | QMD HTTP 服务端口 | `18923` |

---

## 📁 项目结构

```
openclaw-qmd-guide/
├── README.md                          # 本文件
├── install-qmd-openclaw.ps1           # 一键部署脚本
└── docs/
    ├── guide.md                       # 完整部署指南（手动操作版）
    └── config.md                      # OpenClaw QMD 配置详解
```

---

## 🏗️ 架构

```
┌─────────────────────────────────────────────────────┐
│  Windows 宿主机                                       │
│                                                       │
│  ┌─────────────────┐     ┌──────────────────┐        │
│  │ OpenClaw Gateway │────▶│ qmd-http.cmd     │        │
│  │   (Node.js)      │     │ (Windows 脚本)   │        │
│  └─────────────────┘     └────────┬─────────┘        │
│                                   │ HTTP               │
└───────────────────────────────────┼───────────────────┘
                                    ▼
┌───────────────────────────────────────────────────────┐
│  WSL2 (Ubuntu)                                         │
│                                                        │
│  ┌──────────────────────────────────────────┐          │
│  │  qmd-server.js (Node.js HTTP 常驻服务)     │          │
│  │  端口: 127.0.0.1:18923                     │          │
│  │  模型只加载一次，常驻内存                    │          │
│  └──────────────────┬───────────────────────┘          │
│                     ▼                                  │
│  ┌──────────────────────────────────────────┐          │
│  │  QMD CLI (Bun)                             │          │
│  │  ├── BM25 关键词搜索                        │          │
│  │  ├── 向量语义搜索 (embeddinggemma-300M)     │          │
│  │  └── LLM 重排序 (qwen3-reranker-0.6b)      │          │
│  └──────────────────────────────────────────┘          │
│                                                        │
│  数据存储:                                             │
│  ├── /mnt/c/.../qmd/xdg-config/  (索引、集合配置)       │
│  └── /home/.../qmd/models/        (GGUF 模型文件)       │
└────────────────────────────────────────────────────────┘
```

---

## 📋 部署步骤详解

脚本自动完成以下 12 个步骤：

| # | 步骤 | 说明 |
|---|------|------|
| 1 | 检查/安装 WSL2 + Ubuntu | 未安装则自动安装并提示重启 |
| 2 | 安装 Bun 运行时 | QMD 的运行依赖 |
| 3 | 安装 QMD CLI | Bun 失败自动回退 npm |
| 4 | 安装 SQLite (FTS5) | 全文搜索扩展支持 |
| 5 | 配置 WSL2 环境变量 | XDG 路径、PATH、CPU 模式 |
| 6 | 下载 GGUF 模型 | 3 个模型，约 2GB，国内镜像 |
| 7 | 创建集合 + 构建索引 | 3 个默认集合 + 向量嵌入 |
| 8 | 部署 HTTP 常驻服务 | 模型常驻内存，1-3 秒响应 |
| 9 | 创建 Windows 客户端脚本 | qmd-http.cmd |
| 10 | 配置 openclaw.json | 智能合并，不覆盖已有配置 |
| 11 | 设置开机自启 | VBS 脚本，无窗口启动 |
| 12 | 重启 OpenClaw Gateway | 使配置生效 |

---

## ✅ 验证部署

### 方法一：查看日志

```powershell
openclaw gateway logs
```

搜索 `Using QMD memory backend`，出现则表示成功。

### 方法二：对话测试

```
你：请记住：我叫小明，我喜欢打篮球。
（等待 5 分钟，让 QMD 自动索引）

你（新对话）：我叫什么名字？我喜欢什么运动？
（应能从记忆中检索到答案）
```

### 方法三：HTTP 服务健康检查

```powershell
curl http://127.0.0.1:18923/?args=status
```

---

## 🔧 手动管理

```powershell
# 查看 QMD 服务日志
wsl tail -f /home/<WSL用户名>/qmd-server.log

# 重启 QMD 服务
wsl pkill -f qmd-server.js
wsl bash -c "source /home/<WSL用户名>/.bashrc && nohup node /home/<WSL用户名>/qmd-server.js > /home/<WSL用户名>/qmd-server.log 2>&1 &"

# 手动更新索引
curl "http://127.0.0.1:18923/?args=update"
curl "http://127.0.0.1:18923/?args=embed"

# 查看集合列表
curl "http://127.0.0.1:18923/?args=collection+list"

# 测试搜索
curl "http://127.0.0.1:18923/?args=query+%22test%22+-c+memory-root-main+--json"
```

---

## ⚠️ 故障排查

| 问题 | 解决方案 |
|------|----------|
| `qmd: command not found` | `wsl echo $PATH`，确认 `~/.bun/bin` 在 PATH 中 |
| 模型下载 `ETIMEDOUT` | 使用国内镜像手动下载（见 `docs/guide.md` 第二部分） |
| `collection add timed out` | 提前手动创建集合（见 `docs/guide.md` 步骤 7） |
| `MEMORY.md ENOENT` | `wsl touch /mnt/d/openclaw/workspace/MEMORY.md` |
| QMD 搜索超时 | 确认 HTTP 服务运行：`curl http://127.0.0.1:18923/?args=status` |
| `falling back to builtin` | QMD 失败自动回退 SQLite，检查服务日志 |
| 首次搜索很慢（16 秒+） | 正常，CPU 模式首次加载模型，后续 1-3 秒 |
| 想回退到内置 SQLite | 编辑 `openclaw.json`，删除 `memory` 块或设 `"backend": "sqlite"` |

---

## 🔄 回退方案

如果 QMD 出现问题，随时可以回退到 OpenClaw 内置 SQLite 记忆系统：

编辑 `openclaw.json`，删除或修改 `memory` 块：

```json
{
  "memory": {
    "backend": "sqlite"
  }
}
```

然后重启：`openclaw gateway restart`

> OpenClaw 会在 QMD 失败时**自动回退**到内置 SQLite，不会影响正常使用。

---

## 📚 参考链接

| 资源 | 链接 |
|------|------|
| QMD 官方仓库 | [github.com/tobi/qmd](https://github.com/tobi/qmd) |
| OpenClaw 官方仓库 | [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw) |
| OpenClaw Memory 文档 | [Memory Docs](https://github.com/openclaw/openclaw/blob/main/docs/concepts/memory.md) |
| QMD 安装配置指南 | [Clawee.dev](https://clawee.dev/guides/qmd-install-config) |
| GGUF 模型手动下载 | [Clawee.dev](https://clawee.dev/guides/qmd-cpu-gguf-install) |

---

## 🤝 贡献

欢迎提交 Issue 和 PR！

---

## 📄 License

[MIT](LICENSE)
