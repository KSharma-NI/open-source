<#
.SYNOPSIS
  Run LabVIEW unit tests using g-cli and output a color-coded table of results.

.DESCRIPTION
  Executes LabVIEW unit tests with optional pre-run project opening,
  generates test reports, and provides color-coded output.

.PARAMETER LVVersion
  LabVIEW version (e.g., "2026", "2025").

.PARAMETER LVBitness
  LabVIEW bitness ("32" or "64").

.PARAMETER ProjectPath
  (Optional) Path to the LabVIEW project file (*.lvproj). If not provided,
  the script will search upward from its own location to find exactly one.

.PARAMETER OpenProjectBeforeRun
  (Optional) If present, runs OpenProj.vi via LabVIEWCLI before executing tests.

.EXAMPLE
  .\RunUnitTests.ps1 -LVVersion "2026" -LVBitness "64" -ProjectPath "C:\project\MyProject.lvproj"

.NOTES
  [REQ-041] Run LabVIEW unit tests in Docker container
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$LVVersion,

    [Parameter(Mandatory = $true)]
    [ValidateSet("32", "64")]
    [string]$LVBitness,

    [Parameter(Mandatory = $false)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $false)]
    [switch]$OpenProjectBeforeRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script-level variables to track exit states
$Script:OriginalExitCode = 0
$Script:TestsHadFailures = $false

# Path to UnitTestReport.xml in the same directory as this script
$ReportPath = Join-Path -Path $PSScriptRoot -ChildPath "UnitTestReport.xml"

# --------------------------------------------------------------------
# Locate exactly one .lvproj file by searching upward from $PSScriptRoot
# --------------------------------------------------------------------
function Get-SingleLvproj {
    param([string] $StartFolder)

    $currentDir = $StartFolder

    while ($true) {
        Write-Verbose "Searching '$currentDir' for *.lvproj files..."
        $lvprojFiles = Get-ChildItem -Path $currentDir -Filter '*.lvproj' -File -ErrorAction SilentlyContinue

        if ($lvprojFiles.Count -eq 1) {
            return $lvprojFiles[0].FullName
        }
        elseif ($lvprojFiles.Count -gt 1) {
            Write-Error "Error: Multiple .lvproj files found in '$currentDir'."
            $lvprojFiles | ForEach-Object { Write-Host " - $($_.FullName)" }
            return $null
        }
        
        $parentDir = Split-Path -Path $currentDir -Parent
        $driveRoot = [System.IO.Path]::GetPathRoot($currentDir)
        
        if ($parentDir -eq $currentDir -or $parentDir -eq $driveRoot) {
            Write-Error "Error: Reached root without finding exactly one .lvproj."
            return $null
        }

        $currentDir = $parentDir
    }
}

# --------------------------  SETUP  --------------------------
function Setup {
    Write-Information "=== Setup ===" -InformationAction Continue
    $ServiceName = "nisvcloc"
    $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($null -eq $Service) {
        Write-Warning "NI Service Locator service ('$ServiceName') not found."
    }
    else {
        Write-Verbose "Checking NI Service Locator status..."

        if ($Service.Status -ne 'Running') {
            Write-Information "Starting NI Service Locator..." -InformationAction Continue
            try {
                Start-Service -Name $ServiceName -ErrorAction Stop

                $retryCount = 0
                while ((Get-Service $ServiceName).Status -ne 'Running' -and $retryCount -lt 10) {
                    Start-Sleep -Seconds 1
                    $retryCount++
                }
                Write-Information "NI Service Locator started successfully." -InformationAction Continue
            }
            catch {
                Write-Warning "Failed to start NI Service Locator: $($_.Exception.Message)"
            }
        }
        else {
            Write-Verbose "NI Service Locator is already running."
        }
    }

    if (Test-Path $ReportPath) {
        Remove-Item $ReportPath -Force
        Write-Verbose "Deleted existing UnitTestReport.xml."
    }
}

