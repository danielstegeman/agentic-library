<#
.SYNOPSIS
    Retrieves full context for an Azure DevOps pull request: metadata, linked PBI contents, and git diff.

.DESCRIPTION
    Uses `az repos pr show` (reuses the existing `az login` session — no PAT required)
    to retrieve PR metadata, fetches the title/description/acceptance criteria of every
    linked work item via `az boards work-item show`, fetches reviewer comment threads via
    `az devops invoke`, then uses local git to produce the diff between the exact merge
    commits recorded by Azure DevOps.

    TFS system threads (push notifications, auto-merge events) are filtered out — only
    real reviewer threads (those with an explicit status field) are included.

    For large PRs (>50 changed files) the script outputs metadata and the changed-file list
    only, then exits with a LARGE_PR message so the caller can ask the user which paths
    to include before re-running with -PathFilter.

.PARAMETER PrId
    The pull request ID.

.PARAMETER Org
    Azure DevOps organisation URL or short name. Defaults to 'contoso'.

.PARAMETER Project
    Azure DevOps project name. Defaults to 'Contoso'.

.PARAMETER Repo
    Repository name. Defaults to 'contoso-app'.

.PARAMETER RepoPath
    Path to the local git clone. Defaults to the current directory.

.PARAMETER PathFilter
    Optional. Limit the diff to specific paths (passed as -- <path>... to git diff).

.PARAMETER OutputFile
    Path to write the full output to. Defaults to $env:TEMP\pr-<PrId>.md.
    The script prints only the file path to stdout so the agent can read it back
    with the read_file tool.

.EXAMPLE
    .\Get-PrContext.ps1 -PrId 41032

.EXAMPLE
    .\Get-PrContext.ps1 -PrId 41032 -PathFilter 'PrimeObjects/AEL', 'PrimeObjects/Tests'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$PrId,

    [Parameter()]
    [string]$Org = 'contoso',

    [Parameter()]
    [string]$Project = 'Contoso',

    [Parameter()]
    [string]$Repo = 'contoso-app',

    [Parameter()]
    [string]$RepoPath = '.',

    [Parameter()]
    [string[]]$PathFilter,

    [Parameter()]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 1. Fetch PR metadata via az devops
# ---------------------------------------------------------------------------
$orgUrl = if ($Org -match '^https?://') { $Org } else { "https://dev.azure.com/$Org" }

Write-Verbose "Fetching PR $PrId from $orgUrl / $Project / $Repo"

$prJson = (az repos pr show `
    --id $PrId `
    --org $orgUrl `
    --detect false `
    --output json 2>$null) -join "`n"

if ($LASTEXITCODE -ne 0) {
    Write-Error "az repos pr show failed (exit $LASTEXITCODE). Ensure you are logged in with 'az login'."
}

$pr = $prJson | ConvertFrom-Json

$title = $pr.title
$status = if ($pr.isDraft) { 'Draft' } else { $pr.status }
$author = $pr.createdBy.displayName
$sourceBranch = $pr.sourceRefName -replace '^refs/heads/', ''
$targetBranch = $pr.targetRefName -replace '^refs/heads/', ''
$sourceSha = $pr.lastMergeSourceCommit.commitId
$targetSha = $pr.lastMergeTargetCommit.commitId

$repoId = $pr.repository.id

$workItemIds = if (@($pr.workItemRefs).Count -gt 0) {
    @($pr.workItemRefs | ForEach-Object { [int]$_.id })
}
else {
    @()
}

$workItems = if (@($workItemIds).Count -gt 0) {
    ($workItemIds | ForEach-Object { "#$_" }) -join ', '
}
else {
    'none'
}

$reviewers = if (@($pr.reviewers).Count -gt 0) {
    $voteLabel = @{ 10 = 'approved'; 5 = 'approved-with-suggestions'; 0 = 'no vote'; -5 = 'waiting'; -10 = 'rejected' }
    ($pr.reviewers | ForEach-Object {
        $vote = if ($voteLabel.ContainsKey([int]$_.vote)) { $voteLabel[[int]$_.vote] } else { "vote:$($_.vote)" }
        "$($_.displayName) ($vote)"
    }) -join ', '
}
else {
    'none'
}

