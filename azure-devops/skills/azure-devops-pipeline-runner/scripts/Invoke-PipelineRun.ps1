<#
.SYNOPSIS
    Trigger an Azure DevOps pipeline run, or process the results of a completed run.

.DESCRIPTION
    Two mutually-exclusive modes:

    Trigger mode (-ConfigPath):
        Validates the YAML run-config, checks for uncommitted changes and a
        pushed branch, then triggers the pipeline via az CLI. Persists run state
        to .agent-artifacts/pipeline-runs/<buildNumber>/run-state.json and exits
        immediately. Use the printed command to process results once the run
        completes.

    Report mode (-BuildNumber or -RunStateFile):
        Reads the run-state, queries az for status. If the run is still in
        flight, prints a status line and exits with code 2 so the agent waits.
        Once complete, downloads failed-task logs and test results, then writes
        a focused report.md with Summary / Failures / Failed tests / Warnings /
        Timing sections.

.PARAMETER ConfigPath
    Path to a run-config.yml produced by New-PipelineRunConfig.ps1. Triggers the pipeline.

.PARAMETER BuildNumber
    Azure DevOps build number of a previously-triggered run. Generates the report.

.PARAMETER RunStateFile
    Explicit path to a run-state.json. Generates the report.

.PARAMETER AllowDirty
    Trigger mode only. Skip the uncommitted-changes guard.

.PARAMETER KeepRawLogs
    Report mode only. Save downloaded raw logs under raw/ inside the run folder.

.EXAMPLE
    .\Invoke-PipelineRun.ps1 -ConfigPath .agent-artifacts/pipeline-runs/_pending/run-config.yml

.EXAMPLE
    .\Invoke-PipelineRun.ps1 -BuildNumber 20260604.3
#>

[CmdletBinding(DefaultParameterSetName = 'Trigger')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Trigger')]
    [string]$ConfigPath,

    [Parameter(Mandatory, ParameterSetName = 'ReportByBuildNumber')]
    [string]$BuildNumber,

    [Parameter(Mandatory, ParameterSetName = 'ReportByStateFile')]
    [string]$RunStateFile,

    [Parameter(ParameterSetName = 'Trigger')]
    [switch]$AllowDirty,

    [Parameter(ParameterSetName = 'ReportByBuildNumber')]
    [Parameter(ParameterSetName = 'ReportByStateFile')]
    [switch]$KeepRawLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'PipelineRunner.psm1') -Force
Assert-Prerequisite

#--------------------------------------------------------------------
# Trigger mode
#--------------------------------------------------------------------

