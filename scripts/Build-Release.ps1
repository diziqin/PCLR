[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug', 'Snapshot')][string]$Configuration = 'Release',
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'artifacts' }
$versionSource = Get-Content (Join-Path $repoRoot 'Plain Craft Launcher 2/Modules/Base/ModBase.vb') -Raw -Encoding utf8
$version = [regex]::Match($versionSource, 'VersionBaseName As String = "([^"]+)"').Groups[1].Value
if (-not $version) { throw 'Cannot read the application version.' }
$msbuild = Get-Command msbuild -ErrorAction SilentlyContinue
if ($msbuild) {
    $msbuildPath = $msbuild.Source
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio MSBuild with .NET desktop build tools is required.' }
    $msbuildPath = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild/**/Bin/MSBuild.exe' | Select-Object -First 1
    if (-not $msbuildPath) { throw 'MSBuild was not found.' }
}
Push-Location $repoRoot
try {
    & dotnet restore PCLCS/PCLCS.csproj
    if ($LASTEXITCODE) { throw 'NuGet restore failed.' }
    & $msbuildPath 'Plain Craft Launcher 2/Plain Craft Launcher 2.vbproj' /m /nologo /verbosity:minimal "/p:Configuration=$Configuration"
    if ($LASTEXITCODE) { throw "MSBuild failed for $Configuration." }
    $builtExe = Join-Path $repoRoot "Plain Craft Launcher 2/obj/$Configuration/Plain Craft Launcher 2.exe"
    if (-not (Test-Path -LiteralPath $builtExe)) { throw "Build output is missing: $builtExe" }
    & (Join-Path $PSScriptRoot 'Verify-Build.ps1') -Executable $builtExe -ExpectedVersion $version
    $stage = Join-Path $OutputDirectory "stage/$Configuration"
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item -LiteralPath $builtExe -Destination (Join-Path $stage 'PCLR.exe')
    foreach ($file in @('README.md', 'LICENCE', 'THIRD_PARTY_NOTICES.md', 'UPSTREAM.json')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination $stage
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'MeloongCore/LICENSE.txt') -Destination (Join-Path $stage 'MeloongCore.LICENSE.txt')
    $metadata = [ordered]@{
        product = 'Plain Craft Launcher (PCL) PCLR'
        version = $version
        configuration = $Configuration
        commit = (& git rev-parse HEAD)
        upstream = (Get-Content (Join-Path $repoRoot 'UPSTREAM.json') -Raw -Encoding utf8 | ConvertFrom-Json)
        minecraftDownloadEnabled = $true
        executableSha256 = (Get-FileHash -LiteralPath (Join-Path $stage 'PCLR.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'BUILD.json') -Encoding utf8NoBOM
    $stem = "PCLR-$version-windows-$Configuration"
    Copy-Item -LiteralPath $builtExe -Destination (Join-Path $OutputDirectory "$stem.exe")
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath (Join-Path $OutputDirectory "$stem.zip") -Force
    Write-Output "Packaged $stem"
} finally {
    Pop-Location
}
