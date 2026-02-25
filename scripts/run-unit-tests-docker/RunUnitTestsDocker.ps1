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
    [switch]$OpenProjectBeforeRun
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
    
    $setupCmd = if ($VIPMConfigDir) {
        "Set-Location C:\scripts; .\SetupLUnit.ps1 -LVVersion $LVVersion -LVBitness $LVBitness -VIPMConfigDir 'C:\vipm-config' -Verbose -InformationAction Continue"
    } else {
        "Set-Location C:\scripts; .\SetupLUnit.ps1 -LVVersion $LVVersion -LVBitness $LVBitness -Verbose -InformationAction Continue"
    }
    
    $setupArgs = $baseDockerArgs + @(
        'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $setupCmd
    )

    Write-Verbose "Running Docker command: docker $($setupArgs -join ' ')"
    & docker @setupArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to setup VIPM and LUnit (exit code: $LASTEXITCODE)"
    }

    # Step 2: Run unit tests inside container
    Write-Information "Running unit tests in container..." -InformationAction Continue
    
    $testScriptCmd = "Set-Location C:\scripts; .\RunUnitTests.ps1 -LVVersion $LVVersion -LVBitness $LVBitness"
    
    if ($ProjectPath) {
        $testScriptCmd += " -ProjectPath 'C:\workspace\$ProjectPath'"
    }
    if ($OpenProjectBeforeRun) {
        $testScriptCmd += " -OpenProjectBeforeRun"
    }
    
    $testScriptCmd += " -Verbose -InformationAction Continue"

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