function Invoke-TriggerMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [switch]$AllowDirty
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config not found: $ConfigPath"
    }
    $ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Yaml
    foreach ($key in 'pipeline', 'branch') {
        if (-not $config.ContainsKey($key) -or -not $config[$key]) {
            throw "Config missing required key: $key"
        }
    }

    $repoRoot = Get-RepoRoot
    $connection = Get-AzdoConnection -RepoRoot $repoRoot
    $pipelineName = $config['pipeline']
    $branch = $config['branch']

    $yamlPath = Get-PipelineYamlPath -PipelineName $pipelineName -RepoRoot $repoRoot
    $schema = Get-PipelineParameter -Path $yamlPath
    $schemaByName = @{}
    foreach ($p in $schema) { $schemaByName[$p.Name] = $p }

    $rawParams = if ($config.ContainsKey('parameters') -and $config['parameters']) { $config['parameters'] } else { @{} }
    $params = [ordered]@{}
    foreach ($name in $rawParams.Keys) {
        if (-not $schemaByName.ContainsKey($name)) {
            throw "Parameter '$name' is not defined in $pipelineName.yml"
        }
        $value = $rawParams[$name]
        $schemaEntry = $schemaByName[$name]
        $allowedValues = @($schemaEntry.Values)
        if ($allowedValues.Count -gt 0) {
            $valueAsString = "$value"
            if ($valueAsString -notin $allowedValues) {
                throw "Parameter '$name' value '$valueAsString' is not in allowed set [$($allowedValues -join ', ')]"
            }
        }
        # ADO's POST /pipelines/{id}/runs endpoint rejects real (non-preview) runs whose
        # templateParameters contain JSON object/array values with: "Value cannot be null.
        # Parameter name: runParameters". The pipeline runtime accepts the same value as a
        # JSON-encoded string, so we serialize object/array params here. Scalars pass through
        # unchanged.
        if ($value -is [System.Collections.IDictionary] -or
            ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string]))) {
            $params[$name] = ($value | ConvertTo-Json -Depth 20 -Compress)
        }
        else {
            $params[$name] = $value
        }
    }

    $variables = if ($config.ContainsKey('variables') -and $config['variables']) { $config['variables'] } else { @{} }
    if ($null -eq $variables) { $variables = @{} }
    $stagesToSkip = if ($config.ContainsKey('stagesToSkip') -and $config['stagesToSkip']) { @($config['stagesToSkip']) } else { @() }
    if ($null -eq $stagesToSkip) { $stagesToSkip = @() }

    if (Test-UncommittedChange -RepoRoot $repoRoot) {
        if (-not $AllowDirty) {
            throw "Uncommitted changes detected. Commit them first, or pass -AllowDirty to override."
        }
        Write-Warning "Proceeding with uncommitted changes (-AllowDirty)."
    }

    if (-not (Test-RemoteBranch -BranchName $branch -RepoRoot $repoRoot)) {
        throw "Branch '$branch' not found on remote. Push first: git push -u origin $branch"
    }

    $pipelineId = if ($config.ContainsKey('pipelineId') -and $config['pipelineId']) {
        [int]$config['pipelineId']
    }
    else {
        Resolve-PipelineId -PipelineName $pipelineName `
            -Organization $connection.OrganizationUrl `
            -Project $connection.Project
    }

    # Build the REST request body for POST /_apis/pipelines/{id}/runs.
    # This endpoint accepts object/array templateParameters, variables, and stagesToSkip
    # which `az pipelines run` cannot pass.
    $refName = if ($branch -like 'refs/*') { $branch } else { "refs/heads/$branch" }
    $restBody = [ordered]@{
        resources = @{
            repositories = @{
                self = @{ refName = $refName }
            }
        }
    }
    if ($params.Count -gt 0) { $restBody['templateParameters'] = $params }

    $varCount = if ($variables -is [System.Collections.IDictionary]) { $variables.Count } else { 0 }
    if ($varCount -gt 0) {
        $varMap = [ordered]@{}
        foreach ($k in $variables.Keys) {
            $v = $variables[$k]
            # The REST API expects variables in shape: { value: "...", isSecret?: bool }.
            if ($v -is [System.Collections.IDictionary] -and $v.Contains('value')) {
                $varMap[$k] = $v
            }
            else {
                $varMap[$k] = @{ value = "$v" }
            }
        }
        $restBody['variables'] = $varMap
    }
    $skipCount = if ($stagesToSkip -is [System.Collections.IEnumerable] -and -not ($stagesToSkip -is [string])) { @($stagesToSkip).Count } else { 0 }
    if ($skipCount -gt 0) { $restBody['stagesToSkip'] = @($stagesToSkip) }

    $url = "$($connection.OrganizationUrl)/$($connection.Project)/_apis/pipelines/$pipelineId/runs?api-version=7.1-preview.1"

    Write-Host "Triggering pipeline '$pipelineName' on branch '$branch' via REST API..." -ForegroundColor Cyan
    $run = Invoke-AzdoRestApi -Method POST -Url $url -Body $restBody

    $buildNumber = $run.name
    $runId = $run.id
    $webUrl = if ($run._links -and $run._links.web) {
        $run._links.web.href
    }
    else {
        "$($connection.OrganizationUrl)/$($connection.Project)/_build/results?buildId=$runId"
    }

    $runDir = Get-RunArtifactDir -BuildNumber $buildNumber -RepoRoot $repoRoot -CreateIfMissing

    $state = [ordered]@{
        pipelineName    = $pipelineName
        pipelineId      = $pipelineId
        runId           = $runId
        buildNumber     = $buildNumber
        organizationUrl = $connection.OrganizationUrl
        project         = $connection.Project
        sourceBranch    = $branch
        url             = $webUrl
        triggeredAt     = (Get-Date).ToString('o')
        parameters      = $params
        variables       = $variables
        stagesToSkip    = $stagesToSkip
    }
    $statePath = Join-Path $runDir 'run-state.json'
    $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding UTF8

    $configCopy = Join-Path $runDir 'run-config.yml'
    Copy-Item -LiteralPath $ConfigPath -Destination $configCopy -Force

    Write-Host ""
    Write-Host "Pipeline run queued." -ForegroundColor Green
    Write-Host "  Build number : $buildNumber"
    Write-Host "  Run ID       : $runId"
    Write-Host "  URL          : $webUrl"
    Write-Host "  Run state    : $statePath"
    Write-Host ""
    Write-Host "Re-invoke the agent once the run finishes and run:" -ForegroundColor Yellow
    Write-Host "  .\Invoke-PipelineRun.ps1 -BuildNumber $buildNumber"
    Write-Host ""
}