# ---------------------------------------------------------------------------
# 2. Fetch linked work item (PBI) contents
# ---------------------------------------------------------------------------
$workItemBlocks = foreach ($wiId in $workItemIds) {
    Write-Verbose "Fetching work item $wiId"
    $wiJson = (az boards work-item show `
        --id $wiId `
        --org $orgUrl `
        --output json 2>$null) -join "`n"

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not fetch work item $wiId — skipping."
        continue
    }

    $wi = $wiJson | ConvertFrom-Json
    $fields = $wi.fields

    $wiTitle = $fields.'System.Title'
    $wiType = $fields.'System.WorkItemType'
    $wiState = $fields.'System.State'
    $wiDescription = $fields.'System.Description'
    $wiAcceptance = $fields.'Microsoft.VSTS.Common.AcceptanceCriteria'

    $block = @"

### PBI #$wiId — $wiTitle
- **Type**: $wiType
- **State**: $wiState
"@
    if ($wiDescription) {
        $block += "`n**Description**:`n$($wiDescription.Trim())"
    }
    if ($wiAcceptance) {
        $block += "`n**Acceptance criteria**:`n$($wiAcceptance.Trim())"
    }
    $block
}

# ---------------------------------------------------------------------------
# 2b. Fetch PR comment threads
# ---------------------------------------------------------------------------
# az devops invoke returns string status values; MCP returns integers.
# Normalise both to the canonical label strings.
$intStatusLabel = @{ 1 = 'active'; 2 = 'fixed'; 3 = 'wontfix' }
$knownStringStatuses = @('active', 'fixed', 'wontfix', 'byDesign', 'closed', 'pending', 'unknown')

function Resolve-ThreadStatus {
    param($RawStatus)
    if ($null -eq $RawStatus) { return 'unknown' }
    $asString = "$RawStatus"
    if ($intStatusLabel.ContainsKey([int]($asString -as [int]))) {
        return $intStatusLabel[[int]$asString]
    }
    return $asString.ToLower()
}

$reviewerThreads = @()
try {
    $threadsJson = (az devops invoke `
        --area git `
        --resource pullRequestThreads `
        --route-parameters "repositoryId=$repoId" "pullRequestId=$PrId" `
        --org $orgUrl `
        --detect false `
        --output json 2>$null) -join "`n"

    if ($LASTEXITCODE -eq 0) {
        $threadsData = $threadsJson | ConvertFrom-Json
        $allThreads = if ($threadsData.PSObject.Properties['value']) { $threadsData.value } else { @($threadsData) }
        $reviewerThreads = @($allThreads | Where-Object { $null -ne $_.PSObject.Properties['status'] })
    }
    else {
        Write-Warning "Could not fetch PR threads — skipping comments section."
    }
}
catch {
    Write-Warning "Could not fetch PR threads — skipping comments section."
}

# ---------------------------------------------------------------------------
# 3. Fetch both commits from origin
# ---------------------------------------------------------------------------
$resolvedRepoPath = Resolve-Path -LiteralPath $RepoPath

function Invoke-GitFetch {
    param([string]$Ref)
    $result = git -C $resolvedRepoPath fetch origin $Ref 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Verbose "fetch of '$Ref' failed — will rely on locally available commit."
    }
}

Invoke-GitFetch -Ref $sourceBranch
Invoke-GitFetch -Ref $targetBranch

# Verify commits are reachable; if not, try fetching by SHA directly.
foreach ($sha in @($sourceSha, $targetSha)) {
    $reachable = git -C $resolvedRepoPath cat-file -e "${sha}^{commit}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Verbose "Commit $sha not reachable locally — fetching by SHA."
        git -C $resolvedRepoPath fetch origin $sha 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Cannot resolve commit $sha. Run 'git fetch --all' in $resolvedRepoPath and retry."
        }
    }
}

