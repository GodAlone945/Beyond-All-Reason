[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackageDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$packageRoot = [IO.Path]::GetFullPath($PackageDirectory)
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if ($packageRoot.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
    $outputRoot.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
    $packageRoot.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $outputRoot.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Friend launcher build and package output must stay outside the source tree.'
}
$modinfo = Get-Content -LiteralPath (Join-Path $repo 'modinfo.lua') -Raw -Encoding UTF8
$version = [regex]::Match($modinfo, "(?m)^\s*version\s*=\s*'([^']+)'").Groups[1].Value
if ($version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?$') {
    throw 'Cannot determine BAR PVE package version.'
}
if (Test-Path -LiteralPath $packageRoot) { throw "Build directory already exists: $packageRoot" }
New-Item -ItemType Directory -Path $packageRoot,$outputRoot -Force | Out-Null
$archivePath = $null
try {
    & (Join-Path $repo 'tools\pve-launcher\Build.ps1') -OutputDirectory $packageRoot
    if ($LASTEXITCODE -ne 0) { throw 'Launcher build failed.' }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'server.friend.example.json') -Destination (Join-Path $packageRoot 'server.json')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.friend.txt') -Destination (Join-Path $packageRoot 'README.txt')
    $archivePath = Join-Path $outputRoot "BAR-PVE-Friend-Launcher-$version.zip"
    if (Test-Path -LiteralPath $archivePath) { throw "Friend launcher package already exists: $archivePath" }
    [IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $archivePath,
        [IO.Compression.CompressionLevel]::Optimal, $false)
    Write-Output "Friend launcher package: $archivePath"
} catch {
    if (Test-Path -LiteralPath $packageRoot) { Remove-Item -LiteralPath $packageRoot -Recurse -Force }
    if ($archivePath -and (Test-Path -LiteralPath $archivePath -PathType Leaf)) { Remove-Item -LiteralPath $archivePath -Force }
    throw
}