#--------------------------------------------------------------------
# Report mode
#--------------------------------------------------------------------

function Resolve-RunStateFile {
    [CmdletBinding()]
    param(
        [string]$BuildNumber,
        [string]$RunStateFile
    )

    if ($RunStateFile) {
        if (-not (Test-Path -LiteralPath $RunStateFile)) {
            throw "Run state file not found: $RunStateFile"
        }
        return (Resolve-Path -LiteralPath $RunStateFile).Path
    }

    $repoRoot = Get-RepoRoot
    $runDir = Get-RunArtifactDir -BuildNumber $BuildNumber -RepoRoot $repoRoot
    $statePath = Join-Path $runDir 'run-state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        throw "No run-state.json for build $BuildNumber at $statePath. Did you trigger via Invoke-PipelineRun.ps1?"
    }
    return $statePath
}

function Get-RunTimelineRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][int]$RunId
    )

    $url = "$OrganizationUrl/$Project/_apis/build/builds/$RunId/timeline?api-version=7.1"
    $raw = az rest --method get --url $url 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to fetch timeline: $raw"
    }
    return ($raw | Out-String | ConvertFrom-Json)
}

function Get-RunLogRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OrganizationUrl,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][int]$RunId,
        [Parameter(Mandatory)][int]$LogId
    )

    $url = "$OrganizationUrl/$Project/_apis/build/builds/$RunId/logs/$LogId" + '?api-version=7.1'
    $tokenJson = az account get-access-token --resource '499b84ac-1321-427f-aa17-267ca6975798' --output json 2>$null | ConvertFrom-Json
    if (-not $tokenJson) {
        Write-Warning "Could not acquire Azure DevOps access token for log $LogId"
        return $null
    }
    try {
        return (Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $($tokenJson.accessToken)" } -Method Get)
    }
    catch {
        Write-Warning "Failed to download log $LogId : $_"
        return $null
    }
}

function Format-Duration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][TimeSpan]$Span)
    if ($Span.TotalHours -ge 1) { return ('{0:N0}h {1:N0}m' -f $Span.Hours, $Span.Minutes) }
    if ($Span.TotalMinutes -ge 1) { return ('{0:N0}m {1:N0}s' -f $Span.Minutes, $Span.Seconds) }
    return ('{0:N1}s' -f $Span.TotalSeconds)
}

