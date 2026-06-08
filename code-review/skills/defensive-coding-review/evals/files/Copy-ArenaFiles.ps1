function Copy-ArenaFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    # Check if destination exists before removing
    if (Test-Path $DestinationPath) {
        Remove-Item -Path $DestinationPath -Force -Recurse
    }

    if (-not (Test-Path $SourcePath)) {
        Write-Warning "Source path '$SourcePath' does not exist"
        return
    }

    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -Recurse

    try {
        $configPath = Join-Path $DestinationPath "config.json"
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        $config.deployedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $config | ConvertTo-Json | Set-Content -Path $configPath
    }
    catch {
        Write-Error "Failed to update config: $_"
        throw
    }
}
