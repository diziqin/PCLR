[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'artifacts' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$versionSource = Get-Content (Join-Path $repoRoot 'Plain Craft Launcher 2/Modules/Base/ModBase.vb') -Raw -Encoding utf8
$version = [regex]::Match($versionSource, 'VersionBaseName As String = "([^"]+)"').Groups[1].Value
$sourceZip = Join-Path $OutputDirectory "PCLR-$version-source.zip"
$coreZip = Join-Path $OutputDirectory 'meloongcore-source.tmp.zip'
& git -C $repoRoot archive --format=zip "--output=$sourceZip" HEAD
if ($LASTEXITCODE) { throw 'Main source archive failed.' }
& git -C (Join-Path $repoRoot 'MeloongCore') archive --format=zip --prefix=MeloongCore/ "--output=$coreZip" HEAD
if ($LASTEXITCODE) { throw 'MeloongCore source archive failed.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$main = [IO.Compression.ZipFile]::Open($sourceZip, [IO.Compression.ZipArchiveMode]::Update)
$core = [IO.Compression.ZipFile]::OpenRead($coreZip)
try {
    foreach ($entry in $core.Entries) {
        if ($entry.FullName.EndsWith('/')) { continue }
        $target = $main.CreateEntry($entry.FullName, [IO.Compression.CompressionLevel]::Optimal)
        $target.LastWriteTime = $entry.LastWriteTime
        $inputStream = $entry.Open()
        $outputStream = $target.Open()
        try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
    }
} finally { $core.Dispose(); $main.Dispose() }
Remove-Item -LiteralPath $coreZip
Write-Output "Packaged $sourceZip with MeloongCore source."
