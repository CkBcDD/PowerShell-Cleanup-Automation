# 获取脚本所在的目录，并构建配置文件的相对路径
$configFilePath = Join-Path -Path $PSScriptRoot -ChildPath "config.ini"

# 读取INI文件的函数
function Get-IniContent {
    param([string]$iniPath)
    
    $iniContent = Get-Content $iniPath | Where-Object { $_ -notmatch "^\s*#|^\s*$" }
    $currentSection = ''
    $iniHash = @{}

    foreach ($line in $iniContent) {
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            if ($currentSection -eq 'Paths') {
                $iniHash[$currentSection] = @()
            } else {
                $iniHash[$currentSection] = @{}
            }
        } elseif ($line -match '^(.*?)\s*=\s*(.*)$' -and $currentSection -ne 'Paths') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($key -eq 'LogRetentionDays' -or $key -eq 'DefaultThreadsCount') {
                $iniHash[$currentSection][$key] = [int]$value
            } else {
                $iniHash[$currentSection][$key] = $value
            }
        } elseif ($currentSection -eq 'Paths') {
            $iniHash[$currentSection] += $line
        }
    }
    return $iniHash
}

# 解析配置文件
$config = Get-IniContent $configFilePath

# 读取 Debug 部分的配置信息
$logLevel = $config["Debug"]["LogLevel"].ToLower()
$logDirectory = $config["Debug"]["LogDirectory"]
$logRetentionDays = [int]$config["Debug"]["LogRetentionDays"]

# 检查日志目录是否配置正确
if (-not $logDirectory) {
    Write-Host "LogDirectory is not configured. Please check the config.ini."
    exit
}

# 创建日志目录（如果不存在）
if (-not (Test-Path $logDirectory)) {
    try {
        New-Item -ItemType Directory -Path $logDirectory -Force
    } catch {
        Write-Host "Failed to create log directory at '${logDirectory}'. Please check permissions."
        exit
    }
}

# 获取当前日期，用于日志文件名
$currentDate = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "${logDirectory}\cleanup_log_${currentDate}.txt"

# 加载路径
$paths = $config["Paths"]

# 将路径列表分割为多个子列表
$threadCount = $config["MultiThreads"]["DefaultThreadsCount"]
$chunkSize = [Math]::Ceiling($paths.Count / $threadCount)
$pathChunks = $paths | ForEach-Object -Begin { $chunk = @() } -Process {
    $chunk += $_
    if ($chunk.Count -eq $chunkSize) {
        $chunk
        $chunk = @()
    }
} | Where-Object { $_.Count -gt 0 }

# 主线程的日志存储
$global:allLogs = @()

# 日志记录函数，根据级别控制输出
function Write-Log {
    param (
        [string]$level,  # 日志级别
        [string]$message
    )

    # 设置日志优先级
    $levelsPriority = @{
        "none"    = 5
        "error"   = 4
        "warning" = 3
        "info"    = 2
        "debug"   = 1
    }

    # 检查日志级别是否允许输出
    if ($levelsPriority[$level] -ge $levelsPriority[$logLevel]) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "${timestamp} - [${level}] - ${message}"
        $global:allLogs += $logMessage
        Write-Host $logMessage  # 输出到控制台
    }
}

# 添加基础日志记录
Write-Log "info" "Cleanup script execution started."

# 启动多线程任务
$jobs = foreach ($chunk in $pathChunks) {
    Start-Job -ScriptBlock {
        param($paths, $logLevel)

        # 线程内日志存储
        $threadLogs = @()
        $levelsPriority = @{
            "none"    = 5
            "error"   = 4
            "warning" = 3
            "info"    = 2
            "debug"   = 1
        }

        function Write-ThreadLog {
            param (
                [string]$level,  # 日志级别
                [string]$message
            )

            # 检查日志级别是否允许输出
            if ($levelsPriority[$level] -ge $levelsPriority[$logLevel]) {
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $threadLogs += "${timestamp} - [${level}] - ${message}"
            }
        }

        foreach ($path in $paths) {
            try {
                Write-ThreadLog "info" "Starting deletion of ${path}"
                
                if (Test-Path $path) {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                    Write-ThreadLog "info" "Successfully cleaned: ${path}"
                } else {
                    Write-ThreadLog "warning" "Path not found: ${path}"
                }
            } catch {
                Write-ThreadLog "error" "Failed to clean ${path}: ${_.Exception.Message}"
            }
        }

        Write-ThreadLog "debug" "Thread completed"
        return $threadLogs
    } -ArgumentList $chunk, $logLevel
}

# 等待所有任务完成，并收集日志
$jobs | ForEach-Object {
    $threadLogs = Receive-Job -Job $_
    $global:allLogs += $threadLogs

    # 确保作业已完成后再删除
    Wait-Job -Job $_
    Remove-Job -Job $_
}

# 清理旧日志文件
Get-ChildItem -Path $logDirectory -Filter *.txt | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-$logRetentionDays)
} | Remove-Item -Force

# 结束日志
Write-Log "info" "Cleanup script execution completed."

# 写入所有日志到文件
if ($global:allLogs.Count -gt 0) {
    try {
        $global:allLogs | ForEach-Object {
            Add-Content -Path $logFile -Value $_
        }
    } catch {
        Write-Host "Failed to write logs to file: $logFile"
    }
} else {
    Write-Host "No logs to write."
}
