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
$cachePath = Join-Path $OutputDirectory 'verification-cache.json'
$cache = @{}
if (Test-Path -LiteralPath $cachePath) {
    foreach ($entry in (Get-Content $cachePath -Raw -Encoding utf8 | ConvertFrom-Json)) { $cache[$entry.commit] = $entry }
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
    $sourceUrl = "https://github.com/Meloong-Git/PCL/blob/$commit/$([Uri]::EscapeDataString($packagePath))"
    if ($commit -in $ExcludedCommits) {
        $cache[$commit] = [ordered]@{commit=$commit;commitMessage=$parts[2];gitBlob=$blob;excluded=$true;reason='Windows security blocked access; owner requested source and upstream link only.';sourceUrl=$sourceUrl}
    }
    if ($cache.ContainsKey($commit) -and $cache[$commit].gitBlob -eq $blob) {
        if ($cache[$commit].excluded) { $excludedPackages.Add($cache[$commit]) } else { $packages.Add($cache[$commit]) }
        Write-Output "Reused verified history record $($commit.Substring(0, 8))."
        continue
    }
    try {
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
        $bytes = [IO.File]::ReadAllBytes($zipPath)
        $gitHasher = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA1)
        try {
            $gitHasher.AppendData([Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0"))
            $gitHasher.AppendData($bytes)
            $actualBlob = [Convert]::ToHexString($gitHasher.GetHashAndReset()).ToLowerInvariant()
        } finally { $gitHasher.Dispose() }
        if ($actualBlob -ne $blob) { throw "Git blob mismatch: $zipPath" }
        $zipSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        $archive = [IO.Compression.ZipArchive]::new([IO.MemoryStream]::new($bytes), [IO.Compression.ZipArchiveMode]::Read)
        try {
            $exeEntry = $archive.Entries | Where-Object { $_.FullName -match '(?i)\.exe$' } | Sort-Object Length -Descending | Select-Object -First 1
            if (-not $exeEntry) { throw "No executable in $zipPath" }
            $exeName = $exeEntry.FullName
            $exePath = Join-Path $inspectionDirectory "$($commit.Substring(0, 12)).exe"
            [IO.Compression.ZipFileExtensions]::ExtractToFile($exeEntry, $exePath, $true)
            $exeSha = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
            $version = $versionInfo.FileVersion
            $versionSource = 'Win32 file version'
            if (-not $version) {
                try {
                    $version = [Reflection.AssemblyName]::GetAssemblyName($exePath).Version.ToString()
                    $versionSource = 'CLR assembly version'
                } catch [BadImageFormatException] {
                    $version = [regex]::Match($parts[2], '\d+\.\d+\.\d+(?:\.\d+)?').Value
                    $versionSource = 'Upstream package-update commit title; binary has no readable version metadata'
                }
            }
            if (-not $version) { throw "Missing executable version in $zipPath" }
        } finally { $archive.Dispose() }
        $record = [ordered]@{
            version=$version;versionSource=$versionSource;commit=$commit;commitDate=$parts[1];commitMessage=$parts[2]
            gitBlob=$blob;file=(Split-Path $zipPath -Leaf);size=$bytes.Length;sha256=$zipSha
            executable=$exeName;executableSha256=$exeSha;sourceUrl=$sourceUrl
        }
        $packages.Add($record)
        $cache[$commit] = $record
        Write-Output "Verified upstream package $version ($($commit.Substring(0, 8)))"
    } catch {
        if ($_.Exception.ToString() -notmatch '(?i)virus|unwanted|病毒|垃圾软件|800700e1|800700e2') { throw }
        $record = [ordered]@{commit=$commit;commitMessage=$parts[2];gitBlob=$blob;excluded=$true;reason='Windows security blocked access; following owner-approved source-and-upstream-link-only handling.';sourceUrl=$sourceUrl}
        $excludedPackages.Add($record)
        $cache[$commit] = $record
        Write-Output "Excluded security-blocked upstream package $($commit.Substring(0, 8))."
    }
    @($cache.Values) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cachePath -Encoding utf8NoBOM
}
$upstreamReleases = Get-Content -LiteralPath $ReleaseMetadata -Raw -Encoding utf8 | ConvertFrom-Json
$releaseIndex = foreach ($release in $upstreamReleases) {
    $tag = $release.tag_name
    $target = (& git -C $repoRoot rev-parse "refs/tags/$tag^{commit}").Trim()
    if ($LASTEXITCODE) { throw "Missing upstream tag: $tag" }
    $normalized = Get-NormalizedVersion $tag
    $matching = @($packages | Where-Object { (Get-NormalizedVersion $_.version) -eq $normalized })
    $excluded = @($excludedPackages | Where-Object {
        $declaredVersion = [regex]::Match($_.commitMessage, '\d+\.\d+\.\d+(?:\.\d+)?').Value
        $declaredVersion -and (Get-NormalizedVersion $declaredVersion) -eq $normalized
    })
    [ordered]@{
        tag=$tag;name=$release.name;commit=$target;publishedAt=$release.published_at;prerelease=$release.prerelease
        upstreamUrl=$release.html_url;packages=@($matching | ForEach-Object { $_.file })
        binaryAvailable=($matching.Count -gt 0);excludedPackages=@($excluded)
    }
}
$index = [ordered]@{
    upstream='https://github.com/Meloong-Git/PCL';snapshotCommit=$upstreamTip
    releaseCount=@($releaseIndex).Count;packageCount=$packages.Count
    excludedPackages=@($excludedPackages.ToArray());releases=@($releaseIndex);packages=@($packages.ToArray())
}
$index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repoRoot 'docs/upstream-history.json') -Encoding utf8NoBOM
$packages | ForEach-Object { '{0}  {1}' -f $_.sha256, $_.file } | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Encoding utf8NoBOM
Write-Output "Verified $($packages.Count) packages; excluded $($excludedPackages.Count); indexed $(@($releaseIndex).Count) releases."
