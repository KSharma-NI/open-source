<#
.SYNOPSIS
  Run LabVIEW unit tests in a Docker container.

.DESCRIPTION
  Pulls the specified LabVIEW Docker image, sets up VIPM and LUnit,
  and executes unit tests inside the container.

.PARAMETER DockerImage
  Docker image to use (e.g., "nationalinstruments/labview:2026q1-windows").

.PARAMETER LVVersion
  LabVIEW version (e.g., "2026").

.PARAMETER LVBitness
  LabVIEW bitness ("32" or "64").

.PARAMETER ProjectPath
  Path to the LabVIEW project file (*.lvproj) relative to working directory.

.PARAMETER WorkspacePath
  Path to mount as /workspace in the container (defaults to current directory).

.PARAMETER VIPMConfigDir
  Path to directory containing VIPM configuration files (jki.conf, Settings.ini).

.PARAMETER OpenProjectBeforeRun
  If present, opens the project before running tests.

.EXAMPLE
  .\RunUnitTestsDocker.ps1 -DockerImage "nationalinstruments/labview:2026q1-windows" -LVVersion "2026" -LVBitness "64"

.NOTES
  [REQ-041] Run LabVIEW unit tests in Docker container with VIPM and LUnit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DockerImage,

    [Parameter(Mandatory = $true)]
    [string]$LVVersion,

    [Parameter(Mandatory = $true)]
    [ValidateSet("32", "64")]
    [string]$LVBitness,

    [Parameter(Mandatory = $false)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $false)]
    [string]$WorkspacePath = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [string]$VIPMConfigDir,

    [Parameter(Mandatory = $false)]
    [switch]$OpenProjectBeforeRun,

    [Parameter(Mandatory = $false)]
    [string]$VipmInstallerUrl = "https://packages.jki.net/vipm/preview/vipm-setup-latest-preview.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Write-Information "=== Running LabVIEW Tests in Docker ===" -InformationAction Continue
    Write-Information "Docker Image: $DockerImage" -InformationAction Continue
    Write-Information "LabVIEW Version: $LVVersion ($LVBitness-bit)" -InformationAction Continue
    
    # Pull Docker image
    Write-Information "Pulling Docker image..." -InformationAction Continue
    docker pull $DockerImage
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to pull Docker image: $DockerImage"
    }

    # Determine script directory (where this script and helpers are located)
    $ScriptDir = $PSScriptRoot
    Write-Verbose "Script directory: $ScriptDir"
    Write-Verbose "Workspace path: $WorkspacePath"

    $volumeMounts = @(
        '-v', "${WorkspacePath}:C:\workspace",
        '-v', "${ScriptDir}:C:\scripts"
    )
    
    # Add VIPM config volume if provided
    if ($VIPMConfigDir -and (Test-Path $VIPMConfigDir)) {
        Write-Information "Mounting VIPM configuration from: $VIPMConfigDir" -InformationAction Continue
        $volumeMounts += @('-v', "${VIPMConfigDir}:C:\vipm-config")
    }

    # Base docker run arguments
    $baseDockerArgs = @(
        'run',
        '--rm'
    ) + $volumeMounts + @(
        '-w', 'C:\workspace',
        $DockerImage
    )

    # Step 1: Setup VIPM and LUnit inside container
    Write-Information "Setting up VIPM and LUnit in container..." -InformationAction Continue

    $setupScriptBlock = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $output = "[$timestamp] [$Level] $Message"
    Write-Output $output
}

