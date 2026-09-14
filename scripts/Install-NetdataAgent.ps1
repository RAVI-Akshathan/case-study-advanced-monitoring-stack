<#
.SYNOPSIS
    Downloads and silently installs Netdata agent on Windows Servers.
.DESCRIPTION
    Retrieves the latest Netdata MSI package from GitHub and runs an automated,
    logged installation using the TOKEN and ROOMS specified in environment variables.
#>

# Requires elevated privilege
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as an Administrator." -Category PermissionDenied
    exit 1
}

$ProjectName    = 'NETDATA'
$BaseFolder     = Join-Path $env:ProgramData "PowerShellScript\$ProjectName"
$script:LogFile = Join-Path $BaseFolder "LOG FILE\$($ProjectName)_GlobalLogFile.txt"
$MsiLogFile     = Join-Path $BaseFolder "LOG FILE\msi_install.log"
$MsiPath        = Join-Path $BaseFolder 'netdata-x64.msi'

$Token = $env:NETDATA_TOKEN
$Rooms = $env:NETDATA_ROOMS

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO','WARNING','ERROR','DEBUG')]
        [string]$Level = 'INFO',

        [Parameter()]
        [string]$LogFile = $script:LogFile,

        [Parameter()]
        [switch]$DisplayConsole
    )

    $ParentFolder = Split-Path -Path $LogFile -Parent
    $TimeStamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogEntry     = "[$TimeStamp] - [$Level] - $Message"

    try {
        if (-not (Test-Path -Path $ParentFolder)) {
            New-Item -Path $ParentFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        if (-not (Test-Path -Path $LogFile)) {
            New-Item -Path $LogFile -ItemType File -Force -ErrorAction Stop | Out-Null
        }

        Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Host "[$TimeStamp] - [ERROR] - Failed to write to log file '$LogFile' : $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    if ($DisplayConsole) {
        switch ($Level) {
            'ERROR'   { Write-Host $LogEntry -ForegroundColor Red }
            'WARNING' { Write-Host $LogEntry -ForegroundColor Yellow }
            'DEBUG'   { Write-Host $LogEntry -ForegroundColor Gray }
            default   { Write-Host $LogEntry -ForegroundColor White }
        }
    }
}

try {
    if (-not (Test-Path -Path $BaseFolder)) {
        New-Item -Path $BaseFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($Token) -or [string]::IsNullOrWhiteSpace($Rooms)) {
        throw "Set environment variables NETDATA_TOKEN and NETDATA_ROOMS before running this script."
    }

    $HostName = $env:COMPUTERNAME
    Write-Log -Message "Working on the following server: $HostName" -DisplayConsole
    Write-Log -Message "Initiating download of Netdata from GitHub..." -DisplayConsole

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $OldProgressPreference = $ProgressPreference
    
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri 'https://github.com/netdata/netdata/releases/latest/download/netdata-x64.msi' `
                          -OutFile $MsiPath `
                          -ErrorAction Stop
        Write-Log -Message "Package downloaded successfully to '$MsiPath'." -DisplayConsole
    }
    finally {
        $ProgressPreference = $OldProgressPreference
    }

    Write-Log -Message "Installation process is starting..." -DisplayConsole

    $MsiArguments = @(
        '/i'
        $MsiPath
        '/qn'
        "/L*v"
        "`"$MsiLogFile`""
        "TOKEN=$Token"
        "ROOMS=$Rooms"
    )

    $Process = Start-Process -FilePath 'msiexec.exe' `
                             -ArgumentList $MsiArguments `
                             -Wait `
                             -PassThru `
                             -NoNewWindow

    if ($Process.ExitCode -eq 0) {
        $Service = Get-Service -Name 'Netdata' -ErrorAction SilentlyContinue

        if ($Service) {
            Write-Log -Message "Netdata has been successfully installed." -DisplayConsole
        }
        else {
            Write-Log -Message "msiexec returned exit code 0, but the Netdata service was not found. Please verify manually." -Level WARNING -DisplayConsole
        }
    }
    else {
        Write-Log -Message "Netdata installation failed with exit code $($Process.ExitCode). Check detailed log at '$MsiLogFile'." -Level ERROR -DisplayConsole
        exit $Process.ExitCode
    }
}
catch {
    Write-Log -Message "Script failed: $($_.Exception.Message)" -Level ERROR -DisplayConsole
    throw
}
