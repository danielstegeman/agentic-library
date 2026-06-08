<#
.SYNOPSIS
    Generate a YAML run-config from an Azure DevOps pipeline definition.

.DESCRIPTION
    Locates the named pipeline YAML in the current repo, parses its `parameters:`
    block, and writes a pre-filled run-config.yml the user can edit before
    invoking the pipeline. Inline comments show each parameter's type, default,
    and allowed values (for choice parameters).

.PARAMETER PipelineName
    Pipeline YAML filename (with or without .yml extension), e.g. '_ATF' or '_Build'.

.PARAMETER OutputPath
    Destination file. Defaults to <repoRoot>/.agent-artifacts/pipeline-runs/_pending/run-config.yml.

.PARAMETER Force
    Overwrite an existing output file.

.EXAMPLE
    .\New-PipelineRunConfig.ps1 -PipelineName _ATF
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PipelineName,

    [string]$OutputPath,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PipelineRunner.psm1') -Force

Assert-Prerequisite

$repoRoot = Get-RepoRoot
$yamlPath = Get-PipelineYamlPath -PipelineName $PipelineName -RepoRoot $repoRoot
$parameters = @(Get-PipelineParameter -Path $yamlPath)
$branch = Get-CurrentGitBranch -RepoRoot $repoRoot

# Try to discover the ADO pipeline definition that points at this YAML file.
# The pipeline display name in ADO may differ from the YAML filename, so we
# match on yamlFilename to find the correct definition ID.
$discoveredPipelineId = $null
$discoveredPipelineName = $null
try {
    $connection = Get-AzdoConnection -RepoRoot $repoRoot
    $relYaml = $yamlPath.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
    $definitions = Invoke-Az -ArgumentList @(
        'pipelines', 'list',
        '--organization', $connection.OrganizationUrl,
        '--project', $connection.Project,
        '--query-order', 'ModifiedDesc'
    )
    foreach ($d in @($definitions)) {
        $defYaml = $null
        if ($d.PSObject.Properties.Name -contains 'yamlFilename') {
            $defYaml = "$($d.yamlFilename)" -replace '\\', '/'
        }
        if ($defYaml -and ($defYaml -ieq $relYaml -or $defYaml -ieq "/$relYaml")) {
            $discoveredPipelineId = $d.id
            $discoveredPipelineName = $d.name
            break
        }
    }
}
catch {
    Write-Warning "Could not auto-discover pipeline definition: $($_.Exception.Message)"
}

if (-not $OutputPath) {
    $pendingDir = Get-PendingConfigDir -RepoRoot $repoRoot -CreateIfMissing
    $OutputPath = Join-Path $pendingDir 'run-config.yml'
}

if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    throw "Output file already exists: $OutputPath. Use -Force to overwrite."
}

$lines = [System.Collections.Generic.List[string]]::new()
$bareName = $PipelineName -replace '\.ya?ml$', ''

$lines.Add("# Run config for pipeline: $bareName")
$lines.Add("# Source: $($yamlPath.Substring($repoRoot.Length).TrimStart('\','/'))")
if ($discoveredPipelineName -and $discoveredPipelineName -ne $bareName) {
    $lines.Add("# ADO pipeline definition: $discoveredPipelineName (id $discoveredPipelineId)")
}
$lines.Add("# Edit the values below, then run:")
$lines.Add("#   .\Invoke-PipelineRun.ps1 -ConfigPath '$OutputPath'")
$lines.Add("")
$lines.Add("pipeline: $bareName")
if ($discoveredPipelineId) {
    $lines.Add("pipelineId: $discoveredPipelineId  # ADO definition id (auto-discovered from yamlFilename)")
}
$lines.Add("branch: $branch")
$lines.Add("")
$lines.Add("parameters:")

