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

try {
    Write-Verbose "Starting LUnit for G-CLI setup process..."
    Write-Information "Setting up LUnit for LabVIEW $LVVersion ($LVBitness-bit)" -InformationAction Continue

    if ($VIPMConfigDir -and (Test-Path $VIPMConfigDir)) {
        Write-Information "Configuring VIPM from provided config directory..." -InformationAction Continue
        
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
            Write-Information "Copied jki.conf to $destJkiConf" -InformationAction Continue
            Write-Verbose "jki.conf size: $((Get-Item $destJkiConf).Length) bytes"
        } else {
            Write-Warning "jki.conf not found at $sourceJkiConf"
        }
        
        # Copy Settings.ini if exists
        $sourceSettingsIni = Join-Path $VIPMConfigDir "Settings.ini"
        if (Test-Path $sourceSettingsIni) {
            $destSettingsIni = Join-Path $vipmDir "Settings.ini"
            Copy-Item -Path $sourceSettingsIni -Destination $destSettingsIni -Force
            Write-Information "Copied Settings.ini to $destSettingsIni" -InformationAction Continue
            Write-Verbose "Settings.ini size: $((Get-Item $destSettingsIni).Length) bytes"
        } else {
            Write-Warning "Settings.ini not found at $sourceSettingsIni"
        }
        
        Write-Information "VIPM configuration applied successfully" -InformationAction Continue
    } else {
        if ($VIPMConfigDir) {
            Write-Warning "VIPMConfigDir specified but not found: $VIPMConfigDir"
        }
        Write-Information "No VIPM configuration provided, using defaults" -InformationAction Continue
    }
    
    $VipmExe = "C:\Program Files\JKI\VI Package Manager\support\vipm.exe"
    
    # Check if VIPM is already installed
    if (Test-Path $VipmExe) {
        Write-Information "VIPM is already installed at $VipmExe" -InformationAction Continue
        Write-Verbose "Skipping VIPM installation"
    } else {
        Write-Information "VIPM not found. Installing VIPM..." -InformationAction Continue
        
        $VipmInstallerPath = Join-Path $env:TEMP "vipm-setup.exe"
        Write-Verbose "VIPM installer will be downloaded to: $VipmInstallerPath"
        
        # Download VIPM installer
        Write-Information "Downloading VIPM from $VipmInstallerUrl..." -InformationAction Continue
        Invoke-WebRequest -Uri $VipmInstallerUrl -OutFile $VipmInstallerPath
        
        if (-not (Test-Path $VipmInstallerPath)) {
            throw "Failed to download VIPM installer to $VipmInstallerPath"
        }
        
        $installerSize = (Get-Item $VipmInstallerPath).Length / 1MB
        Write-Verbose "Downloaded installer size: $($installerSize.ToString('F2')) MB"
        
        # Install VIPM silently
        Write-Information "Installing VIPM..." -InformationAction Continue
        Write-Verbose "Running installer with arguments: /quiet /norestart"
        
        $process = Start-Process -FilePath $VipmInstallerPath `
                                 -ArgumentList "/quiet", "/norestart" `
                                 -Wait `
                                 -PassThru
        
        $exitCode = $process.ExitCode
        Write-Verbose "VIPM installer exit code: $exitCode"
        
        if ($exitCode -eq 0) {
            Write-Information "VIPM installed successfully" -InformationAction Continue
            
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
    
    # Refresh package list
    Write-Information "Refreshing VIPM package list..." -InformationAction Continue
    Write-Verbose "Running: vipm.exe package-list-refresh"
    
    & $VipmExe package-list-refresh
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to refresh VIPM package list (exit code: $LASTEXITCODE)"
    }
    
    Write-Verbose "Package list refreshed successfully"

    Write-Information "Waiting 30 seconds for VIPM to complete background refresh..." -InformationAction Continue
    Start-Sleep -Seconds 30
    Write-Verbose "Wait complete, proceeding with installation"
        
    # Install LUnit for G-CLI
    Write-Information "Installing LUnit for G-CLI for LabVIEW $LVVersion ($LVBitness-bit)..." -InformationAction Continue
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
        Write-Information "Waiting for background mass compilation to complete..." -InformationAction Continue
    }
    
    # Wait for mass compile to complete (whether timeout occurred or not)
    Write-Information "Waiting 240 seconds for mass compilation to complete..." -InformationAction Continue
    Start-Sleep -Seconds 240
    Write-Verbose "Wait complete"
    
    # Verify installation by checking if LUnit package is installed
    Write-Information "Verifying LUnit for G-CLI installation..." -InformationAction Continue
    
    # Query installed packages
    $listOutput = & $VipmExe list --installed --labview-version $LVVersion --labview-bitness $LVBitness 2>&1
    $listExitCode = $LASTEXITCODE
    
    Write-Verbose "Package list exit code: $listExitCode"
    Write-Verbose "Package list output:`n$listOutput"
    
    # Check if LUnit package appears in the list
    $lunitInstalled = $listOutput | Select-String -Pattern "sas_workshops_lib_lunit_for_g_cli" -Quiet
    
    if ($lunitInstalled) {
        Write-Information "LUnit for G-CLI installed successfully!" -InformationAction Continue
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