function Get-ErrorContextLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogText,
        [int]$ContextLines = 20
    )

    $lines = $LogText -split "`r?`n"
    $hits = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^##\[error\]' -or $lines[$i] -match '(?i)\bERROR\b' -or $lines[$i] -match '(?i)\bFAILED\b' -or $lines[$i] -match 'Exception') {
            $hits.Add($i)
        }
    }
    if ($hits.Count -eq 0) {
        $tail = [Math]::Max(0, $lines.Length - 30)
        return ($lines[$tail..($lines.Length - 1)] -join "`n")
    }

    $ranges = [System.Collections.Generic.List[object]]::new()
    foreach ($hit in $hits) {
        $start = [Math]::Max(0, $hit - $ContextLines)
        $end = [Math]::Min($lines.Length - 1, $hit + $ContextLines)
        $ranges.Add(@{ Start = $start; End = $end })
    }

    $merged = [System.Collections.Generic.List[object]]::new()
    foreach ($range in ($ranges | Sort-Object { $_.Start })) {
        if ($merged.Count -gt 0 -and $range.Start -le $merged[-1].End + 1) {
            $merged[-1].End = [Math]::Max($merged[-1].End, $range.End)
        }
        else {
            $merged.Add(@{ Start = $range.Start; End = $range.End })
        }
    }

    $sections = foreach ($range in $merged) {
        $snippet = $lines[$range.Start..$range.End] -join "`n"
        "[lines $($range.Start + 1)-$($range.End + 1)]`n$snippet"
    }
    return ($sections -join "`n---`n")
}

function Get-WarningLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogText)

    $found = [regex]::Matches($LogText, '(?m)^##\[warning\].*$')
    return ($found | ForEach-Object { $_.Value })
}