function ConvertTo-IndentedYaml {
    <#
    .SYNOPSIS
        Render a value as YAML lines at the given indent level.

    .DESCRIPTION
        Handles primitives, arrays, and nested dictionaries/hashtables so that
        object-typed pipeline parameter defaults (e.g. pipelineDebugOptions)
        round-trip correctly through the run-config.
    #>
    param(
        [object]$Value,
        [int]$Indent
    )

    $pad = ' ' * $Indent
    $out = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $Value) {
        $out.Add('~')
        return $out
    }
    if ($Value -is [bool]) {
        $out.Add(([string]$Value).ToLowerInvariant())
        return $out
    }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Count -eq 0) {
            $out.Add('{}')
            return $out
        }
        $out.Add('')
        foreach ($key in $Value.Keys) {
            $childLines = @(ConvertTo-IndentedYaml -Value $Value[$key] -Indent ($Indent + 2))
            if ($childLines[0] -eq '' -or $childLines[0] -eq '{}' -or $childLines[0].StartsWith('- ')) {
                $out.Add("${pad}${key}:" + $(if ($childLines[0] -eq '') { '' } else { ' ' + $childLines[0] }))
                if ($childLines[0] -eq '') {
                    for ($i = 1; $i -lt $childLines.Count; $i++) { $out.Add($childLines[$i]) }
                }
            }
            else {
                $out.Add("${pad}${key}: $($childLines[0])")
                for ($i = 1; $i -lt $childLines.Count; $i++) { $out.Add($childLines[$i]) }
            }
        }
        return $out
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @($Value)
        if ($items.Count -eq 0) {
            $out.Add('[]')
            return $out
        }
        $allScalar = $true
        foreach ($i in $items) {
            if ($i -is [System.Collections.IDictionary] -or
                ($i -is [System.Collections.IEnumerable] -and -not ($i -is [string]))) {
                $allScalar = $false; break
            }
        }
        if ($allScalar) {
            $rendered = $items | ForEach-Object {
                if ($_ -is [bool]) { ([string]$_).ToLowerInvariant() }
                else { "'" + ("$_" -replace "'", "''") + "'" }
            }
            $out.Add('[' + ($rendered -join ', ') + ']')
            return $out
        }
        $out.Add('')
        foreach ($i in $items) {
            $childLines = @(ConvertTo-IndentedYaml -Value $i -Indent ($Indent + 2))
            $out.Add("${pad}- $($childLines[0])")
            for ($k = 1; $k -lt $childLines.Count; $k++) { $out.Add($childLines[$k]) }
        }
        return $out
    }

    $stringValue = "$Value"
    if ($stringValue -match '[:#&*?{}\[\],|>!%@`]' -or
        $stringValue -match '^\s' -or $stringValue -match '\s$' -or
        $stringValue -eq '' -or $stringValue -match '^(true|false|null|yes|no|on|off)$') {
        $out.Add("'" + ($stringValue -replace "'", "''") + "'")
    }
    else {
        $out.Add($stringValue)
    }
    return $out
}

if ($parameters.Count -eq 0) {
    $lines.Add("  # (pipeline declares no parameters)")
}
else {
    foreach ($p in $parameters) {
        $comment = "# type: $($p.Type)"
        $vals = @($p.Values)
        if ($vals.Count -gt 0) {
            $comment += " | allowed: [$($vals -join ', ')]"
        }
        $lines.Add("  $comment")

        $rendered = @(ConvertTo-IndentedYaml -Value $p.Default -Indent 4)
        if ($rendered[0] -eq '') {
            $lines.Add("  $($p.Name):")
            for ($i = 1; $i -lt $rendered.Count; $i++) { $lines.Add($rendered[$i]) }
        }
        else {
            $lines.Add("  $($p.Name): $($rendered[0])")
            for ($i = 1; $i -lt $rendered.Count; $i++) { $lines.Add($rendered[$i]) }
        }
        $lines.Add("")
    }
}

$lines.Add("variables: {}")
$lines.Add("")
$lines.Add("# Optional list of stage names to skip:")
$lines.Add("stagesToSkip: []")

$lines -join [Environment]::NewLine | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Host ""
Write-Host "Generated run config:" -ForegroundColor Green
Write-Host "  $OutputPath"
Write-Host ""
Write-Host "Next step:"
Write-Host "  1. Open the file and review/edit the parameters and branch."
Write-Host "  2. Commit any local changes (or pass -AllowDirty)."
Write-Host "  3. Run: .\Invoke-PipelineRun.ps1 -ConfigPath '$OutputPath'"
