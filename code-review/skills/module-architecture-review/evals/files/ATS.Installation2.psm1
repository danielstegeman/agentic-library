function Get-SafePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return $Path.TrimEnd('\', '/')
}

function Install-Arena {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallPath
    )

    $safePath = Get-SafePath -Path $InstallPath
    Write-Information "Installing to $safePath"
    # ... installation logic
}
