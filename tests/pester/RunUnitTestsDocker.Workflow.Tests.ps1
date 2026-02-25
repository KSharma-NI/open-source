#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'RunUnitTestsDocker.Workflow' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module "$repoRoot/actions/OpenSourceActions.psm1" -Force
    }

    $meta = @{
        requirement = 'REQ-041'
        Owner       = 'DevOps'
        Evidence    = 'tests/pester/RunUnitTestsDocker.Workflow.Tests.ps1'
    }

    It 'executes run-unit-tests-docker successfully [REQ-041]' -Tag 'REQ-041' {
        # Mock Docker commands
        Mock -CommandName 'docker' -MockWith { return 0 } -ModuleName OpenSourceActions
        
        $result = Invoke-RunUnitTestsDocker `
            -DockerImage 'nationalinstruments/labview:2026q1-windows' `
            -LVVersion '2026' `
            -LVBitness '64' `
            -DryRun
        
        $result | Should -Be 0
    }

    It 'validates required parameters [REQ-041]' -Tag 'REQ-041' {
        { Invoke-RunUnitTestsDocker } | Should -Throw
    }

    It 'validates LVBitness parameter [REQ-041]' -Tag 'REQ-041' {
        { Invoke-RunUnitTestsDocker -DockerImage 'test' -LVVersion '2026' -LVBitness 'invalid' } | Should -Throw
    }

    It 'accepts optional ProjectPath parameter [REQ-041]' -Tag 'REQ-041' {
        Mock -CommandName 'docker' -MockWith { return 0 } -ModuleName OpenSourceActions
        
        $result = Invoke-RunUnitTestsDocker `
            -DockerImage 'nationalinstruments/labview:2026q1-windows' `
            -LVVersion '2026' `
            -LVBitness '64' `
            -ProjectPath 'MyProject.lvproj' `
            -DryRun
        
        $result | Should -Be 0
    }

    It 'accepts OpenProjectBeforeRun switch [REQ-041]' -Tag 'REQ-041' {
        Mock -CommandName 'docker' -MockWith { return 0 } -ModuleName OpenSourceActions
        
        $result = Invoke-RunUnitTestsDocker `
            -DockerImage 'nationalinstruments/labview:2026q1-windows' `
            -LVVersion '2026' `
            -LVBitness '64' `
            -OpenProjectBeforeRun `
            -DryRun
        
        $result | Should -Be 0
    }
}