function Invoke-ReportMode {
    [CmdletBinding()]
    param(
        [string]$BuildNumber,
        [string]$RunStateFile,
        [switch]$KeepRawLogs
    )

    $statePath = Resolve-RunStateFile -BuildNumber $BuildNumber -RunStateFile $RunStateFile
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

    Write-Host "Checking status of build $($state.buildNumber) (run $($state.runId))..." -ForegroundColor Cyan
    $run = Invoke-Az -ArgumentList @(
        'pipelines', 'runs', 'show',
        '--id', "$($state.runId)",
        '--organization', $state.organizationUrl,
        '--project', $state.project
    )

    if ($run.status -ne 'completed') {
        Write-Host ""
        Write-Host "Run is still $($run.status). Try again once it finishes." -ForegroundColor Yellow
        Write-Host "  URL: $($state.url)"
        exit 2
    }

    $runDir = Split-Path -Parent $statePath
    $timeline = Get-RunTimelineRest -OrganizationUrl $state.organizationUrl -Project $state.project -RunId $state.runId

    $tasks = @($timeline.records | Where-Object { $_.type -eq 'Task' })
    $jobs = @($timeline.records | Where-Object { $_.type -eq 'Job' })
    $stages = @($timeline.records | Where-Object { $_.type -eq 'Stage' })

    $failedTasks = @($tasks | Where-Object { $_.result -in 'failed', 'canceled' -and $_.log })
    $allWarnings = [System.Collections.Generic.List[string]]::new()

    if ($KeepRawLogs.IsPresent) {
        $rawDir = Join-Path $runDir 'raw'
        New-Item -ItemType Directory -Path $rawDir -Force | Out-Null
    }

    $report = [System.Collections.Generic.List[string]]::new()
    $report.Add("# Pipeline run report: $($state.pipelineName) — build $($state.buildNumber)")
    $report.Add("")
    $report.Add("## Summary")
    $report.Add("")
    $report.Add("| Field | Value |")
    $report.Add("|-------|-------|")
    $report.Add("| Pipeline | $($state.pipelineName) |")
    $report.Add("| Build number | $($state.buildNumber) |")
    $report.Add("| Run ID | $($state.runId) |")
    $report.Add("| Status | $($run.status) |")
    $report.Add("| Result | $($run.result) |")
    $report.Add("| Branch | $($state.sourceBranch) |")
    if ($run.PSObject.Properties.Name -contains 'createdDate') { $report.Add("| Queued | $($run.createdDate) |") }
    if ($run.PSObject.Properties.Name -contains 'finishedDate') { $report.Add("| Finished | $($run.finishedDate) |") }
    if ($run.createdDate -and $run.finishedDate) {
        $duration = [datetime]$run.finishedDate - [datetime]$run.createdDate
        $report.Add("| Duration | $(Format-Duration -Span $duration) |")
    }
    $report.Add("| URL | $($state.url) |")
    $report.Add("")
    $report.Add("### Parameters")
    $report.Add("")
    if ($state.parameters -and ($state.parameters.PSObject.Properties.Name.Count -gt 0)) {
        $report.Add('```yaml')
        foreach ($prop in $state.parameters.PSObject.Properties) {
            $report.Add("$($prop.Name): $($prop.Value)")
        }
        $report.Add('```')
    }
    else {
        $report.Add("_(none)_")
    }
    $report.Add("")

    # Failures section
    $report.Add("## Failures")
    $report.Add("")
    if ($failedTasks.Count -eq 0) {
        $report.Add("_No failed tasks._")
        $report.Add("")
    }
    else {
        $jobsById = @{}
        foreach ($j in $jobs) { $jobsById[$j.id] = $j }
        $stagesById = @{}
        foreach ($s in $stages) { $stagesById[$s.id] = $s }

        foreach ($task in $failedTasks) {
            $job = if ($task.parentId -and $jobsById.ContainsKey($task.parentId)) { $jobsById[$task.parentId] } else { $null }
            $stage = if ($job -and $job.parentId -and $stagesById.ContainsKey($job.parentId)) { $stagesById[$job.parentId] } else { $null }
            $pathParts = @()
            if ($stage) { $pathParts += $stage.name }
            if ($job) { $pathParts += $job.name }
            $pathParts += $task.name
            $path = $pathParts -join ' / '

            $report.Add("### $path")
            $report.Add("")
            $report.Add("- Result: $($task.result)")
            if ($task.startTime -and $task.finishTime) {
                $taskDuration = [datetime]$task.finishTime - [datetime]$task.startTime
                $report.Add("- Duration: $(Format-Duration -Span $taskDuration)")
            }
            $logUrl = "$($state.url)&l=$($task.log.id)"
            $report.Add("- Log: $logUrl")
            $report.Add("")

            $logText = Get-RunLogRest -OrganizationUrl $state.organizationUrl -Project $state.project -RunId $state.runId -LogId $task.log.id
            if ($logText) {
                if ($KeepRawLogs.IsPresent) {
                    $safeName = ($path -replace '[^\w\.\-]', '_')
                    $logText | Set-Content -LiteralPath (Join-Path $rawDir "$safeName.log") -Encoding UTF8
                }
                $snippet = Get-ErrorContextLine -LogText $logText
                $report.Add('```')
                $report.Add($snippet)
                $report.Add('```')
                $report.Add("")

                foreach ($w in (Get-WarningLine -LogText $logText)) { $allWarnings.Add($w) | Out-Null }
            }
            else {
                $report.Add("_(log unavailable)_")
                $report.Add("")
            }
        }
    }

    # Failed tests
    $report.Add("## Failed tests")
    $report.Add("")
    $failedTests = @()
    try {
        $testApi = "$($state.organizationUrl)/$($state.project)/_apis/test/runs?buildIds=$($state.runId)&api-version=7.1"
        $testRunsResp = az rest --method get --url $testApi 2>$null | Out-String | ConvertFrom-Json
        foreach ($tr in @($testRunsResp.value)) {
            $resultsApi = "$($state.organizationUrl)/$($state.project)/_apis/test/runs/$($tr.id)/results?outcomes=Failed&api-version=7.1"
            $results = az rest --method get --url $resultsApi 2>$null | Out-String | ConvertFrom-Json
            foreach ($r in @($results.value)) { $failedTests += $r }
        }
    }
    catch {
        Write-Warning "Could not retrieve test results: $_"
    }

    if ($failedTests.Count -eq 0) {
        $report.Add("_No failed tests reported._")
        $report.Add("")
    }
    else {
        foreach ($t in $failedTests) {
            $report.Add("### $($t.testCase.name)")
            $report.Add("")
            if ($t.errorMessage) {
                $report.Add('```')
                $report.Add($t.errorMessage)
                $report.Add('```')
            }
            if ($t.stackTrace) {
                $report.Add("<details><summary>Stack trace</summary>")
                $report.Add("")
                $report.Add('```')
                $report.Add($t.stackTrace)
                $report.Add('```')
                $report.Add("</details>")
            }
            $report.Add("")
        }
    }

    # Warnings (from failed-task logs)
    $report.Add("## Warnings")
    $report.Add("")
    if ($allWarnings.Count -eq 0) {
        $report.Add("_No warnings collected from failed tasks._")
        $report.Add("")
    }
    else {
        $unique = $allWarnings | Select-Object -Unique
        $report.Add('```')
        $unique | ForEach-Object { $report.Add($_) }
        $report.Add('```')
        $report.Add("")
    }

    # Timing
    $report.Add("## Timing")
    $report.Add("")
    $report.Add("| Stage / Job | Result | Duration |")
    $report.Add("|-------------|--------|----------|")
    $stageRows = @()
    foreach ($stage in ($stages | Sort-Object order)) {
        $dur = if ($stage.startTime -and $stage.finishTime) { Format-Duration -Span ([datetime]$stage.finishTime - [datetime]$stage.startTime) } else { '-' }
        $report.Add("| **$($stage.name)** | $($stage.result) | $dur |")
        foreach ($job in ($jobs | Where-Object { $_.parentId -eq $stage.id } | Sort-Object order)) {
            $jobDur = if ($job.startTime -and $job.finishTime) { Format-Duration -Span ([datetime]$job.finishTime - [datetime]$job.startTime) } else { '-' }
            $report.Add("| &nbsp;&nbsp;$($job.name) | $($job.result) | $jobDur |")
            if ($job.startTime -and $job.finishTime) {
                $stageRows += [PSCustomObject]@{
                    Name     = "$($stage.name) / $($job.name)"
                    Duration = [datetime]$job.finishTime - [datetime]$job.startTime
                }
            }
        }
    }
    $report.Add("")
    if ($stageRows.Count -gt 0) {
        $top5 = $stageRows | Sort-Object Duration -Descending | Select-Object -First 5
        $report.Add("**Top 5 slowest jobs:**")
        $report.Add("")
        foreach ($row in $top5) {
            $report.Add("- $($row.Name) — $(Format-Duration -Span $row.Duration)")
        }
        $report.Add("")
    }

    $reportPath = Join-Path $runDir 'report.md'
    $report -join [Environment]::NewLine | Set-Content -LiteralPath $reportPath -Encoding UTF8

    Write-Host ""
    Write-Host "Report written:" -ForegroundColor Green
    Write-Host "  $reportPath"
    Write-Host ""
    Write-Host "Final result: $($run.result)"
    if ($run.result -ne 'succeeded') { exit 1 }
}

#--------------------------------------------------------------------
# Dispatch
#--------------------------------------------------------------------

switch ($PSCmdlet.ParameterSetName) {
    'Trigger' { Invoke-TriggerMode -ConfigPath $ConfigPath -AllowDirty:$AllowDirty }
    default { Invoke-ReportMode -BuildNumber $BuildNumber -RunStateFile $RunStateFile -KeepRawLogs:$KeepRawLogs }
}
