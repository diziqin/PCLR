[CmdletBinding()]
param(
    [string]$Repository = 'diziqin/PCLR',
    [string]$PackageDirectory,
    [string]$GitHubCli = 'gh'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $PackageDirectory) { $PackageDirectory = Join-Path $repoRoot 'artifacts/upstream' }
$index = Get-Content (Join-Path $repoRoot 'docs/upstream-history.json') -Raw -Encoding utf8 | ConvertFrom-Json
$requestPath = Join-Path $PackageDirectory 'release-request.json'
$progressPath = Join-Path $PackageDirectory 'published.json'
$published = [Collections.Generic.List[object]]::new()
foreach ($release in ($index.releases | Sort-Object publishedAt)) {
    $tag = $release.tag
    $body = @"
这是龙腾猫跃发布的 **PCL $tag 上游原版历史归档**，不包含 PCLR 的修改。

- [上游原始发行说明]($($release.upstreamUrl))
- [对应上游提交](https://github.com/Meloong-Git/PCL/commit/$($release.commit))
- 原始发布日期（UTC）：$($release.publishedAt)
- [支持原作者](https://meloong.com/afd/a/LTCat)
- [PCLR 当前修复版](https://github.com/$Repository/releases/latest)

"@
    if ($release.excludedPackages.Count -gt 0) {
        $body += "`n以下历史包变体被本机 Windows 安全软件拦截，按维护者选择的处理原则不单独重新上传；保留源码记录与上游链接，不对这些文件的安全性作结论。`n"
        foreach ($excluded in $release.excludedPackages) { $body += "`n[$($excluded.commitMessage)]($($excluded.sourceUrl))`n" }
    }
    if ($release.binaryAvailable) {
        $body += "`n附件为上游原样压缩包，保留原有程序与签名；可用 docs/upstream-history.json 中的 Git blob 与 SHA-256 核验。`n"
    } elseif ($release.excludedPackages.Count -eq 0) {
        $body += "`n上游仓库没有公开此版本对应的二进制包，本条保留真实源码发行记录，不使用其他版本程序冒充。GitHub 自动生成的源码归档不包含子模块内容。`n"
    }
    $body += "`n历史原版可能仍会自动更新到上游版本，且可能无法适配当前服务。日常使用请选择 PCLR 当前修复版。许可与第三方声明以对应上游版本为准。"
    $existingText = & $GitHubCli api "repos/$Repository/releases/tags/$tag" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $remoteRelease = $existingText | ConvertFrom-Json
        if ($remoteRelease.name -ne "上游归档 PCL $tag") { throw "An unrelated release already uses tag $tag." }
    } else {
        [ordered]@{
            tag_name = $tag
            target_commitish = $release.commit
            name = "上游归档 PCL $tag"
            body = $body
            draft = $false
            prerelease = [bool]$release.prerelease
            make_latest = 'false'
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $requestPath -Encoding utf8NoBOM
        $createdText = & $GitHubCli api --method POST "repos/$Repository/releases" --input $requestPath
        if ($LASTEXITCODE) { throw "Creating upstream release $tag failed." }
        $remoteRelease = $createdText | ConvertFrom-Json
    }
    foreach ($file in $release.packages) {
        $localFile = Join-Path $PackageDirectory $file
        $metadata = $index.packages | Where-Object file -eq $file | Select-Object -First 1
        if (-not (Test-Path -LiteralPath $localFile)) { throw "Missing package $file" }
        $hash = (Get-FileHash -LiteralPath $localFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $metadata.sha256) { throw "Local checksum mismatch for $file" }
        if (-not ($remoteRelease.assets | Where-Object name -eq $file)) {
            & $GitHubCli release upload $tag $localFile --repo $Repository
            if ($LASTEXITCODE) { throw "Uploading package $file failed." }
        }
    }
    $verifiedText = & $GitHubCli api "repos/$Repository/releases/$($remoteRelease.id)"
    if ($LASTEXITCODE) { throw "Cannot verify release $tag" }
    $verified = $verifiedText | ConvertFrom-Json
    foreach ($file in $release.packages) {
        $asset = $verified.assets | Where-Object name -eq $file | Select-Object -First 1
        $metadata = $index.packages | Where-Object file -eq $file | Select-Object -First 1
        if (-not $asset -or $asset.size -ne $metadata.size) { throw "Uploaded package size mismatch for $file" }
        if ($asset.digest -and $asset.digest -ne "sha256:$($metadata.sha256)") { throw "Uploaded package checksum mismatch for $file" }
    }
    $published.Add([ordered]@{tag=$tag;id=$verified.id;url=$verified.html_url;assets=@($verified.assets | Select-Object name,size,digest)})
    $published.ToArray() | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $progressPath -Encoding utf8NoBOM
    Write-Output "Published upstream $tag ($($release.packages.Count) package(s)); $($published.Count)/$($index.releaseCount)"
    Start-Sleep -Milliseconds 850
}
Write-Output "Published and verified $($published.Count) upstream historical releases."
