function Install-Arena {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [string]$InstallPath = "C:\FrontArena"
    )

    if ($PSCmdlet.ShouldProcess($InstallPath, "Install Arena $Version")) {
        $msiPath = Get-ArenaMsiPath -Version $Version
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /qn" -Wait
        Write-Information "Arena $Version installed to $InstallPath"
    }
}

function Get-ArenaMsiPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $basePath = "\\fileserver\installers\arena"
    return Join-Path $basePath "FrontArena-$Version.msi"
}

function Test-ArenaInstallation {
    [CmdletBinding()]
    param(
        [string]$InstallPath = "C:\FrontArena"
    )

    $requiredFiles = @("prime.exe", "ael.dll", "acm.dll")
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path (Join-Path $InstallPath $file))) {
            throw "Missing required file: $file"
        }
    }
}
