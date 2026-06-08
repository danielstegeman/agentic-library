function Get-SafePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return $Path.TrimEnd('\', '/')
}

function Set-ArenaConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $safePath = Get-SafePath -Path $ConfigPath
    Write-Information "Configuring at $safePath"
    # ... configuration logic
}
