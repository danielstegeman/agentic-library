<#
.SYNOPSIS
    Detects the project stack in a workspace and recommends devcontainer configuration.

.DESCRIPTION
    Scans the workspace root for language/framework marker files (package.json,
    requirements.txt, go.mod, etc.), maps the detected stack to a recommended
    Dev Container base image, extracts port hints from existing configs, and
    detects the appropriate post-create command.

    Outputs a structured text block that the agent can parse to pre-fill the
    devcontainer interview with sensible defaults.

.PARAMETER WorkspaceRoot
    Path to the workspace root to scan. Defaults to the current directory.

.EXAMPLE
    .\Detect-ProjectStack.ps1 -WorkspaceRoot C:\my-project

.OUTPUTS
    Structured text block to stdout:
        Language: typescript
        Image: mcr.microsoft.com/devcontainers/typescript-node:1
        PostCreate: npm install
        Ports: 3000, 5173
        PackageManager: npm
        Existing: none
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$WorkspaceRoot = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Resolve-Path $WorkspaceRoot

# ---------------------------------------------------------------------------
# 1. Check for existing devcontainer configuration
# ---------------------------------------------------------------------------
$existing = 'none'
$packageManager = 'unknown'
if (Test-Path (Join-Path $root '.devcontainer/devcontainer.json')) {
    $existing = '.devcontainer/devcontainer.json'
}
elseif (Test-Path (Join-Path $root '.devcontainer.json')) {
    $existing = '.devcontainer.json'
}

# ---------------------------------------------------------------------------
# 2. Detect language/framework from marker files
# ---------------------------------------------------------------------------
$detections = [ordered]@{}

# Node.js / JavaScript / TypeScript
if (Test-Path (Join-Path $root 'package.json')) {
    $pkg = Get-Content (Join-Path $root 'package.json') -Raw | ConvertFrom-Json
    $hasTsConfig = Test-Path (Join-Path $root 'tsconfig.json')
    if ($hasTsConfig) {
        $detections['typescript'] = @{
            Image          = 'mcr.microsoft.com/devcontainers/typescript-node:1'
            PostCreate     = $null  # resolved below from lock file
            PackageManager = 'npm'
        }
    }
    else {
        $detections['javascript'] = @{
            Image          = 'mcr.microsoft.com/devcontainers/javascript-node:1'
            PostCreate     = $null
            PackageManager = 'npm'
        }
    }
    # Detect package manager
    $nodeKey = if ($hasTsConfig) { 'typescript' } else { 'javascript' }
    if (Test-Path (Join-Path $root 'pnpm-lock.yaml')) {
        $detections[$nodeKey].PostCreate = 'pnpm install'
        $detections[$nodeKey].PackageManager = 'pnpm'
    }
    elseif (Test-Path (Join-Path $root 'yarn.lock')) {
        $detections[$nodeKey].PostCreate = 'yarn install'
        $detections[$nodeKey].PackageManager = 'yarn'
    }
    elseif (Test-Path (Join-Path $root 'bun.lockb')) {
        $detections[$nodeKey].PostCreate = 'bun install'
        $detections[$nodeKey].PackageManager = 'bun'
    }
    else {
        $detections[$nodeKey].PostCreate = 'npm install'
    }
}

# Python
if ((Test-Path (Join-Path $root 'requirements.txt')) -or
    (Test-Path (Join-Path $root 'pyproject.toml')) -or
    (Test-Path (Join-Path $root 'setup.py')) -or
    (Test-Path (Join-Path $root 'Pipfile'))) {

    $pyPm = 'pip'
    $pyPostCreate = 'pip install -e ".[dev]"'
    if (Test-Path (Join-Path $root 'uv.lock')) {
        $pyPostCreate = 'uv sync'
        $pyPm = 'uv'
    }
    elseif (Test-Path (Join-Path $root 'poetry.lock')) {
        $pyPostCreate = 'poetry install'
        $pyPm = 'poetry'
    }
    elseif (Test-Path (Join-Path $root 'Pipfile.lock')) {
        $pyPostCreate = 'pipenv install --dev'
        $pyPm = 'pipenv'
    }
    elseif (Test-Path (Join-Path $root 'requirements.txt')) {
        $pyPostCreate = 'pip install -r requirements.txt'
    }

    $detections['python'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/python:1'
        PostCreate     = $pyPostCreate
        PackageManager = $pyPm
    }
}

# Go
if (Test-Path (Join-Path $root 'go.mod')) {
    $detections['go'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/go:1'
        PostCreate     = 'go mod download'
        PackageManager = 'go'
    }
}

# Rust
if (Test-Path (Join-Path $root 'Cargo.toml')) {
    $detections['rust'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/rust:1'
        PostCreate     = 'cargo build'
        PackageManager = 'cargo'
    }
}

# .NET / C#
$csprojFiles = Get-ChildItem -Path $root -Filter '*.csproj' -Recurse -Depth 2 -ErrorAction SilentlyContinue
$slnFiles = Get-ChildItem -Path $root -Filter '*.sln' -Depth 0 -ErrorAction SilentlyContinue
if ($csprojFiles -or $slnFiles) {
    $detections['dotnet'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/dotnet:1'
        PostCreate     = 'dotnet restore'
        PackageManager = 'dotnet'
    }
}

