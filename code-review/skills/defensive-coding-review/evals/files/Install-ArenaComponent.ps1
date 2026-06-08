function Install-ArenaComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComponentName,

        [string]$Version,

        [string]$InstallPath
    )

    if ([string]::IsNullOrEmpty($Version)) {
        throw "Version is required"
    }

    if ([string]::IsNullOrEmpty($InstallPath)) {
        throw "InstallPath is required"
    }

    $installerPath = Join-Path $InstallPath "$ComponentName-$Version.msi"

    if (-not (Test-Path $installerPath)) {
        return $false
    }

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installerPath`" /qn" -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        return $true
    }
    else {
        return $false
    }
}