# ---------------------------------------------------------------------------
# 4. Changed file list
# ---------------------------------------------------------------------------
$changedFiles = git -C $resolvedRepoPath diff --name-status "${targetSha}..${sourceSha}" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "git diff --name-status failed.`n$changedFiles"
}

$fileLines = $changedFiles -split "`n" | Where-Object { $_ -match '\S' }
$fileCount = $fileLines.Count

# ---------------------------------------------------------------------------
# 5–7. Build output (captured so it can also be written to file)
# ---------------------------------------------------------------------------
$capturedOutput = & {
    $shortSource = $sourceSha.Substring(0, 8)
    $shortTarget = $targetSha.Substring(0, 8)

@"
## PR #$PrId — $title
- **Author**: $author
- **Status**: $status
- **Source**: ``$sourceBranch`` → **Target**: ``$targetBranch``
- **Commits**: ``$shortSource`` ← ``$shortTarget``
- **Work items**: $workItems
- **Reviewers**: $reviewers
"@

    if ($workItemBlocks) {
        $workItemBlocks
    }

    # PR comment threads
    $threadCount = $reviewerThreads.Count
    "`n### PR Comments ($threadCount)"
    if ($threadCount -eq 0) {
        'No reviewer comments.'
    }
    else {
        foreach ($thread in $reviewerThreads) {
            $label = Resolve-ThreadStatus -RawStatus $thread.status

            $location = 'general'
            if ($null -ne $thread.threadContext) {
                $filePath = $thread.threadContext.filePath
                $line = if ($thread.threadContext.PSObject.Properties['rightFileStart'] -and $null -ne $thread.threadContext.rightFileStart) {
                    $thread.threadContext.rightFileStart.line
                }
                elseif ($thread.threadContext.PSObject.Properties['leftFileStart'] -and $null -ne $thread.threadContext.leftFileStart) {
                    $thread.threadContext.leftFileStart.line
                }
                else {
                    $null
                }
                $location = if ($null -ne $line) { "${filePath}:${line}" } else { $filePath }
            }

            "THREAD $($thread.id) | status:$label | $location"
            foreach ($comment in $thread.comments) {
                $isDeleted = $comment.PSObject.Properties['isDeleted'] -and $comment.isDeleted
                if ($isDeleted) { continue }
                $commentText = if ($comment.PSObject.Properties['content'] -and $comment.content) { $comment.content } else { '[no content]' }
                "  [$($comment.author.displayName)] $commentText"
            }
            ''
        }
    }

@"

### Changed files ($fileCount)
$($fileLines -join "`n")
"@

    # Guard for large PRs
    $largePrThreshold = 50
    if ($fileCount -gt $largePrThreshold -and -not $PathFilter) {
        Write-Output ''
        Write-Output "LARGE_PR: $fileCount files changed. Re-run with -PathFilter to scope the diff, or confirm to proceed."
        return
    }

    # Full diff
    $diffArgs = @('-C', $resolvedRepoPath, 'diff', "${targetSha}..${sourceSha}")
    if ($PathFilter) {
        $diffArgs += '--'
        $diffArgs += $PathFilter
    }

    $diff = git @diffArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git diff failed.`n$diff"
    }

    if (-not $diff) {
        Write-Output ''
        Write-Output 'No changes between the two commits.'
    }
    else {
        Write-Output ''
        Write-Output '```diff'
        Write-Output $diff
        Write-Output '```'
    }
}

# ---------------------------------------------------------------------------
# 8. Write output to file
# ---------------------------------------------------------------------------
if (-not $OutputFile) {
    $OutputFile = Join-Path $env:TEMP "pr-$PrId.md"
}

$dir = Split-Path -Parent $OutputFile
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$capturedOutput | Set-Content -Path $OutputFile -Encoding UTF8
Write-Host "Output written to: $OutputFile"
