[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReleaseMetadata,
    [string]$OutputDirectory,
    [string[]]$ExcludedCommits = @('5843649cfa7fc2d7727fa43c7a43f8370f5aaa98')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'artifacts/upstream' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$inspectionDirectory = Join-Path $OutputDirectory 'inspection'
New-Item -ItemType Directory -Path $inspectionDirectory -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Get-NormalizedVersion([string]$Value) {
    $numbers = @($Value -split '\.')
    while ($numbers.Count -lt 4) { $numbers += '0' }
    return ($numbers -join '.')
}
$upstreamTip = '6b9a50df911c9d68b69b24c979efba477fb14b67'
$packagePath = [string]::Concat([char]0x6700, [char]0x65B0, [char]0x6B63, [char]0x5F0F, [char]0x7248, '.zip')
$revisions = & git -C $repoRoot log '--format=%H%x09%cs%x09%s' $upstreamTip -- $packagePath
if ($LASTEXITCODE) { throw 'Cannot enumerate upstream package history.' }
$packages = [Collections.Generic.List[object]]::new()
$excludedPackages = [Collections.Generic.List[object]]::new()
$seen = @{}
foreach ($revision in $revisions) {
    $parts = $revision -split "`t", 3
    $commit = $parts[0]
    $blob = (& git -C $repoRoot rev-parse "${commit}:$packagePath").Trim()
    if ($LASTEXITCODE) { throw "Cannot resolve package in $commit" }
    if ($seen.ContainsKey($blob)) { continue }
    $seen[$blob] = $true
    if ($commit -in $ExcludedCommits) {
        $excludedPackages.Add([ordered]@{
            commit = $commit
            commitMessage = $parts[2]
            gitBlob = $blob
            reason = 'Windows security blocked access; owner requested source and upstream link only.'
            sourceUrl = "https://github.com/Meloong-Git/PCL/blob/$commit/$([Uri]::EscapeDataString($packagePath))"
        })
        Write-Output "Excluded blocked upstream package at $($commit.Substring(0, 8))."
        continue
    }
    $zipPath = Join-Path $OutputDirectory "PCL-upstream-$($commit.Substring(0, 12)).zip"
    if (-not (Test-Path -LiteralPath $zipPath)) {
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'git'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @('-C', $repoRoot, 'cat-file', 'blob', $blob)) { $startInfo.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::Start($startInfo)
        $errorText = $process.StandardError.ReadToEndAsync()
        $stream = [IO.File]::Create($zipPath)
        try { $process.StandardOutput.BaseStream.CopyTo($stream) } finally { $stream.Dispose() }
        $process.WaitForExit()
        if ($process.ExitCode) { throw "Package export failed: $($errorText.GetAwaiter().GetResult())" }
        $process.Dispose()
    }
    $actualBlob = (& git -C $repoRoot hash-object -- $zipPath).Trim()
    if ($actualBlob -ne $blob) { throw "Git blob mismatch: $zipPath" }
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $exeEntry = $archive.Entries | Where-Object { $_.FullName -match '(?i)\.exe$' } | Sort-Object Length -Descending | Select-Object -First 1
        if (-not $exeEntry) { throw "No executable in $zipPath" }
        $exePath = Join-Path $inspectionDirectory "$($commit.Substring(0, 12)).exe"
        [IO.Compression.ZipFileExtensions]::ExtractToFile($exeEntry, $exePath, $true)
        $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
        $version = $versionInfo.FileVersion
        $versionSource = 'Win32 file version'
        if (-not $version) {
            try {
                $version = [Reflection.AssemblyName]::GetAssemblyName($exePath).Version.ToString()
                $versionSource = 'CLR assembly version'
            } catch {
                $version = [regex]::Match($parts[2], '\d+\.\d+\.\d+(?:\.\d+)?').Value
                $versionSource = 'Upstream package-update commit title; binary has no readable version metadata'
            }
        }
        if (-not $version) { throw "Missing executable version in $zipPath" }
        $exeSha = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
    } finally { $archive.Dispose() }
    $packages.Add([ordered]@{
        version = $version
        versionSource = $versionSource
        commit = $commit
        commitDate = $parts[1]
        commitMessage = $parts[2]
        gitBlob = $blob
        file = (Split-Path $zipPath -Leaf)
        size = (Get-Item -LiteralPath $zipPath).Length
        sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        executable = $exeEntry.FullName
        executableSha256 = $exeSha
        sourceUrl = "https://github.com/Meloong-Git/PCL/blob/$commit/$([Uri]::EscapeDataString($packagePath))"
    })
    Write-Output "Verified upstream package $version ($($commit.Substring(0, 8)))"
}
$upstreamReleases = Get-Content -LiteralPath $ReleaseMetadata -Raw -Encoding utf8 | ConvertFrom-Json
$releaseIndex = foreach ($release in $upstreamReleases) {
    $tag = $release.tag_name
    $target = (& git -C $repoRoot rev-parse "refs/tags/$tag^{commit}").Trim()
    if ($LASTEXITCODE) { throw "Missing upstream tag: $tag" }
    $normalized = Get-NormalizedVersion $tag
    $matching = @($packages | Where-Object { (Get-NormalizedVersion $_.version) -eq $normalized })
    [ordered]@{
        tag = $tag
        name = $release.name
        commit = $target
        publishedAt = $release.published_at
        prerelease = $release.prerelease
        upstreamUrl = $release.html_url
        packages = @($matching | ForEach-Object { $_.file })
        binaryAvailable = ($matching.Count -gt 0)
    }
}
$index = [ordered]@{
    upstream = 'https://github.com/Meloong-Git/PCL'
    snapshotCommit = $upstreamTip
    releaseCount = @($releaseIndex).Count
    packageCount = $packages.Count
    excludedPackages = @($excludedPackages.ToArray())
    releases = @($releaseIndex)
    packages = @($packages.ToArray())
}
$indexPath = Join-Path $repoRoot 'docs/upstream-history.json'
$index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $indexPath -Encoding utf8NoBOM
$packages | ForEach-Object { '{0}  {1}' -f $_.sha256, $_.file } | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Encoding utf8NoBOM
Write-Output "Verified $($packages.Count) unique packages across $(@($releaseIndex).Count) upstream releases."
