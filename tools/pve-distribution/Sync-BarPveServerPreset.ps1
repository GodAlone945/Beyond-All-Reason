[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ServerRoot,
    [switch]$CheckOnly,
    [switch]$ActivateDefault
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($CheckOnly -and $ActivateDefault) { throw 'CheckOnly and ActivateDefault cannot be combined.' }

$root = [IO.Path]::GetFullPath($ServerRoot).TrimEnd('\')
$store = Join-Path $root 'pve-data'
$statePath = Join-Path $store 'state.json'
$spadsPath = Join-Path $root 'spads\etc\spads.conf'
$presetPath = Join-Path $root 'spads\etc\hostingPresets.conf'
foreach ($path in @($statePath, $spadsPath, $presetPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing: $path" }
}
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($state.schemaVersion -ne 1 -or $null -eq $state.active) { throw 'No active PVE version.' }
$entry = $state.active
if ($entry.version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?$' -or
    $entry.gameName -cne "BAR PVE $($entry.version)" -or
    $entry.fileName -cne "BAR-PVE-$($entry.version).sdz") {
    throw 'Invalid active PVE identity.'
}
$archivePath = Join-Path (Join-Path $store 'games') $entry.fileName
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "Missing archive: $archivePath" }
if ((Get-Item -LiteralPath $archivePath).Length -ne [int64]$entry.size) { throw 'PVE archive size mismatch.' }
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -cne [string]$entry.sha256) { throw 'PVE archive SHA-256 mismatch.' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $metadataEntry = $zip.GetEntry('modinfo.lua')
    if ($null -eq $metadataEntry) { throw 'PVE archive lacks modinfo.lua.' }
    $reader = [IO.StreamReader]::new($metadataEntry.Open())
    try { $metadata = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally { $zip.Dispose() }
if ($metadata -cnotmatch "(?m)^\s*name\s*=\s*'BAR PVE'" -or
    $metadata -cnotmatch "(?m)^\s*version\s*=\s*'$([regex]::Escape($entry.version))'") {
    throw 'PVE archive identity mismatch.'
}
$spadsText = [IO.File]::ReadAllText($spadsPath, [Text.Encoding]::ASCII)
$dataLines = @($spadsText -split '\r?\n' | Where-Object { $_ -like 'springDataDir:*' })
if ($dataLines.Count -ne 1) { throw 'Invalid SPADS data directory configuration.' }
$dataDirs = @($dataLines[0].Substring('springDataDir:'.Length).Split(';') | ForEach-Object {
    [IO.Path]::GetFullPath($_).TrimEnd('\')
})
if ($store -notin $dataDirs) { throw 'SPADS does not scan pve-data.' }
$presetText = [IO.File]::ReadAllText($presetPath, [Text.Encoding]::ASCII)
$section = [regex]::Match($presetText, '(?ms)^\[pve<default>\]\r?\n.*?(?=^\[|\z)')
if (-not $section.Success) { throw 'PVE hosting preset is missing.' }
$matches = [regex]::Matches($section.Value, '(?m)^modName:[^\r\n]*')
if ($matches.Count -ne 1) { throw 'PVE hosting preset has no unique modName.' }
$current = $matches[0].Value.Substring('modName:'.Length)
if ($CheckOnly) {
    if ($current -cne $entry.gameName) { throw "Preset mismatch: $current != $($entry.gameName)" }
    Write-Output "Verified: $($entry.gameName) SHA-256 $hash"
    exit 0
}
if (@(Get-Process -Name perl, spring, spring-headless -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Server or game process is running; stop it before changing the PVE preset.'
}
if ($current -cne $entry.gameName) {
    $updatedSection = $section.Value.Replace($matches[0].Value, "modName:$($entry.gameName)")
    $updatedText = $presetText.Substring(0, $section.Index) + $updatedSection +
        $presetText.Substring($section.Index + $section.Length)
    $temporary = "$presetPath.tmp-$PID"
    try {
        [IO.File]::WriteAllText($temporary, $updatedText, [Text.Encoding]::ASCII)
        [IO.File]::Replace($temporary, $presetPath,
            "$presetPath.pre-pve-$(Get-Date -Format 'yyyyMMdd-HHmmss')")
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
if ($ActivateDefault) {
    $defaultSection = [regex]::Match($spadsText, '(?ms)^\[default\]\r?\n.*?(?=^\[|\z)')
    if (-not $defaultSection.Success) { throw 'SPADS default section is missing.' }
    $defaultHosting = [regex]::Matches($defaultSection.Value, '(?m)^hostingPreset:[^\r\n]*')
    if ($defaultHosting.Count -ne 1) { throw 'SPADS default section has no unique hostingPreset.' }
    if ($defaultHosting[0].Value -cne 'hostingPreset:pve') {
        $updatedSection = $defaultSection.Value.Replace($defaultHosting[0].Value, 'hostingPreset:pve')
        $updatedText = $spadsText.Substring(0, $defaultSection.Index) + $updatedSection +
            $spadsText.Substring($defaultSection.Index + $defaultSection.Length)
        $temporary = "$spadsPath.tmp-$PID"
        try {
            [IO.File]::WriteAllText($temporary, $updatedText, [Text.Encoding]::ASCII)
            [IO.File]::Replace($temporary, $spadsPath,
                "$spadsPath.pre-pve-$(Get-Date -Format 'yyyyMMdd-HHmmss')")
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        }
    }
}
$status = [ordered]@{
    schemaVersion = 1
    channel = 'pve'
    version = [string]$entry.version
    gameName = [string]$entry.gameName
    sha256 = $hash
    engineVersion = [string]$entry.engineVersion
    manifestUrl = "https://github.com/GodAlone945/Beyond-All-Reason/releases/download/pve-v$($entry.version)/manifest.json"
}
$statusPath = Join-Path $store 'server-version.json'
$statusTemporary = "$statusPath.tmp-$PID"
try {
    [IO.File]::WriteAllText($statusTemporary, ($status | ConvertTo-Json -Depth 4),
        [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
        [IO.File]::Replace($statusTemporary, $statusPath, "$statusPath.bak")
    } else {
        [IO.File]::Move($statusTemporary, $statusPath)
    }
} finally {
    if (Test-Path -LiteralPath $statusTemporary) { Remove-Item -LiteralPath $statusTemporary -Force }
}
Write-Output "Server PVE preset: $($entry.gameName) SHA-256 $hash"
