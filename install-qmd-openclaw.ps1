#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows + WSL2 安装 QMD 并接入 OpenClaw 一键部署脚本

.DESCRIPTION
    自动完成以下操作：
    1. 检查/安装 WSL2 + Ubuntu
    2. 在 WSL2 中安装 Bun、QMD、SQLite
    3. 配置环境变量（.bashrc）
    4. 下载 QMD GGUF 模型（国内镜像）
    5. 创建 QMD 集合并构建索引
    6. 部署 QMD HTTP 常驻服务
    7. 创建 Windows 客户端脚本
    8. 配置 openclaw.json
    9. 设置开机自启

.NOTES
    以管理员身份运行 PowerShell，然后执行：
    Set-ExecutionPolicy Bypass -Scope Process -Force; .\install-qmd-openclaw.ps1
#>

param(
    [string]$WinUser = "",
    [string]$WslUser = "",
    [string]$OpenClawDir = "",
    [string]$QmdHttpPort = "18923"
)

# ============================================================
# 配置区域（可根据需要修改）
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ============================================================
# 工具函数
# ============================================================

function Write-Title($text) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Step($num, $text) {
    Write-Host ""
    Write-Host "[$num] $text" -ForegroundColor Yellow
}

function Write-Ok($text) {
    Write-Host "  [OK] $text" -ForegroundColor Green
}

function Write-Skip($text) {
    Write-Host "  [SKIP] $text" -ForegroundColor DarkYellow
}

function Write-Warn($text) {
    Write-Host "  [WARN] $text" -ForegroundColor Red
}

function Write-Info($text) {
    Write-Host "  [INFO] $text" -ForegroundColor Gray
}

