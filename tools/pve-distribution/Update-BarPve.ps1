[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Install', 'Rollback', 'Status')][string]$Action,
    [Parameter(Mandatory = $true)][string]$StoreRoot,
    [string]$Manifest,
    [string]$Version,
    [switch]$AllowLocalManifest
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Store {
    $full = [IO.Path]::GetFullPath($StoreRoot).TrimEnd('\')
    $leaf = Split-Path -Leaf $full
    if ($leaf -notin @('bar-pve', 'pve-data')) { throw 'StoreRoot must end in bar-pve or pve-data.' }
    if (-not (Test-Path -LiteralPath $full)) { New-Item -ItemType Directory -Path $full -Force | Out-Null }
    return $full
}
function Assert-Idle {
    if (@(Get-Process -Name spring, spring-headless -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Recoil is running. Close the game before activating or rolling back a PVE version.'
    }
}
function Assert-Version([string]$value) {
    if ($value -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?$') {
        throw "Invalid PVE version: $value"
    }
}
function Get-State([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ schemaVersion = 1; active = $null; history = @() }
    }
    $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.schemaVersion -ne 1) { throw 'Unsupported local state schema.' }
    return $state
}
function Save-State([string]$path, [object]$state) {
    $temporary = "$path.tmp-$PID"
    $json = $state | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
    try {
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temporary, $path, "$path.bak") }
        else { [IO.File]::Move($temporary, $path) }
    }
    finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Assert-File([string]$path, [object]$entry) {
    if (-not [IO.File]::Exists($path)) { throw "Missing package: $path" }
    $size = (Get-Item -LiteralPath $path).Length
    if ($size -ne [int64]$entry.size) { throw "Package length mismatch: $path" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -cne [string]$entry.sha256) { throw "Package SHA-256 mismatch: $path" }
}
function Assert-Archive([string]$path, [string]$version) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $entry = $archive.GetEntry('modinfo.lua')
        if ($null -eq $entry) { throw 'PVE archive has no modinfo.lua.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $metadata = $reader.ReadToEnd() }
        finally { $reader.Dispose() }
        if ($metadata -cnotmatch "(?m)^\s*name\s*=\s*'BAR PVE'" -or
            $metadata -cnotmatch "(?m)^\s*version\s*=\s*'$([regex]::Escape($version))'") {
            throw 'PVE archive identity does not match the manifest.'
        }
    }
    finally { $archive.Dispose() }
}
function Assert-Manifest([object]$m) {
    if ($m.schemaVersion -ne 1 -or $m.channel -cne 'pve') { throw 'Invalid manifest schema or channel.' }
    Assert-Version ([string]$m.version)
    if ($m.gameName -cne "BAR PVE $($m.version)") { throw 'Manifest game name does not match PVE identity.' }
    if ($null -eq $m.package -or [string]$m.package.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid package digest.' }
    if ([int64]$m.package.size -lt 1) { throw 'Invalid package size.' }
    $expected = "BAR-PVE-$($m.version).sdz"
    if ($m.package.fileName -cne $expected) { throw 'Invalid PVE package filename.' }
    if ($null -eq $m.engine -or [string]::IsNullOrWhiteSpace([string]$m.engine.version)) {
        throw 'Required engine version is missing.'
    }
    if (-not $AllowLocalManifest) {
        $uri = [Uri]$m.package.url
        if ($uri.Scheme -cne 'https' -or $uri.Host -notin @('github.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com')) {
            throw 'Package URL must be an HTTPS GitHub Release asset.'
        }
    }
}
$root = Assert-Store
$games = Join-Path $root 'games'
$staging = Join-Path $root 'staging'
$statePath = Join-Path $root 'state.json'
$state = Get-State $statePath
if ($Action -eq 'Status') { $state | ConvertTo-Json -Depth 8; exit 0 }
Assert-Idle
New-Item -ItemType Directory -Path $games,$staging -Force | Out-Null

if ($Action -eq 'Install') {
    if ([string]::IsNullOrWhiteSpace($Manifest)) { throw 'Install requires -Manifest.' }
    if ($AllowLocalManifest) {
        $m = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        $manifestUri = [Uri]$Manifest
        if ($manifestUri.Scheme -cne 'https' -or $manifestUri.Host -cne 'github.com') {
            throw 'Manifest must be an HTTPS GitHub Release asset.'
        }
        $m = Invoke-RestMethod -Uri $manifestUri -UseBasicParsing
    }
    Assert-Manifest $m
    $destination = Join-Path $games $m.package.fileName
    $stagePath = Join-Path $staging ($m.package.fileName + ".part-$PID")
    try {
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            if ($AllowLocalManifest) { Copy-Item -LiteralPath $m.package.url -Destination $stagePath }
            else { Invoke-WebRequest -Uri $m.package.url -OutFile $stagePath -UseBasicParsing | Out-Null }
            Assert-File $stagePath $m.package
            Assert-Archive $stagePath $m.version
            [IO.File]::Move($stagePath, $destination)
        }
        Assert-File $destination $m.package
        Assert-Archive $destination $m.version
        $entry = [pscustomobject]@{
            version = [string]$m.version
            gameName = [string]$m.gameName
            fileName = [string]$m.package.fileName
            sha256 = [string]$m.package.sha256
            size = [int64]$m.package.size
            engineVersion = [string]$m.engine.version
        }
        $history = @($state.history | Where-Object { $_.version -cne $entry.version })
        if ($null -ne $state.active -and $state.active.version -cne $entry.version) {
            $history = @($state.active) + $history
        }
        Save-State $statePath ([pscustomobject]@{ schemaVersion = 1; active = $entry; history = $history })
        Write-Output "Active: $($entry.gameName)"
    }
    finally { if (Test-Path -LiteralPath $stagePath -PathType Leaf) { Remove-Item -LiteralPath $stagePath -Force } }
}
else {
    Assert-Version $Version
    $candidate = @($state.history | Where-Object { $_.version -ceq $Version }) | Select-Object -First 1
    if ($null -eq $candidate) { throw "No retained verified version: $Version" }
    $candidatePath = Join-Path $games $candidate.fileName
    Assert-File $candidatePath $candidate
    Assert-Archive $candidatePath $candidate.version
    $history = @($state.history | Where-Object { $_.version -cne $Version })
    if ($null -ne $state.active) { $history = @($state.active) + $history }
    Save-State $statePath ([pscustomobject]@{ schemaVersion = 1; active = $candidate; history = $history })
    Write-Output "Rolled back: $($candidate.gameName)"
}
