# This script automates the cleanup of specified directories by reading paths from a configuration file (config.ini).
# The script supports multi-threading for efficient file deletion and allows for customizable logging.

# Get the script's directory and build the relative path to the config.ini file
$configFilePath = Join-Path -Path $PSScriptRoot -ChildPath "config.ini"

# Function to read and parse the INI configuration file
function Get-IniContent {
    param([string]$iniPath)
    
    $iniContent = Get-Content $iniPath | Where-Object { $_ -notmatch "^\s*#|^\s*$" }
    $currentSection = ''
    $iniHash = @{}

    foreach ($line in $iniContent) {
        # Check for section headers (e.g., [Paths])
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            if ($currentSection -eq 'Paths') {
                $iniHash[$currentSection] = @()
            } else {
                $iniHash[$currentSection] = @{}
            }
        # Parse key-value pairs within sections (e.g., LogLevel = debug)
        } elseif ($line -match '^(.*?)\s*=\s*(.*)$' -and $currentSection -ne 'Paths') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($key -eq 'LogRetentionDays' -or $key -eq 'DefaultThreadsCount') {
                $iniHash[$currentSection][$key] = [int]$value
            } else {
                $iniHash[$currentSection][$key] = $value
            }
        # Add paths to the 'Paths' section
        } elseif ($currentSection -eq 'Paths') {
            $iniHash[$currentSection] += $line
        }
    }
    return $iniHash
}

# Parse the config.ini file
$config = Get-IniContent $configFilePath

# Read Debug settings from the config file
$logLevel = $config["Debug"]["LogLevel"].ToLower()
$logDirectory = $config["Debug"]["LogDirectory"]
$logRetentionDays = [int]$config["Debug"]["LogRetentionDays"]

# Ensure the log directory is configured and exists
if (-not $logDirectory) {
    Write-Host "LogDirectory is not configured. Please check the config.ini."
    exit
}

# Create the log directory if it does not exist
if (-not (Test-Path $logDirectory)) {
    try {
        New-Item -ItemType Directory -Path $logDirectory -Force
    } catch {
        Write-Host "Failed to create log directory at '${logDirectory}'. Please check permissions."
        exit
    }
}

# Generate a log file name based on the current date and time
$currentDate = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "${logDirectory}\cleanup_log_${currentDate}.txt"

# Load the paths to be cleaned from the config file
$paths = $config["Paths"]

# Split the paths into smaller chunks for multi-threaded processing
$threadCount = $config["MultiThreads"]["DefaultThreadsCount"]
$chunkSize = [Math]::Ceiling($paths.Count / $threadCount)
$pathChunks = $paths | ForEach-Object -Begin { $chunk = @() } -Process {
    $chunk += $_
    if ($chunk.Count -eq $chunkSize) {
        $chunk
        $chunk = @()
    }
} | Where-Object { $_.Count -gt 0 }

# Global array to store all logs
$global:allLogs = @()

# Function to log messages based on the configured log level
function Write-Log {
    param (
        [string]$level,  # Log level (e.g., error, warning, info, debug)
        [string]$message
    )

    # Define log level priorities
    $levelsPriority = @{
        "none"    = 5
        "error"   = 4
        "warning" = 3
        "info"    = 2
        "debug"   = 1
    }

    # Check if the current log level is allowed to be logged
    if ($levelsPriority[$level] -ge $levelsPriority[$logLevel]) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "${timestamp} - [${level}] - ${message}"
        $global:allLogs += $logMessage
        Write-Host $logMessage  # Output to the console
    }
}

# Log the start of the cleanup process
Write-Log "info" "Cleanup script execution started."

# Start multi-threaded tasks to process the path chunks
$jobs = foreach ($chunk in $pathChunks) {
    Start-Job -ScriptBlock {
        param($paths, $logLevel)

        # Thread-specific log storage
        $threadLogs = @()
        $levelsPriority = @{
            "none"    = 5
            "error"   = 4
            "warning" = 3
            "info"    = 2
            "debug"   = 1
        }

        # Function to log messages within each thread
        function Write-ThreadLog {
            param (
                [string]$level,  # Log level
                [string]$message
            )

            # Check if the current log level is allowed to be logged
            if ($levelsPriority[$level] -ge $levelsPriority[$logLevel]) {
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $threadLogs += "${timestamp} - [${level}] - ${message}"
            }
        }

        # Process each path in the chunk
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

# Wait for all tasks to complete and collect logs
$jobs | ForEach-Object {
    $threadLogs = Receive-Job -Job $_
    $global:allLogs += $threadLogs

    # Ensure jobs are completed before removal
    Wait-Job -Job $_
    Remove-Job -Job $_
}

# Clean up old log files based on retention settings
Get-ChildItem -Path $logDirectory -Filter *.txt | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-$logRetentionDays)
} | Remove-Item -Force

# Log the end of the cleanup process
Write-Log "info" "Cleanup script execution completed."

# Write all collected logs to the log file
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