# Java (Maven)
if (Test-Path (Join-Path $root 'pom.xml')) {
    $detections['java'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/java:1'
        PostCreate     = './mvnw install -DskipTests || mvn install -DskipTests'
        PackageManager = 'maven'
    }
}

# Java (Gradle)
if (Test-Path (Join-Path $root 'build.gradle')) {
    $detections['java'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/java:1'
        PostCreate     = './gradlew build -x test || gradle build -x test'
        PackageManager = 'gradle'
    }
}

# PHP
if (Test-Path (Join-Path $root 'composer.json')) {
    $detections['php'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/php:1'
        PostCreate     = 'composer install'
        PackageManager = 'composer'
    }
}

# Ruby
if (Test-Path (Join-Path $root 'Gemfile')) {
    $detections['ruby'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/ruby:1'
        PostCreate     = 'bundle install'
        PackageManager = 'bundler'
    }
}

# C/C++
if ((Test-Path (Join-Path $root 'CMakeLists.txt')) -or
    (Test-Path (Join-Path $root 'Makefile'))) {
    $detections['cpp'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/cpp:1'
        PostCreate     = $null
        PackageManager = 'cmake'
    }
}

# Elixir
if (Test-Path (Join-Path $root 'mix.exs')) {
    $detections['elixir'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/base:ubuntu'
        PostCreate     = 'mix deps.get'
        PackageManager = 'mix'
    }
}

# Dart / Flutter
if (Test-Path (Join-Path $root 'pubspec.yaml')) {
    $detections['dart'] = @{
        Image          = 'mcr.microsoft.com/devcontainers/base:ubuntu'
        PostCreate     = 'dart pub get'
        PackageManager = 'dart'
    }
}

# ---------------------------------------------------------------------------
# 3. Pick primary detection (first match wins — ordered by specificity)
# ---------------------------------------------------------------------------
if (@($detections.Keys).Count -eq 0) {
    $language = 'unknown'
    $image = 'mcr.microsoft.com/devcontainers/base:ubuntu'
    $postCreate = ''
    $packageManager = 'unknown'
}
else {
    $language = ($detections.Keys | Select-Object -First 1)
    $image = $detections[$language].Image
    $postCreate = $detections[$language].PostCreate
    $packageManager = $detections[$language].PackageManager
    if (-not $postCreate) { $postCreate = '' }
}

# ---------------------------------------------------------------------------
# 4. Detect ports from existing config files
# ---------------------------------------------------------------------------
$ports = [System.Collections.Generic.List[int]]::new()

# .env file: PORT=3000
if (Test-Path (Join-Path $root '.env')) {
    $envContent = Get-Content (Join-Path $root '.env') -ErrorAction SilentlyContinue
    foreach ($line in $envContent) {
        if ($line -match '^\s*(?:PORT|APP_PORT|SERVER_PORT|API_PORT)\s*=\s*(\d+)') {
            $p = [int]$Matches[1]
            if ($p -gt 0 -and $p -le 65535 -and -not $ports.Contains($p)) {
                $ports.Add($p)
            }
        }
    }
}

# package.json scripts with --port or PORT
if (Test-Path (Join-Path $root 'package.json')) {
    $pkgContent = Get-Content (Join-Path $root 'package.json') -Raw -ErrorAction SilentlyContinue
    $portMatches = [regex]::Matches($pkgContent, '(?:--port|PORT[=:])\s*(\d{2,5})')
    foreach ($m in $portMatches) {
        $p = [int]$m.Groups[1].Value
        if ($p -gt 0 -and $p -le 65535 -and -not $ports.Contains($p)) {
            $ports.Add($p)
        }
    }
}

# Common framework defaults if no port detected
if ($ports.Count -eq 0) {
    switch -Wildcard ($language) {
        'typescript' { $ports.Add(3000) }
        'javascript' { $ports.Add(3000) }
        'python'     { $ports.Add(8000) }
        'go'         { $ports.Add(8080) }
        'rust'       { $ports.Add(8080) }
        'dotnet'     { $ports.Add(5000) }
        'java'       { $ports.Add(8080) }
        'php'        { $ports.Add(8080) }
        'ruby'       { $ports.Add(3000) }
    }
}

$portsStr = if ($ports.Count -gt 0) { ($ports | Sort-Object -Unique) -join ', ' } else { 'none' }

# ---------------------------------------------------------------------------
# 5. Detect additional languages (multi-language projects)
# ---------------------------------------------------------------------------
$additionalLanguages = @()
if (@($detections.Keys).Count -gt 1) {
    $additionalLanguages = @($detections.Keys | Select-Object -Skip 1)
}
$additionalStr = if ($additionalLanguages.Count -gt 0) { $additionalLanguages -join ', ' } else { 'none' }

# ---------------------------------------------------------------------------
# 6. Output structured result
# ---------------------------------------------------------------------------
Write-Output "Language: $language"
Write-Output "AdditionalLanguages: $additionalStr"
Write-Output "Image: $image"
Write-Output "PostCreate: $postCreate"
Write-Output "Ports: $portsStr"
Write-Output "PackageManager: $packageManager"
Write-Output "Existing: $existing"
