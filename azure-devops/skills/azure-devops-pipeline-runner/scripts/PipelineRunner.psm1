<#
.SYNOPSIS
    Shared helpers for the azure-devops-pipeline-runner skill scripts.

.DESCRIPTION
    Provides utilities to:
    - Parse Azure DevOps pipeline YAML files and extract their `parameters:` block
    - Resolve pipeline ID from pipeline name via az CLI
    - Detect git repo root, current branch, and uncommitted changes
    - Resolve per-run artifact directories under <repoRoot>/.agent-artifacts/pipeline-runs/
    - Wrap az CLI invocations with consistent JSON parsing and error handling

.NOTES
    Requires: az CLI with the azure-devops extension, and the powershell-yaml module.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Prerequisite {
    [CmdletBinding()]
    param()

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "az CLI is not installed or not on PATH. Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
    }

    $extensions = az extension list --output json 2>$null | ConvertFrom-Json
    if (-not ($extensions | Where-Object { $_.name -eq 'azure-devops' })) {
        throw "The azure-devops extension is not installed. Run: az extension add --name azure-devops"
    }

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        throw "The powershell-yaml module is not installed. Run: Install-Module powershell-yaml -Scope CurrentUser"
    }

    Import-Module powershell-yaml -ErrorAction Stop
}

function Get-RepoRoot {
    [CmdletBinding()]
    param(
        [string]$StartPath = (Get-Location).Path
    )

    Push-Location $StartPath
    try {
        $root = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $root) {
            throw "Not inside a git repository: $StartPath"
        }
        return (Resolve-Path $root).Path
    }
    finally {
        Pop-Location
    }
}

function Get-CurrentGitBranch {
    [CmdletBinding()]
    param([string]$RepoRoot = (Get-RepoRoot))

    Push-Location $RepoRoot
    try {
        $branch = git rev-parse --abbrev-ref HEAD
        if ($LASTEXITCODE -ne 0) { throw "Failed to read current git branch" }
        return $branch.Trim()
    }
    finally { Pop-Location }
}

function Test-UncommittedChange {
    [CmdletBinding()]
    param([string]$RepoRoot = (Get-RepoRoot))

    Push-Location $RepoRoot
    try {
        $status = git status --porcelain
        return [bool]$status
    }
    finally { Pop-Location }
}

function Test-RemoteBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BranchName,

        [string]$RepoRoot = (Get-RepoRoot),
        [string]$Remote = 'origin'
    )

    Push-Location $RepoRoot
    try {
        $result = git ls-remote --heads $Remote $BranchName 2>$null
        return [bool]$result
    }
    finally { Pop-Location }
}

