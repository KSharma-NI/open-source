<#
.SYNOPSIS
  Install VI Package Manager (VIPM) and LUnit for G-CLI package.

.DESCRIPTION
  Downloads and installs VIPM if not already installed, refreshes the package list,
  and installs the LUnit for G-CLI package for the specified LabVIEW version and bitness.

.PARAMETER LVVersion
  LabVIEW version (e.g., "2026", "2025").

.PARAMETER LVBitness
  LabVIEW bitness ("32" or "64").

.PARAMETER VIPMConfigDir
  Path to directory containing VIPM configuration files (jki.conf, Settings.ini).

.PARAMETER VipmInstallerUrl
  URL to download the VIPM installer.

.EXAMPLE
  .\SetupLUnit.ps1 -LVVersion "2026" -LVBitness "64"

.NOTES
  [REQ-041] Install VIPM and LUnit for G-CLI package in Docker container
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$LVVersion,

    [Parameter(Mandatory = $true)]
    [ValidateSet("32", "64")]
    [string]$LVBitness,
    
    [Parameter(Mandatory = $false)]
    [string]$VIPMConfigDir,

    [Parameter(Mandatory = $false)]
    [string]$VipmInstallerUrl = "https://packages.jki.net/vipm/preview/vipm-setup-latest-preview.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$InformationPreference = 'Continue'