# ------------------------  MAIN SEQUENCE  ----------------------
function MainSequence {
    Write-Information "`n=== Running Tests ===" -InformationAction Continue
    
    if ($OpenProjectBeforeRun) {
        $PreRunVI = Join-Path -Path $PSScriptRoot -ChildPath "OpenProj.vi"
        Write-Information "Opening project before run..." -InformationAction Continue
        
        if (Test-Path $PreRunVI) {
            $labviewCLI = "C:\Program Files (x86)\National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe"
            if (Test-Path $labviewCLI) {
                & $labviewCLI -OperationName RunVI -VIPath $PreRunVI $AbsoluteProjectPath

                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "LabVIEW CLI failed (Exit code: $LASTEXITCODE)"
                }
            }
        }
    }

    $gCliPath = "C:\Program Files\G-CLI\bin\g-cli.exe"

    Write-Information "Running unit tests for LabVIEW $LVVersion ($LVBitness-bit)" -InformationAction Continue
    Write-Information "Project Path: $AbsoluteProjectPath" -InformationAction Continue
    Write-Verbose "Report will be saved at: $ReportPath"

    & $gCliPath --lv-ver $LVVersion --arch $LVBitness lunit -- -r "$ReportPath" "$AbsoluteProjectPath"

    $script:OriginalExitCode = $LASTEXITCODE

    if ($script:OriginalExitCode -ne 0) {
        Write-Warning "g-cli test execution failed (exit code $script:OriginalExitCode)."
    }

    if ($script:OriginalExitCode -ne 0 -and -not (Test-Path $ReportPath)) {
        $script:TestsHadFailures = $true
        Write-Warning "No test report found, and g-cli returned an error."
        return
    }

    # Parse test results
    if (Test-Path $ReportPath) {
        try {
            [xml]$xmlDoc = Get-Content $ReportPath -ErrorAction Stop
            $testCases = $xmlDoc.SelectNodes("//testcase")
            
            if (!$testCases -or $testCases.Count -eq 0) {
                Write-Error "No <testcase> entries found in UnitTestReport.xml."
                $script:TestsHadFailures = $true
                return
            }

            # Display results in table format
            $results = @()
            foreach ($case in $testCases) {
                $status = $case.GetAttribute("status")
                if ([string]::IsNullOrWhiteSpace($status)) { $status = "Skipped" }

                $results += [PSCustomObject]@{
                    TestCaseName = $case.GetAttribute("name")
                    ClassName    = $case.GetAttribute("classname")
                    Status       = $status
                    Time         = $case.GetAttribute("time")
                    Assertions   = $case.GetAttribute("assertions")
                }

                if ($status -notmatch "^Passed$" -and $status -notmatch "^Skipped$") {
                    $script:TestsHadFailures = $true
                }
            }

            $results | Format-Table -AutoSize
        }
        catch {
            Write-Error "Failed to parse UnitTestReport.xml: $($_.Exception.Message)"
            $script:TestsHadFailures = $true
        }
    }
}

# --------------------------  CLEANUP  --------------------------
function Cleanup {
    Write-Information "`n=== Cleanup ===" -InformationAction Continue
    try {
        $artifactDir = Join-Path -Path (Join-Path $PSScriptRoot '..' '..') -ChildPath 'artifacts/unit-tests'
        New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
        $dest = Join-Path -Path $artifactDir -ChildPath 'UnitTestReport.xml'
        Copy-Item -Path $ReportPath -Destination $dest -Force
        Write-Information "Copied UnitTestReport.xml to artifacts." -InformationAction Continue
    }
    catch {
        Write-Warning "Failed to copy UnitTestReport.xml: $($_.Exception.Message)"
    }
}

# -------------------  EXECUTION FLOW  -------------------
try {
    if ($ProjectPath) {
        $AbsoluteProjectPath = Resolve-Path $ProjectPath
        Write-Information "Using provided project: $AbsoluteProjectPath" -InformationAction Continue
    } else {
        $AbsoluteProjectPath = Get-SingleLvproj -StartFolder $PSScriptRoot
        if (-not $AbsoluteProjectPath) { exit 3 }
        Write-Information "Found project: $AbsoluteProjectPath" -InformationAction Continue
    }

    Setup
    MainSequence
    Cleanup

    if ($Script:OriginalExitCode -ne 0) {
        exit $Script:OriginalExitCode
    }
    elseif ($Script:TestsHadFailures) {
        exit 2
    }
    else {
        exit 0
    }
}
catch {
    Write-Error "RunUnitTests failed: $_"
    exit 1
}