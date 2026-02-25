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

    $normalizedWorkspace = $WorkspacePath.Replace('\', '/')
    if ($normalizedWorkspace -match '^([A-Z]):(.+)$') {
        # Convert Windows path to Docker volume format: C:\path -> /c/path
        $normalizedWorkspace = "/$($matches[1].ToLower())$($matches[2])"
    }
    
    Write-Verbose "Normalized workspace for Docker: $normalizedWorkspace"

    # Base docker run arguments
    $baseDockerArgs = @(
        'run',
        '--rm',
        '-v', "${WorkspacePath}:C:\workspace",
        '-w', 'C:\workspace',
        $DockerImage
    )

    # Step 1: Setup VIPM and LUnit inside container
    Write-Information "Setting up VIPM and LUnit in container..." -InformationAction Continue
    
    $setupArgs = $baseDockerArgs + @(
        'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
        "& C:\workspace\scripts\run-unit-tests-docker\SetupLunit.ps1 -LVVersion $LVVersion -LVBitness $LVBitness -Verbose -InformationAction Continue"
    )

    Write-Verbose "Running Docker command: docker $($setupArgs -join ' ')"
    & docker @setupArgs
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to setup VIPM and LUnit (exit code: $LASTEXITCODE)"
    }

    # Run unit tests inside container
    Write-Information "Running unit tests in container..." -InformationAction Continue
    
    $testScriptCmd = "& C:\workspace\scripts\run-unit-tests-docker\RunUnitTests.ps1 -LVVersion $LVVersion -LVBitness $LVBitness"
    
    if ($ProjectPath) {
        $testScriptCmd += " -ProjectPath 'C:\workspace\$ProjectPath'"
    }
    if ($OpenProjectBeforeRun) {
        $testScriptCmd += " -OpenProjectBeforeRun"
    }
    
    $testScriptCmd += " -Verbose -InformationAction Continue"

    $testArgs = $baseDockerArgs + @(
        'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
        $testScriptCmd
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