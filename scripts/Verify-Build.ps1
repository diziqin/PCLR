[CmdletBinding()]
param([Parameter(Mandatory)][string]$Executable, [Parameter(Mandatory)][string]$ExpectedVersion)
$ErrorActionPreference = 'Stop'
$resolvedExe = (Resolve-Path -LiteralPath $Executable).Path
$versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($resolvedExe)
if ($versionInfo.FileVersion -ne $ExpectedVersion) { throw "Incorrect binary version: $($versionInfo.FileVersion)" }
if ($versionInfo.ProductName -ne 'Plain Craft Launcher (PCL) PCLR') { throw 'The binary does not identify itself as PCLR.' }
# Inspect literal constants in the actual compiled .NET Framework executable.
# Windows PowerShell supplies the .NET Framework reflection environment.
$inspection = @'
param([string]$Path)
$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile($Path)
$embeddedLibraries = @{}
foreach ($resourceName in $assembly.GetManifestResourceNames()) {
    if (-not $resourceName.EndsWith('.resources')) { continue }
    $reader = [Resources.ResourceReader]::new($assembly.GetManifestResourceStream($resourceName))
    try {
        $entries = $reader.GetEnumerator()
        while ($entries.MoveNext()) {
            if ($entries.Value -is [byte[]]) { $embeddedLibraries[$entries.Key] = $entries.Value }
        }
    } finally { $reader.Dispose() }
}
$resolver = [ResolveEventHandler]{
    param($Sender, $EventArgs)
    $shortName = [Reflection.AssemblyName]::new($EventArgs.Name).Name
    if ($embeddedLibraries.ContainsKey($shortName)) { return [Reflection.Assembly]::Load($embeddedLibraries[$shortName]) }
    return $null
}.GetNewClosure()
[AppDomain]::CurrentDomain.add_AssemblyResolve($resolver)
$flags = [Reflection.BindingFlags]'Public,NonPublic,Static'
$secret = $assembly.GetType('PCL.ModSecret', $true)
if ($secret.GetField('RestrictMcDownload', $flags).GetRawConstantValue() -ne $false) { throw 'Minecraft download is disabled in the binary.' }
if ($secret.GetField('VersionBranchMain', $flags).GetRawConstantValue() -ne 'PCLR') { throw 'Incorrect downstream identity.' }
$name = $assembly.GetType('PCL.ModBase', $true).GetField('LauncherName', $flags).GetRawConstantValue()
if ($name -ne 'Plain Craft Launcher (PCL) PCLR') { throw 'Incorrect launcher name.' }
Write-Output 'Compiled PCLR identity and download switch verified.'
'@
$checkPath = Join-Path ([IO.Path]::GetTempPath()) ('pclr-check-' + [guid]::NewGuid().ToString('N') + '.ps1')
try {
    [IO.File]::WriteAllText($checkPath, $inspection, [Text.UTF8Encoding]::new($false))
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $checkPath -Path $resolvedExe
    if ($LASTEXITCODE) { throw 'Compiled binary verification failed.' }
} finally {
    if (Test-Path -LiteralPath $checkPath) { Remove-Item -LiteralPath $checkPath }
}
