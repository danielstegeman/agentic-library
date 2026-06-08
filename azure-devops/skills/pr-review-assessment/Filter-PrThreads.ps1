<#
.SYNOPSIS
    Filters raw Azure DevOps pull request thread JSON down to human reviewer threads only,
    and formats them as token-optimized plain text.

.DESCRIPTION
    The mcp_microsoft_azu_repo_list_pull_request_threads MCP tool returns large JSON payloads
    dominated by TFS system push-notification threads. This script drops those and formats
    the remaining reviewer threads as compact plain text for use in the PR review assessment
    skill.

    Threads without a `status` field are TFS system events (push notifications, PR published
    events). Only threads with an explicit status are real reviewer threads.

    Status labels:
      1 = active   (needs assessment)
      2 = fixed    (already resolved)
      3 = wontfix  (author responded, reviewer accepted)

.PARAMETER Path
    Path to the content.json file written by the MCP tool call.

.EXAMPLE
    .\Filter-PrThreads.ps1 -Path "C:\...\content.json"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path
)

$StatusLabel = @{
    1 = 'active'
    2 = 'fixed'
    3 = 'wontfix'
}

$threads = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

$reviewerThreads = $threads | Where-Object { $null -ne $_.PSObject.Properties['status'] }

$output = foreach ($thread in $reviewerThreads) {
    $label = if ($StatusLabel.ContainsKey([int]$thread.status)) { $StatusLabel[[int]$thread.status] } else { "status:$($thread.status)" }

    $location = 'general'
    if ($null -ne $thread.threadContext) {
        $filePath = $thread.threadContext.filePath
        $line = if ($thread.threadContext.PSObject.Properties['rightFileStart'] -and $null -ne $thread.threadContext.rightFileStart) {
            $thread.threadContext.rightFileStart.line
        } elseif ($thread.threadContext.PSObject.Properties['leftFileStart'] -and $null -ne $thread.threadContext.leftFileStart) {
            $thread.threadContext.leftFileStart.line
        } else {
            $null
        }
        $location = if ($null -ne $line) { "$filePath`:$line" } else { $filePath }
    }

    "THREAD $($thread.id) | status:$label | $location"
    foreach ($comment in $thread.comments) {
        "  [$($comment.author.displayName)] $($comment.content)"
    }
    ''
}

$output
