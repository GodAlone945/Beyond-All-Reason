[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$ReleaseBaseUrl,
    [Parameter(Mandatory = $true)][string]$EngineVersion
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$modinfo = Get-Content -LiteralPath (Join-Path $source 'modinfo.lua') -Raw -Encoding UTF8
$name = [regex]::Match($modinfo, "(?m)^\s*name\s*=\s*'([^']+)'").Groups[1].Value
$version = [regex]::Match($modinfo, "(?m)^\s*version\s*=\s*'([^']+)'").Groups[1].Value
if ($name -cne 'BAR PVE' -or $version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?$') {
    throw 'modinfo.lua must name BAR PVE and contain a concrete release version.'
}
if (-not (Get-ChildItem -LiteralPath (Join-Path $source 'recoil-lua-library') -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    throw 'recoil-lua-library submodule is empty. Initialize and pin it before packaging.'
}
$uri = [Uri]$ReleaseBaseUrl
if ($uri.Scheme -cne 'https' -or $uri.Host -cne 'github.com') {
    throw 'ReleaseBaseUrl must be an HTTPS GitHub Release download directory.'
}
$out = [IO.Path]::GetFullPath($OutputDirectory)
if ($out.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must be outside the game source tree.'
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
$fileName = "BAR-PVE-$version.sdz"
$archivePath = Join-Path $out $fileName
$manifestPath = Join-Path $out 'manifest.json'
if (Test-Path -LiteralPath $archivePath -PathType Leaf) { throw "Immutable release asset already exists: $archivePath" }
$excluded = @('.git', '.github', '.vscode', '.codex', 'docs', 'doc', 'tools', 'spec', '.lux')
$files = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force | Where-Object {
    $relative = $_.FullName.Substring($source.Length + 1)
    $first = ($relative -split '[\\/]')[0]
    $first -notin $excluded -and -not $first.StartsWith('.') -and
    $relative -notmatch '(^|[\\/])\.git([\\/]|$)'
} | Sort-Object { $_.FullName.Substring($source.Length + 1) })
if ($files.Count -lt 1000) { throw 'Source tree is incomplete; refusing to package.' }
$zip = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($source.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $file.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal)
    }
}
catch {
    $zip.Dispose()
    Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
    throw
}
finally { $zip.Dispose() }
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $archivePath).Length
$manifest = [ordered]@{
    schemaVersion = 1
    channel = 'pve'
    version = $version
    gameName = "BAR PVE $version"
    package = [ordered]@{
        fileName = $fileName
        url = ($ReleaseBaseUrl.TrimEnd('/') + '/' + $fileName)
        sha256 = $hash
        size = $size
    }
    engine = [ordered]@{ version = $EngineVersion }
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6),
    [Text.UTF8Encoding]::new($false))
Write-Output "Package: $archivePath"
Write-Output "Manifest: $manifestPath"
Write-Output "SHA-256: $hash"
Write-Output 'Run unitsync and a server/client smoke test before uploading immutable assets.'