try {
    Write-Verbose "Starting LUnit for G-CLI setup process..."
    Write-Information "Setting up LUnit for LabVIEW $LVVersion ($LVBitness-bit)"

    if ($VIPMConfigDir -and (Test-Path $VIPMConfigDir)) {
        Write-Information "Configuring VIPM from provided config directory..." 
        
        $jkiDir = "C:\ProgramData\JKI"
        $vipmDir = "C:\ProgramData\JKI\VIPM"
        
        # Create directories
        New-Item -ItemType Directory -Path $jkiDir -Force | Out-Null
        New-Item -ItemType Directory -Path $vipmDir -Force | Out-Null
        Write-Verbose "Created directories: $jkiDir and $vipmDir"
        
        # Copy jki.conf if exists
        $sourceJkiConf = Join-Path $VIPMConfigDir "jki.conf"
        if (Test-Path $sourceJkiConf) {
            $destJkiConf = Join-Path $jkiDir "jki.conf"
            Copy-Item -Path $sourceJkiConf -Destination $destJkiConf -Force
            Write-Information "Copied jki.conf to $destJkiConf" 
            Write-Verbose "jki.conf size: $((Get-Item $destJkiConf).Length) bytes"
        } else {
            Write-Warning "jki.conf not found at $sourceJkiConf"
        }
        
        # Copy Settings.ini if exists
        $sourceSettingsIni = Join-Path $VIPMConfigDir "Settings.ini"
        if (Test-Path $sourceSettingsIni) {
            $destSettingsIni = Join-Path $vipmDir "Settings.ini"
            Copy-Item -Path $sourceSettingsIni -Destination $destSettingsIni -Force
            Write-Information "Copied Settings.ini to $destSettingsIni" 
            Write-Verbose "Settings.ini size: $((Get-Item $destSettingsIni).Length) bytes"
        } else {
            Write-Warning "Settings.ini not found at $sourceSettingsIni"
        }
        
        Write-Information "VIPM configuration applied successfully" 
    } else {
        if ($VIPMConfigDir) {
            Write-Warning "VIPMConfigDir specified but not found: $VIPMConfigDir"
        }
        Write-Information "No VIPM configuration provided, using defaults" 
    }
    
    $VipmExe = "C:\Program Files\JKI\VI Package Manager\support\vipm.exe"
    
    # Check if VIPM is already installed
    if (Test-Path $VipmExe) {
        Write-Information "VIPM is already installed at $VipmExe" 
        Write-Verbose "Skipping VIPM installation"
    } else {
        Write-Information "VIPM not found. Installing VIPM..." 
        
        $VipmInstallerPath = Join-Path $env:TEMP "vipm-setup.exe"
        Write-Verbose "VIPM installer will be downloaded to: $VipmInstallerPath"
        
        # Download VIPM installer
        Write-Information "Downloading VIPM from $VipmInstallerUrl..." 
        Invoke-WebRequest -Uri $VipmInstallerUrl -OutFile $VipmInstallerPath
        
        if (-not (Test-Path $VipmInstallerPath)) {
            throw "Failed to download VIPM installer to $VipmInstallerPath"
        }
        
        $installerSize = (Get-Item $VipmInstallerPath).Length / 1MB
        Write-Verbose "Downloaded installer size: $($installerSize.ToString('F2')) MB"
        
        # Install VIPM silently
        Write-Information "Installing VIPM..." 
        Write-Verbose "Running installer with arguments: /quiet /norestart"
        
        $process = Start-Process -FilePath $VipmInstallerPath `
                                 -ArgumentList "/quiet", "/norestart" `
                                 -Wait `
                                 -PassThru
        
        $exitCode = $process.ExitCode
        Write-Verbose "VIPM installer exit code: $exitCode"
        
        if ($exitCode -eq 0) {
            Write-Information "VIPM installed successfully" 
            
            # Clean up installer
            if (Test-Path $VipmInstallerPath) {
                Remove-Item $VipmInstallerPath -Force
                Write-Verbose "Installer file removed"
            }
        } else {
            throw "VIPM installation failed with exit code: $exitCode"
        }
        
        # Verify VIPM was installed
        if (-not (Test-Path $VipmExe)) {
            throw "VIPM executable not found at $VipmExe after installation"
        }
        
        Write-Verbose "VIPM executable verified at $VipmExe"
    }
    
    # Configure LabVIEW settings before installing packages
    Write-Host "Configuring LabVIEW settings..." 
    
    $LabVIEWBasePath = if ($LVBitness -eq "64") {
        "C:\Program Files\National Instruments\LabVIEW $LVVersion"
    } else {
        "C:\Program Files (x86)\National Instruments\LabVIEW $LVVersion"
    }
    
    $IniPath = Join-Path $LabVIEWBasePath "LabVIEW.ini"
    $LabVIEWExePath = Join-Path $LabVIEWBasePath "LabVIEW.exe"
    
    Write-Verbose "LabVIEW base path: $LabVIEWBasePath"
    Write-Verbose "INI file path: $IniPath"
    Write-Verbose "LabVIEW executable: $LabVIEWExePath"
    
    # Settings required for LUnit testing
    $RequiredSettings = @(
        "server.tcp.enabled=TRUE",
        "server.tcp.access=+127.0.0.1;+localhost;+*",
        "server.viscripting.ShowScriptingOperationsInEditor=TRUE"
    )
    
    # Create INI file if it doesn't exist
    if (-not (Test-Path $IniPath)) {
        Write-Information "LabVIEW.ini not found at $IniPath" 
        
        if (-not (Test-Path $LabVIEWExePath)) {
            throw "LabVIEW executable not found at $LabVIEWExePath. Ensure LabVIEW $LVVersion ($LVBitness-bit) is installed."
        }
        
        Write-Information "Launching LabVIEW to generate ini file..."
        
        $lvProcess = Start-Process -FilePath $LabVIEWExePath -PassThru
        Write-Verbose "LabVIEW started with PID: $($lvProcess.Id)"
        Write-Information "Waiting 60 seconds for LabVIEW to generate ini file..." 
        Start-Sleep -Seconds 60
        
        if (-not $lvProcess.HasExited) {
            Write-Verbose "Terminating LabVIEW process..."
            Stop-Process -Id $lvProcess.Id -Force -ErrorAction SilentlyContinue
            Write-Information "LabVIEW closed" 
        } else {
            Write-Verbose "LabVIEW process already exited"
        }
        
        if (-not (Test-Path $IniPath)) {
            throw "INI file not found at $IniPath after launching LabVIEW"
        }
        
        Write-Verbose "INI file created successfully"
    } else {
        Write-Verbose "INI file already exists at $IniPath"
    }
    
    # Update INI file with required settings
    $CurrentContent = Get-Content -Path $IniPath -ErrorAction Stop
    Write-Verbose "Current INI file has $($CurrentContent.Count) lines"
    
    $NewLinesToAdd = @()
    
    foreach ($Setting in $RequiredSettings) {
        if ($CurrentContent -notcontains $Setting) {
            $NewLinesToAdd += $Setting
            Write-Information "Will add: $Setting"
        } else {
            Write-Verbose "Already exists: $Setting"
        }
    }
    
    if ($NewLinesToAdd.Count -gt 0) {
        Write-Information "Adding $($NewLinesToAdd.Count) new settings to $IniPath"
        Add-Content -Path $IniPath -Value $NewLinesToAdd -Encoding ASCII
        Write-Information "Successfully updated LabVIEW.ini"
    } else {
        Write-Information "LabVIEW.ini is already configured"
    }
        
    # Refresh package list
    Write-Information "Refreshing VIPM package list..." 
    Write-Verbose "Running: vipm.exe package-list-refresh"
    
    & $VipmExe package-list-refresh
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to refresh VIPM package list (exit code: $LASTEXITCODE)"
    }
    
    Write-Verbose "Package list refreshed successfully"

    Write-Host "Waiting 30 seconds for VIPM to complete background refresh..." 
    Start-Sleep -Seconds 30
    Write-Verbose "Wait complete, proceeding with installation"
        
    # Install LUnit for G-CLI
    Write-Host "Installing LUnit for G-CLI for LabVIEW $LVVersion ($LVBitness-bit)..." 
    Write-Verbose "Running: vipm.exe install sas_workshops_lib_lunit_for_g_cli --labview-version $LVVersion --labview-bitness $LVBitness"
    
    & $VipmExe install sas_workshops_lib_lunit_for_g_cli `
              --labview-version $LVVersion `
              --labview-bitness $LVBitness
    
    $installExitCode = $LASTEXITCODE
    Write-Verbose "LUnit installation exit code: $installExitCode"
    
    # VIPM may timeout during mass compilation but continue in background
    # Check for actual installation success rather than just exit code
    if ($installExitCode -ne 0) {
        Write-Warning "VIPM install command returned exit code: $installExitCode (may be a timeout)"
        Write-Information "Waiting for background mass compilation to complete..." 
    }
    
    # Wait for mass compile to complete (whether timeout occurred or not)
    Write-Information "Waiting 240 seconds for mass compilation to complete..." 
    Start-Sleep -Seconds 240
    Write-Verbose "Wait complete"
    
    # Verify installation by checking if LUnit package is installed
    Write-Information "Verifying LUnit for G-CLI installation..." 
    
    # Query installed packages
    $listOutput = & $VipmExe list --installed --labview-version $LVVersion --labview-bitness $LVBitness 2>&1
    $listExitCode = $LASTEXITCODE
    
    Write-Verbose "Package list exit code: $listExitCode"
    Write-Host "Package list output:`n$listOutput"
    
    # Check if LUnit package appears in the list
    $lunitInstalled = $listOutput | Select-String -Pattern "sas_workshops_lib_lunit_for_g_cli" -Quiet
    
    if ($lunitInstalled) {
        Write-Host "LUnit for G-CLI installed successfully!" 
        exit 0
    } else {
        # If not found, show what packages are installed for debugging
        Write-Warning "Installed packages:"
        Write-Warning $listOutput
        throw "LUnit for G-CLI package not found in installed packages list"
    }
}
catch {
    Write-Error "SetupLunit failed: $_"
    exit 1
}