function Test-Command($cmd) {
    try { Get-Command $cmd -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

function Invoke-Wsl($command) {
    $result = wsl -d Ubuntu -- bash -c $command 2>&1
    return $result
}

# ============================================================
# 自动检测配置
# ============================================================

Write-Title "QMD + OpenClaw 一键部署脚本"

# 检测 Windows 用户名
if (-not $WinUser) {
    $WinUser = $env:USERNAME
}
Write-Info "Windows 用户: $WinUser"

# 检测 WSL 用户名
if (-not $WslUser) {
    $detected = Invoke-Wsl "whoami"
    if ($detected -and $detected -notmatch "error") {
        $WslUser = $detected.Trim()
    } else {
        $WslUser = Read-Host "  请输入 WSL2 中的 Linux 用户名"
    }
}
Write-Info "WSL 用户: $WslUser"

# 检测 OpenClaw 目录
if (-not $OpenClawDir) {
    $possiblePaths = @(
        "D:\openclaw",
        "C:\Users\$WinUser\.openclaw",
        "C:\openclaw"
    )
    foreach ($p in $possiblePaths) {
        if (Test-Path $p) {
            $OpenClawDir = $p
            break
        }
    }
    if (-not $OpenClawDir) {
        $OpenClawDir = Read-Host "  请输入 OpenClaw 安装目录（如 D:\openclaw）"
    }
}
Write-Info "OpenClaw 目录: $OpenClawDir"

$WslHome = "/home/$WslUser"
$OpenClawBinDir = "C:\Users\$WinUser\.openclaw\bin"
$OpenClawConfigDir = "C:\Users\$WinUser\.openclaw"
$OpenClawJsonPath = "$OpenClawConfigDir\openclaw.json"

# 检测 OpenClaw workspace 路径
$workspacePaths = @(
    "$OpenClawDir\workspace",
    "$OpenClawConfigDir\workspace"
)
$OpenClawWorkspace = ""
foreach ($p in $workspacePaths) {
    if (Test-Path $p) {
        $OpenClawWorkspace = $p
        break
    }
}
if (-not $OpenClawWorkspace) {
    $OpenClawWorkspace = "$OpenClawDir\workspace"
}

# 转换为 WSL 路径
$drive = $OpenClawWorkspace.Substring(0,1).ToLower()
$rest = $OpenClawWorkspace.Substring(2).Replace("\","/")
$WslWorkspace = "/mnt/$drive$rest"

Write-Info "OpenClaw Workspace: $OpenClawWorkspace"
Write-Info "WSL Workspace 路径: $WslWorkspace"

# ============================================================
# 步骤 1：检查/安装 WSL2
# ============================================================

Write-Step 1 "检查 WSL2"

$wslInstalled = $false
try {
    $wslVer = wsl --version 2>&1
    if ($wslVer -notmatch "error") {
        $wslInstalled = $true
    }
} catch {}

if (-not $wslInstalled) {
    Write-Info "正在安装 WSL2..."
    wsl --install -d Ubuntu-24.04
    Write-Warn "WSL2 安装完成，需要重启电脑。重启后重新运行此脚本。"
    Read-Host "按 Enter 键重启电脑"
    Restart-Computer
    exit
} else {
    Write-Ok "WSL2 已安装"
}

# 检查 Ubuntu 发行版
$ubuntuInstalled = $false
try {
    $distros = wsl --list --quiet 2>&1
    if ($distros -match "Ubuntu") {
        $ubuntuInstalled = $true
    }
} catch {}

if (-not $ubuntuInstalled) {
    Write-Info "正在安装 Ubuntu..."
    wsl --install -d Ubuntu-24.04
    Write-Warn "Ubuntu 安装完成，请从开始菜单打开 Ubuntu 完成初始化设置，然后重新运行此脚本。"
    Read-Host "按 Enter 键退出"
    exit
} else {
    Write-Ok "Ubuntu 已安装"
}

# 测试 WSL 连接
$testResult = Invoke-Wsl "echo ok"
if ($testResult -match "ok") {
    Write-Ok "WSL2 连接正常"
} else {
    Write-Warn "WSL2 连接失败，请确保 Ubuntu 已完成初始化。"
    exit 1
}

# ============================================================
# 步骤 2：在 WSL2 中安装 Bun
# ============================================================

Write-Step 2 "安装 Bun"

$bunVer = Invoke-Wsl "bun --version 2>/dev/null"
if ($bunVer -and $bunVer -match "\d+") {
    Write-Ok "Bun 已安装 (版本: $($bunVer.Trim()))"
} else {
    Write-Info "正在安装 Bun..."
    Invoke-Wsl "curl -fsSL https://bun.sh/install | bash" | Out-Null
    Start-Sleep -Seconds 2
    $bunVer = Invoke-Wsl "source ~/.bashrc && bun --version 2>/dev/null"
    if ($bunVer -and $bunVer -match "\d+") {
        Write-Ok "Bun 安装成功 (版本: $($bunVer.Trim()))"
    } else {
        Write-Warn "Bun 安装失败，请手动在 WSL2 中执行: curl -fsSL https://bun.sh/install | bash"
    }
}

# ============================================================
# 步骤 3：在 WSL2 中安装 QMD
# ============================================================

Write-Step 3 "安装 QMD"

$qmdVer = Invoke-Wsl "source ~/.bashrc && qmd --version 2>/dev/null"
if ($qmdVer -and $qmdVer -match "\d+") {
    Write-Ok "QMD 已安装 (版本: $($qmdVer.Trim()))"
} else {
    Write-Info "正在安装 QMD（通过 Bun）..."
    Invoke-Wsl "source ~/.bashrc && bun install -g https://github.com/tobi/qmd" | Out-Null
    Start-Sleep -Seconds 3

    # 如果 Bun 安装失败，尝试 npm
    $qmdVer2 = Invoke-Wsl "source ~/.bashrc && qmd --version 2>/dev/null"
    if (-not ($qmdVer2 -and $qmdVer2 -match "\d+")) {
        Write-Info "Bun 安装失败，尝试 npm..."
        Invoke-Wsl "source ~/.bashrc && npm install -g @tobilu/qmd" | Out-Null
        Start-Sleep -Seconds 3
    }

    $qmdVer3 = Invoke-Wsl "source ~/.bashrc && qmd --version 2>/dev/null"
    if ($qmdVer3 -and $qmdVer3 -match "\d+") {
        Write-Ok "QMD 安装成功 (版本: $($qmdVer3.Trim()))"
    } else {
        Write-Warn "QMD 安装失败，请手动在 WSL2 中执行: bun install -g https://github.com/tobi/qmd"
    }
}

# ============================================================
# 步骤 4：安装 SQLite
# ============================================================

Write-Step 4 "安装 SQLite"

$sqliteVer = Invoke-Wsl "sqlite3 --version 2>/dev/null"
if ($sqliteVer -and $sqliteVer -match "\d+") {
    Write-Ok "SQLite 已安装 (版本: $($sqliteVer.Trim()))"
} else {
    Write-Info "正在安装 SQLite..."
    Invoke-Wsl "sudo apt update && sudo apt install -y sqlite3 build-essential cmake" | Out-Null
    Start-Sleep -Seconds 2
    $sqliteVer = Invoke-Wsl "sqlite3 --version 2>/dev/null"
    if ($sqliteVer -and $sqliteVer -match "\d+") {
        Write-Ok "SQLite 安装成功"
    } else {
        Write-Warn "SQLite 安装失败"
    }
}

# ============================================================
# 步骤 5：配置环境变量
# ============================================================

Write-Step 5 "配置 WSL2 环境变量"

$bashrcContent = @"

# ========== QMD for OpenClaw 配置 ==========
export NODE_LLAMA_CPP_CUDA=false

WIN_USER=`$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
STATE_DIR="/mnt/c/Users/`${WIN_USER}/.openclaw"
AGENT_ID="main"
export XDG_CONFIG_HOME="`$STATE_DIR/agents/`$AGENT_ID/qmd/xdg-config"
export XDG_CACHE_HOME="$WslHome/.cache"

export PATH="`$HOME/.bun/bin:`$HOME/.npm-global/bin:`$PATH"
"@

# 写入 .bashrc（追加，不覆盖）
$checkResult = Invoke-Wsl "grep -c 'QMD for OpenClaw' ~/.bashrc 2>/dev/null"
if ($checkResult -match "^[1-9]") {
    Write-Ok "环境变量已配置（已存在）"
} else {
    # 使用 heredoc 写入
    $escapedContent = $bashrcContent -replace '"', '\"'
    Invoke-Wsl "cat >> ~/.bashrc << 'BASHEOF'
$bashrcContent
BASHEOF" | Out-Null
    Write-Ok "环境变量已写入 ~/.bashrc"
}

# 验证
$xdgConfig = Invoke-Wsl "source ~/.bashrc && echo `$XDG_CONFIG_HOME"
$xdgCache = Invoke-Wsl "source ~/.bashrc && echo `$XDG_CACHE_HOME"
Write-Info "XDG_CONFIG_HOME = $xdgConfig"
Write-Info "XDG_CACHE_HOME = $xdgCache"

# ============================================================
# 步骤 6：下载 QMD 模型
# ============================================================

Write-Step 6 "下载 QMD GGUF 模型（国内镜像）"

$modelDir = "$WslHome/.cache/qmd/models"
$modelCheck = Invoke-Wsl "ls $modelDir/*.gguf 2>/dev/null | wc -l"
$modelCount = 0
if ($modelCheck -match "\d+") { $modelCount = [int]$modelCheck.Trim() }

if ($modelCount -ge 3) {
    Write-Ok "3 个模型已存在，跳过下载"
} else {
    Write-Info "正在下载 3 个 GGUF 模型（约 2GB，使用 hf-mirror.com）..."

    Invoke-Wsl "mkdir -p $modelDir" | Out-Null

    $models = @(
        @{ url = "https://hf-mirror.com/ggml-org/embeddinggemma-300M-GGUF/resolve/main/embeddinggemma-300M-Q8_0.gguf"; name = "embeddinggemma-300M-Q8_0.gguf" },
        @{ url = "https://hf-mirror.com/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/resolve/main/qwen3-reranker-0.6b-q8_0.gguf"; name = "qwen3-reranker-0.6b-q8_0.gguf" },
        @{ url = "https://hf-mirror.com/tobil/qmd-query-expansion-1.7B/resolve/main/qmd-query-expansion-1.7B-Q4_K_M.gguf"; name = "qmd-query-expansion-1.7B-Q4_K_M.gguf" }
    )

    foreach ($m in $models) {
        $exists = Invoke-Wsl "test -f $modelDir/$($m.name) && echo yes || echo no"
        if ($exists.Trim() -eq "yes") {
            Write-Ok "$($m.name) 已存在，跳过"
        } else {
            Write-Info "下载 $($m.name)..."
            Invoke-Wsl "cd $modelDir && wget -c '$($m.url)' -O $($m.name)" | Out-Null
            $check = Invoke-Wsl "test -f $modelDir/$($m.name) && echo yes || echo no"
            if ($check.Trim() -eq "yes") {
                Write-Ok "$($m.name) 下载完成"
            } else {
                Write-Warn "$($m.name) 下载失败，请手动下载"
            }
        }
    }
}

# 显示已下载的模型
$modelList = Invoke-Wsl "ls -lh $modelDir/*.gguf 2>/dev/null"
if ($modelList) {
    Write-Info "已下载的模型："
    $modelList | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
}

# ============================================================
# 步骤 7：创建 QMD 集合并构建索引
# ============================================================

Write-Step 7 "创建 QMD 集合并构建索引"

# 确保 workspace 文件存在
Invoke-Wsl "mkdir -p $WslWorkspace/memory" | Out-Null
Invoke-Wsl "touch $WslWorkspace/MEMORY.md" | Out-Null
Write-Ok "MEMORY.md 和 memory/ 目录已就绪"

# 创建集合
$collections = @(
    @{ path = $WslWorkspace; name = "memory-root-main"; mask = "MEMORY.md" },
    @{ path = $WslWorkspace; name = "memory-alt-main"; mask = "memory.md" },
    @{ path = "$WslWorkspace/memory"; name = "memory-dir-main"; mask = "**/*.md" }
)

foreach ($c in $collections) {
    $exists = Invoke-Wsl "source ~/.bashrc && qmd collection list 2>/dev/null" 
    if ($exists -match $c.name) {
        Write-Skip "集合 $($c.name) 已存在"
    } else {
        Write-Info "创建集合 $($c.name)..."
        Invoke-Wsl "source ~/.bashrc && qmd collection add '$($c.path)' --name '$($c.name)' --mask '$($c.mask)'" | Out-Null
        Start-Sleep -Seconds 2
        Write-Ok "集合 $($c.name) 创建完成"
    }
}

# 显示集合列表
$colList = Invoke-Wsl "source ~/.bashrc && qmd collection list 2>/dev/null"
if ($colList) {
    Write-Info "当前集合列表："
    $colList | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
}

# 更新索引
Write-Info "更新文件索引..."
Invoke-Wsl "source ~/.bashrc && qmd update" | Out-Null
Write-Ok "索引更新完成"

# 生成向量嵌入
Write-Info "生成向量嵌入（首次较慢）..."
Invoke-Wsl "source ~/.bashrc && qmd embed" | Out-Null
Write-Ok "向量嵌入完成"

# 预热搜索
Write-Info "预热搜索..."
Invoke-Wsl "source ~/.bashrc && qmd query 'test' -c memory-root-main --json" | Out-Null
Write-Ok "QMD 就绪"

# ============================================================
# 步骤 8：部署 QMD HTTP 常驻服务
# ============================================================

Write-Step 8 "部署 QMD HTTP 常驻服务"

# 创建 qmd-server.js
$qmdServerJs = @'
const http = require("http");
const { execSync } = require("child_process");

const PORT = PORT_PLACEHOLDER;

function qmd(args) {
  try {
    const cmd = `qmd ${args}`;
    const result = execSync(cmd, {
      timeout: 120000,
      encoding: "utf-8",
      env: {
        ...process.env,
        XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME,
        XDG_CACHE_HOME: process.env.XDG_CACHE_HOME,
      },
    });
    return { ok: true, output: result };
  } catch (e) {
    return { ok: false, output: e.stderr || e.message };
  }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const args = url.searchParams.get("args") || "";
  console.log(`[qmd-server] ${args}`);
  const result = qmd(args);
  res.writeHead(result.ok ? 200 : 500, { "Content-Type": "application/json" });
  res.end(JSON.stringify(result));
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[qmd-server] listening on 127.0.0.1:${PORT}`);
});
'@

$qmdServerJs = $qmdServerJs -replace "PORT_PLACEHOLDER", $QmdHttpPort

# 写入 WSL2
$serverPath = "$WslHome/qmd-server.js"
$tempFile = [System.IO.Path]::GetTempFileName()
$qmdServerJs | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline
$wslTempPath = Invoke-Wsl "wslpath '$tempFile'" 2>$null
if (-not $wslTempPath) { $wslTempPath = $tempFile }
# 直接用 bash 写入
$qmdServerJsB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($qmdServerJs))
Invoke-Wsl "echo '$qmdServerJsB64' | base64 -d > $serverPath" | Out-Null
Write-Ok "qmd-server.js 已创建"

# 停止已有的 qmd-server 进程
Invoke-Wsl "pkill -f qmd-server.js 2>/dev/null" | Out-Null
Start-Sleep -Seconds 1

# 启动服务
Write-Info "启动 QMD HTTP 服务（端口: $QmdHttpPort）..."
Invoke-Wsl "source ~/.bashrc && nohup node $serverPath > $WslHome/qmd-server.log 2>&1 &" | Out-Null
Start-Sleep -Seconds 3

# 验证服务
$healthCheck = Invoke-Wsl "curl -s http://127.0.0.1:$QmdHttpPort/?args=--version 2>/dev/null"
if ($healthCheck -match '"ok":true') {
    Write-Ok "QMD HTTP 服务启动成功"
} else {
    Write-Warn "QMD HTTP 服务启动失败，请检查日志: $WslHome/qmd-server.log"
}

# 预热服务
Write-Info "预热服务（加载模型到内存，首次较慢）..."
Invoke-Wsl "curl -s http://127.0.0.1:$QmdHttpPort/?args=status > /dev/null 2>&1" | Out-Null
Invoke-Wsl "curl -s http://127.0.0.1:$QmdHttpPort/?args=update > /dev/null 2>&1" | Out-Null
Invoke-Wsl "curl -s http://127.0.0.1:$QmdHttpPort/?args=embed > /dev/null 2>&1" | Out-Null
Write-Ok "服务预热完成"

# ============================================================
# 步骤 9：创建 Windows 客户端脚本
# ============================================================

Write-Step 9 "创建 Windows 客户端脚本"

if (-not (Test-Path $OpenClawBinDir)) {
    New-Item -Path $OpenClawBinDir -ItemType Directory -Force | Out-Null
}

# 创建 qmd-http.cmd
$qmdHttpCmd = "@echo off`r`ncurl -s `"http://127.0.0.1:$QmdHttpPort/?args=%*`""
$qmdHttpCmd | Out-File -FilePath "$OpenClawBinDir\qmd-http.cmd" -Encoding ASCII
Write-Ok "qmd-http.cmd 已创建: $OpenClawBinDir\qmd-http.cmd"

# 测试
$testCmd = & "$OpenClawBinDir\qmd-http.cmd" --version 2>&1
if ($testCmd -match '"ok":true') {
    Write-Ok "客户端脚本测试通过"
} else {
    Write-Warn "客户端脚本测试失败"
}

# ============================================================
# 步骤 10：配置 openclaw.json
# ============================================================

Write-Step 10 "配置 openclaw.json"

$qmdCommand = "$OpenClawBinDir\qmd-http.cmd" -replace "\\", "\\\\"

$memoryConfig = @{
    backend = "qmd"
    citations = "auto"
    qmd = @{
        command = $qmdCommand
        includeDefaultMemory = $true
        searchMode = "search"
        update = @{
            interval = "5m"
            debounceMs = 15000
            onBoot = $true
            waitForBootSync = $false
        }
        limits = @{
            maxResults = 6
            timeoutMs = 30000
        }
        scope = @{
            default = "deny"
            rules = @(
                @{ action = "allow"; match = @{ chatType = "direct" } }
            )
        }
    }
}

if (Test-Path $OpenClawJsonPath) {
    Write-Info "发现已有 openclaw.json，正在合并配置..."

    try {
        $existingJson = Get-Content $OpenClawJsonPath -Raw | ConvertFrom-Json

        # 如果已有 memory 配置，备份
        if ($existingJson.memory) {
            $backupPath = "$OpenClawJsonPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Copy-Item $OpenClawJsonPath $backupPath
            Write-Info "已备份原配置: $backupPath"
        }

        # 合并 memory 配置
        $existingJson | Add-Member -NotePropertyName "memory" -NotePropertyValue $memoryConfig -Force

        $existingJson | ConvertTo-Json -Depth 10 | Out-File -FilePath $OpenClawJsonPath -Encoding UTF8
        Write-Ok "openclaw.json 配置已更新"
    } catch {
        Write-Warn "自动合并失败，请手动添加 memory 配置"
        Write-Info "需要添加的配置："
        Write-Host ($memoryConfig | ConvertTo-Json -Depth 10) -ForegroundColor Gray
    }
} else {
    Write-Info "未找到 openclaw.json，创建新文件..."
    $newConfig = @{ memory = $memoryConfig }
    $newConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $OpenClawJsonPath -Encoding UTF8
    Write-Ok "openclaw.json 已创建: $OpenClawJsonPath"
}

# ============================================================
# 步骤 11：设置开机自启
# ============================================================

Write-Step 11 "设置开机自启"

$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$vbsContent = "Set ws = CreateObject(`"Wscript.Shell`")`r`nws.Run `"wsl -d Ubuntu -- bash -c '""source $WslHome/.bashrc && nohup node $WslHome/qmd-server.js > $WslHome/qmd-server.log 2>&1 &'""`", 0"
$vbsPath = "$OpenClawBinDir\start-qmd-server.vbs"
$vbsContent | Out-File -FilePath $vbsPath -Encoding ASCII
Copy-Item $vbsPath "$startupFolder\start-qmd-server.vbs" -Force
Write-Ok "开机自启已配置: $startupFolder\start-qmd-server.vbs"

# ============================================================
# 步骤 12：重启 OpenClaw Gateway
# ============================================================

Write-Step 12 "重启 OpenClaw Gateway"

if (Test-Command "openclaw") {
    openclaw gateway restart 2>&1 | Out-Null
    Write-Ok "OpenClaw Gateway 已重启"
} else {
    Write-Warn "未找到 openclaw 命令，请手动重启: openclaw gateway restart"
}

# ============================================================
# 完成
# ============================================================

Write-Title "部署完成"

Write-Host ""
Write-Host "  部署摘要：" -ForegroundColor White
Write-Host "  --------" -ForegroundColor White
Write-Host "  WSL 用户:           $WslUser" -ForegroundColor Gray
Write-Host "  OpenClaw 目录:      $OpenClawDir" -ForegroundColor Gray
Write-Host "  QMD HTTP 端口:      $QmdHttpPort" -ForegroundColor Gray
Write-Host "  客户端脚本:         $OpenClawBinDir\qmd-http.cmd" -ForegroundColor Gray
Write-Host "  配置文件:           $OpenClawJsonPath" -ForegroundColor Gray
Write-Host "  开机自启:           已启用" -ForegroundColor Gray
Write-Host ""

Write-Host "  验证步骤：" -ForegroundColor White
Write-Host "  --------" -ForegroundColor White
Write-Host "  1. 查看日志: openclaw gateway logs" -ForegroundColor Gray
Write-Host "     搜索 'Using QMD memory backend' 确认成功" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. 在 OpenClaw 对话中测试：" -ForegroundColor Gray
Write-Host "     发送: 请记住：我叫小明" -ForegroundColor Gray
Write-Host "     等几分钟后新对话问: 我叫什么名字？" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. 手动管理 QMD 服务：" -ForegroundColor Gray
Write-Host "     查看日志: wsl tail -f $WslHome/qmd-server.log" -ForegroundColor Gray
Write-Host "     重启服务: wsl pkill -f qmd-server.js && wsl bash -c 'source $WslHome/.bashrc && nohup node $WslHome/qmd-server.js > $WslHome/qmd-server.log 2>&1 &'" -ForegroundColor Gray
Write-Host "     测试服务: curl http://127.0.0.1:$QmdHttpPort/?args=status" -ForegroundColor Gray
Write-Host ""

Write-Host "  回退方案：" -ForegroundColor White
Write-Host "  --------" -ForegroundColor White
Write-Host "  编辑 $OpenClawJsonPath" -ForegroundColor Gray
Write-Host "  删除 memory 块或设置 `"backend`": `"sqlite`"，然后 openclaw gateway restart" -ForegroundColor Gray
Write-Host ""
