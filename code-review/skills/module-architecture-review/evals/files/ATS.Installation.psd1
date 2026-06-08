@{
    ModuleVersion     = '1.0.0'
    RootModule        = 'ATS.Installation.psm1'
    FunctionsToExport = @(
        'Test-ArenaInstallation',
        'Install-Arena',
        'Get-ArenaMsiPath'
    )
}