try {
    Write-Log "Setting up LUnit for LabVIEW {LVVersion} ({LVBitness}-bit)"

    # Configure VIPM if config directory provided
    if (Test-Path 'C:\vipm-config') {
        Write-Log "Configuring VIPM from provided config directory..."
        
        $jkiDir = "C:\ProgramData\JKI"
        $vipmDir = "C:\ProgramData\JKI\VIPM"
        
        New-Item -ItemType Directory -Path $jkiDir -Force | Out-Null
        New-Item -ItemType Directory -Path $vipmDir -Force | Out-Null
        
        $sourceJkiConf = "C:\vipm-config\jki.conf"
        if (Test-Path $sourceJkiConf) {
            $destJkiConf = Join-Path $jkiDir "jki.conf"
            Copy-Item -Path $sourceJkiConf -Destination $destJkiConf -Force
            Write-Log "Copied jki.conf to $destJkiConf"
        } else {
            Write-Log "WARNING: jki.conf not found at $sourceJkiConf" "WARN"
        }
        
        $sourceSettingsIni = "C:\vipm-config\Settings.ini"
        if (Test-Path $sourceSettingsIni) {
            $destSettingsIni = Join-Path $vipmDir "Settings.ini"
            Copy-Item -Path $sourceSettingsIni -Destination $destSettingsIni -Force
            Write-Log "Copied Settings.ini to $destSettingsIni"
        } else {
            Write-Log "WARNING: Settings.ini not found at $sourceSettingsIni" "WARN"
        }
        
        Write-Log "VIPM configuration applied successfully"
    } else {
        Write-Log "No VIPM configuration provided, using defaults"
    }
    
    $VipmExe = "C:\Program Files\JKI\VI Package Manager\support\vipm.exe"
    
    # Check if VIPM is already installed
    if (Test-Path $VipmExe) {
        Write-Log "VIPM is already installed at $VipmExe"
    } else {
        Write-Log "VIPM not found. Installing VIPM..."
        
        $VipmInstallerPath = Join-Path $env:TEMP "vipm-setup.exe"
        $VipmInstallerUrl = '{VipmInstallerUrl}'
        
        Write-Log "Downloading VIPM from $VipmInstallerUrl..."
        Invoke-WebRequest -Uri $VipmInstallerUrl -OutFile $VipmInstallerPath
        
        if (-not (Test-Path $VipmInstallerPath)) {
            throw "Failed to download VIPM installer to $VipmInstallerPath"
        }
        
        $installerSize = (Get-Item $VipmInstallerPath).Length / 1MB
        Write-Log ("Downloaded installer size: {0:F2} MB" -f $installerSize)
        
        Write-Log "Installing VIPM..."
        
        $process = Start-Process -FilePath $VipmInstallerPath `
                                 -ArgumentList "/quiet", "/norestart" `
                                 -Wait `
                                 -PassThru
        
        $exitCode = $process.ExitCode
        
        if ($exitCode -eq 0) {
            Write-Log "VIPM installed successfully"
            
            if (Test-Path $VipmInstallerPath) {
                Remove-Item $VipmInstallerPath -Force
            }
        } else {
            throw "VIPM installation failed with exit code: $exitCode"
        }
        
        if (-not (Test-Path $VipmExe)) {
            throw "VIPM executable not found at $VipmExe after installation"
        }
    }
    
    # Configure LabVIEW settings before installing packages
    Write-Log "Configuring LabVIEW settings..."
    
    $LabVIEWBasePath = if ('{LVBitness}' -eq "64") {
        "C:\Program Files\National Instruments\LabVIEW {LVVersion}"
    } else {
        "C:\Program Files (x86)\National Instruments\LabVIEW {LVVersion}"
    }
    
    $IniPath = Join-Path $LabVIEWBasePath "LabVIEW.ini"
    $LabVIEWExePath = Join-Path $LabVIEWBasePath "LabVIEW.exe"
    
    $RequiredSettings = @(
        "server.tcp.enabled=TRUE",
        "server.tcp.access=+127.0.0.1;+localhost;+*",
        "server.viscripting.ShowScriptingOperationsInEditor=TRUE"
    )
    
    if (-not (Test-Path $IniPath)) {
        Write-Log "LabVIEW.ini not found at $IniPath"
        
        if (-not (Test-Path $LabVIEWExePath)) {
            throw "LabVIEW executable not found at $LabVIEWExePath. Ensure LabVIEW {LVVersion} ({LVBitness}-bit) is installed."
        }
        
        Write-Log "Launching LabVIEW to generate ini file..."
        
        $lvProcess = Start-Process -FilePath $LabVIEWExePath -PassThru
        Write-Log "Waiting 60 seconds for LabVIEW to generate ini file..."
        Start-Sleep -Seconds 60
        
        if (-not $lvProcess.HasExited) {
            Stop-Process -Id $lvProcess.Id -Force -ErrorAction SilentlyContinue
            Write-Log "LabVIEW closed"
        }
        
        if (-not (Test-Path $IniPath)) {
            throw "INI file not found at $IniPath after launching LabVIEW"
        }
    }
    
    $CurrentContent = Get-Content -Path $IniPath -ErrorAction Stop
    $NewLinesToAdd = @()
    
    foreach ($Setting in $RequiredSettings) {
        if ($CurrentContent -notcontains $Setting) {
            $NewLinesToAdd += $Setting
            Write-Log "Will add setting: $Setting"
        }
    }
    
    if ($NewLinesToAdd.Count -gt 0) {
        Write-Log "Adding $($NewLinesToAdd.Count) new settings to $IniPath"
        Add-Content -Path $IniPath -Value $NewLinesToAdd -Encoding ASCII
        Write-Log "Successfully updated LabVIEW.ini"
    } else {
        Write-Log "LabVIEW.ini is already configured"
    }
    
    # Refresh package list
    Write-Log "Refreshing VIPM package list..."
    
    & $VipmExe package-list-refresh
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to refresh VIPM package list (exit code: $LASTEXITCODE)"
    }
    
    Write-Log "Waiting 30 seconds for VIPM to complete background refresh..."
    Start-Sleep -Seconds 30
    
    # Install LUnit for G-CLI
    Write-Log "Installing LUnit for G-CLI for LabVIEW {LVVersion} ({LVBitness}-bit)..."
    
    & $VipmExe install sas_workshops_lib_lunit_for_g_cli `
              --labview-version '{LVVersion}' `
              --labview-bitness '{LVBitness}'
    
    $installExitCode = $LASTEXITCODE
    
    if ($installExitCode -ne 0) {
        Write-Log "WARNING: VIPM install command returned exit code: $installExitCode (may be a timeout)" "WARN"
        Write-Log "Waiting for background mass compilation to complete..."
    }
    
    Write-Log "Waiting 240 seconds (4 minutes) for mass compilation to complete..."
    Start-Sleep -Seconds 240
    
    # Verify installation
    Write-Log "Verifying LUnit for G-CLI installation..."
    
    $listOutput = & $VipmExe list --installed --labview-version '{LVVersion}' --labview-bitness '{LVBitness}' 2>&1 | Out-String
    $listExitCode = $LASTEXITCODE
    
    Write-Log "Package list exit code: $listExitCode"
    
    if ($listOutput -match "sas_workshops_lib_lunit_for_g_cli") {
        Write-Log "LUnit for G-CLI installed successfully!"
        exit 0
    } else {
        Write-Log "ERROR: LUnit for G-CLI package not found in installed packages list" "ERROR"
        Write-Output "Installed packages:"
        Write-Output $listOutput
        throw "LUnit for G-CLI package not found in installed packages list"
    }
}
catch {
    Write-Output "ERROR: SetupLunit failed: $_"
    exit 1
}
'@
    
    $setupScriptBlock = $setupScriptBlock -replace '\{LVVersion\}', $LVVersion
    $setupScriptBlock = $setupScriptBlock -replace '\{LVBitness\}', $LVBitness
    $setupScriptBlock = $setupScriptBlock -replace '\{VipmInstallerUrl\}', $VipmInstallerUrl
    
    $setupArgs = $baseDockerArgs + @(
        'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $setupScriptBlock
    )

    Write-Verbose "Running Docker command: docker $($setupArgs -join ' ')"
    & docker @setupArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to setup VIPM and LUnit (exit code: $LASTEXITCODE)"
    }

    # Step 2: Run unit tests inside container
    Write-Information "Running unit tests in container..." -InformationAction Continue
    
    $testScriptCmd = "`$InformationPreference = 'Continue'; Set-Location C:\scripts; .\RunUnitTests.ps1 -LVVersion $LVVersion -LVBitness $LVBitness"
    
    if ($ProjectPath) {
        $testScriptCmd += " -ProjectPath 'C:\workspace\$ProjectPath'"
    }
    if ($OpenProjectBeforeRun) {
        $testScriptCmd += " -OpenProjectBeforeRun"
    }
    
    $testScriptCmd += " -Verbose"

    $testArgs = $baseDockerArgs + @(
        'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $testScriptCmd
    )

    Write-Verbose "Running Docker command: docker $($testArgs -join ' ')"
    & docker @testArgs
    
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        Write-Information "Unit tests completed successfully!" -InformationAction Continue
        exit 0
    } else {
        Write-Error "Unit tests failed with exit code: $exitCode"
        exit $exitCode
    }
}
catch {
    Write-Error "RunUnitTestsDocker failed: $_"
    exit 1
}