function Get-PipelineYamlPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PipelineName,

        [string]$RepoRoot = (Get-RepoRoot),

        [string]$SearchSubPath = 'OpsObjects'
    )

    $bare = $PipelineName -replace '\.ya?ml$', ''
    $candidates = @(
        (Join-Path $RepoRoot "$SearchSubPath\$bare.yml"),
        (Join-Path $RepoRoot "$SearchSubPath\$bare.yaml")
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    $matchedFiles = @(Get-ChildItem -Path (Join-Path $RepoRoot $SearchSubPath) -Recurse -Filter "$bare.yml" -ErrorAction SilentlyContinue)
    if ($matchedFiles.Count -eq 1) { return $matchedFiles[0].FullName }
    if ($matchedFiles.Count -gt 1) {
        throw "Multiple pipeline files match '$bare.yml':`n$(($matchedFiles | ForEach-Object FullName) -join "`n")"
    }

    throw "Pipeline YAML not found for '$PipelineName' under $RepoRoot\$SearchSubPath"
}

function Get-PipelineParameter {
    <#
    .SYNOPSIS
        Parse the `parameters:` block of a pipeline YAML file.

    .OUTPUTS
        Array of hashtables: @{ Name; Type; Default; Values }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $parsed = ConvertFrom-Yaml $content

    if (-not $parsed.ContainsKey('parameters')) {
        return @()
    }

    $result = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($p in @($parsed['parameters'])) {
        $result.Add(@{
                Name    = [string]$p['name']
                Type    = if ($p.ContainsKey('type')) { [string]$p['type'] } else { 'string' }
                Default = if ($p.ContainsKey('default')) { $p['default'] } else { $null }
                Values  = if ($p.ContainsKey('values')) { @($p['values']) } else { @() }
            })
    }
    # Return the list itself so the caller can use @(...) to get a plain array without re-wrapping.
    return $result.ToArray()
}

function Get-AzdoConnection {
    <#
    .SYNOPSIS
        Read organization + project from the git remote URL.

    .DESCRIPTION
        Supports https://dev.azure.com/<org>/<project>/_git/<repo> and
        https://<org>@dev.azure.com/<org>/<project>/_git/<repo>.
    #>
    [CmdletBinding()]
    param([string]$RepoRoot = (Get-RepoRoot))

    Push-Location $RepoRoot
    try {
        $remote = git config --get remote.origin.url
        if (-not $remote) { throw "No origin remote configured for $RepoRoot" }

        if ($remote -match 'dev\.azure\.com/([^/]+)/([^/]+)/_git/') {
            return @{
                Organization    = $Matches[1]
                OrganizationUrl = "https://dev.azure.com/$($Matches[1])"
                Project         = $Matches[2]
            }
        }
        if ($remote -match '([^@/]+)\.visualstudio\.com/([^/]+)/_git/') {
            return @{
                Organization    = $Matches[1]
                OrganizationUrl = "https://$($Matches[1]).visualstudio.com"
                Project         = $Matches[2]
            }
        }
        throw "Could not parse Azure DevOps org/project from remote: $remote"
    }
    finally { Pop-Location }
}

function Invoke-Az {
    <#
    .SYNOPSIS
        Run an az CLI command and parse the JSON response.

    .PARAMETER ArgumentList
        Arguments to pass to az (do not include 'az').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    Write-Verbose ("az " + ($ArgumentList -join ' '))
    $output = & az @ArgumentList --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az command failed (exit $LASTEXITCODE): az $($ArgumentList -join ' ')`n$output"
    }
    if (-not $output) { return $null }
    try {
        return ($output | Out-String | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse az output as JSON: $_`nRaw: $output"
    }
}

function Resolve-PipelineId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PipelineName,

        [Parameter(Mandatory)]
        [string]$Organization,

        [Parameter(Mandatory)]
        [string]$Project
    )

    $bare = $PipelineName -replace '\.ya?ml$', ''
    $pipelines = Invoke-Az -ArgumentList @(
        'pipelines', 'show',
        '--name', $bare,
        '--organization', $Organization,
        '--project', $Project
    )
    if (-not $pipelines) {
        throw "Pipeline '$bare' is not registered in $Organization/$Project. Create it first via Azure DevOps."
    }
    return $pipelines.id
}

function Get-RunArtifactDir {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BuildNumber,

        [string]$RepoRoot = (Get-RepoRoot),

        [switch]$CreateIfMissing
    )

    $safe = $BuildNumber -replace '[^\w\.\-]', '_'
    $dir = Join-Path $RepoRoot ".agent-artifacts\pipeline-runs\$safe"
    if ($CreateIfMissing -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-PendingConfigDir {
    [CmdletBinding()]
    param(
        [string]$RepoRoot = (Get-RepoRoot),
        [switch]$CreateIfMissing
    )

    $dir = Join-Path $RepoRoot '.agent-artifacts\pipeline-runs\_pending'
    if ($CreateIfMissing -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function ConvertTo-RunParameterString {
    <#
    .SYNOPSIS
        Convert a hashtable into the `key=value` pairs expected by az pipelines run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Map
    )

    $pairs = @()
    foreach ($key in $Map.Keys) {
        $value = $Map[$key]
        if ($value -is [bool]) {
            $value = if ($value) { 'True' } else { 'False' }
        }
        elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            $value = ($value | ForEach-Object { "$_" }) -join ','
        }
        $pairs += "$key=$value"
    }
    return , $pairs
}

function Get-AzdoAccessToken {
    <#
    .SYNOPSIS
        Acquire an Azure DevOps bearer token via az CLI.
    #>
    [CmdletBinding()]
    param()

    $json = az account get-access-token --resource '499b84ac-1321-427f-aa17-267ca6975798' --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to acquire Azure DevOps access token. Run 'az login' first.`n$json"
    }
    $token = ($json | Out-String | ConvertFrom-Json).accessToken
    if (-not $token) { throw "Empty access token from az account get-access-token" }
    return $token
}

function Invoke-AzdoRestApi {
    <#
    .SYNOPSIS
        Call an Azure DevOps REST endpoint with a UTF-8 JSON body using Invoke-RestMethod.

    .DESCRIPTION
        Bypasses `az rest`, which on Windows hosts truncates inline bodies and mangles
        @file bodies via cp1252 encoding. Encodes the body as UTF-8 bytes so any
        characters survive the round-trip.

    .PARAMETER Method
        HTTP method (GET, POST, PATCH, PUT, DELETE).

    .PARAMETER Url
        Absolute URL of the REST endpoint.

    .PARAMETER Body
        Optional object to serialize to JSON for the request body. Pass $null for no body.

    .PARAMETER Depth
        JSON serialization depth. Defaults to 20 to handle deeply nested templateParameters.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        [object]$Body,
        [int]$Depth = 20
    )

    $token = Get-AzdoAccessToken
    $headers = @{ Authorization = "Bearer $token" }

    $args = @{
        Method  = $Method
        Uri     = $Url
        Headers = $headers
    }

    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth $Depth -Compress
        $args['ContentType'] = 'application/json; charset=utf-8'
        # Pass the JSON as a string, not a byte array. Invoke-RestMethod in PS 7 will encode
        # the body as UTF-8 when ContentType declares charset=utf-8. Passing byte[] causes
        # the request to be sent as multipart/form-data, which the ADO API rejects with
        # "runParameters cannot be null" because it cannot deserialize the body.
        $args['Body'] = $json
    }

    try {
        return Invoke-RestMethod @args
    }
    catch {
        # PowerShell 7 surfaces the response body via ErrorDetails.Message; PowerShell 5 requires
        # reading from the response stream directly.
        $errorBody = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $errorBody = $_.ErrorDetails.Message
        }
        elseif ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $errorBody = $reader.ReadToEnd()
            }
            catch { $errorBody = $null }
        }
        if ($errorBody) {
            throw "Azure DevOps REST $Method $Url failed: $($_.Exception.Message)`nBody sent: $json`nResponse: $errorBody"
        }
        throw "Azure DevOps REST $Method $Url failed: $($_.Exception.Message)`nBody sent: $json"
    }
}

Export-ModuleMember -Function @(
    'Assert-Prerequisite',
    'Get-RepoRoot',
    'Get-CurrentGitBranch',
    'Test-UncommittedChange',
    'Test-RemoteBranch',
    'Get-PipelineYamlPath',
    'Get-PipelineParameter',
    'Get-AzdoConnection',
    'Invoke-Az',
    'Resolve-PipelineId',
    'Get-RunArtifactDir',
    'Get-PendingConfigDir',
    'ConvertTo-RunParameterString',
    'Get-AzdoAccessToken',
    'Invoke-AzdoRestApi'
)
