#Requires -Version 5.1
<#
.SYNOPSIS
    Initialises .agent-artifacts/ working-memory folder on the current branch.

.DESCRIPTION
    Creates the .agent-artifacts/ folder structure and writes a README.md derived
    from the template next to this script. Safe to run multiple times — existing
    files and directories are never overwritten.

.PARAMETER RepoRoot
    Path to the git repository root. Defaults to the output of
    'git rev-parse --show-toplevel' executed in the current working directory.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

# Resolve repo root
if (-not $RepoRoot) {
    $RepoRoot = (git rev-parse --show-toplevel 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not determine git repository root. Make sure you are inside a git repository."
    }
    $RepoRoot = $RepoRoot.Trim()
}

$ArtifactsRoot = Join-Path $RepoRoot '.agent-artifacts'
$SubDirs = @('plans', 'reports', 'notes')

# Create subdirectories and .gitkeep placeholders (idempotent)
foreach ($SubDir in $SubDirs) {
    $DirPath = Join-Path $ArtifactsRoot $SubDir
    if (-not (Test-Path $DirPath)) {
        New-Item -ItemType Directory -Path $DirPath -Force | Out-Null
        Write-Host "Created: .agent-artifacts/$SubDir/"
    }
    else {
        Write-Verbose "Already exists: .agent-artifacts/$SubDir/"
    }

    $GitKeepPath = Join-Path $DirPath '.gitkeep'
    $HasOtherFiles = (Get-ChildItem -Path $DirPath -File | Where-Object { $_.Name -ne '.gitkeep' }).Count -gt 0
    if (-not $HasOtherFiles -and -not (Test-Path $GitKeepPath)) {
        New-Item -ItemType File -Path $GitKeepPath -Force | Out-Null
        Write-Host "Created: .agent-artifacts/$SubDir/.gitkeep"
    }
}

# Write README from template (only if not already present)
$ReadMePath = Join-Path $ArtifactsRoot 'README.md'
if (-not (Test-Path $ReadMePath)) {
    $TemplatePath = Join-Path $PSScriptRoot 'README-template.md'
    if (-not (Test-Path $TemplatePath)) {
        Write-Error "README template not found at: $TemplatePath"
    }
    Copy-Item -Path $TemplatePath -Destination $ReadMePath
    Write-Host "Created: .agent-artifacts/README.md"
}
else {
    Write-Verbose "Already exists: .agent-artifacts/README.md"
}

# Stage the folder
Push-Location $RepoRoot
try {
    git add .agent-artifacts/
}
finally {
    Pop-Location
}

Write-Host @"

.agent-artifacts/ is ready and staged.
Remember: delete this folder before completing the pull request.
"@
