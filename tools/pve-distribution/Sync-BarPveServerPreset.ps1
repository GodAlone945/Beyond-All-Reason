[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ServerRoot,
    [switch]$CheckOnly,
    [switch]$ActivateDefault,
    [switch]$PublishStatus,
    [string]$GitRepository
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($CheckOnly -and $ActivateDefault) { throw 'CheckOnly and ActivateDefault cannot be combined.' }
if ($CheckOnly -and $PublishStatus) { throw 'CheckOnly and PublishStatus cannot be combined.' }

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
if ($PublishStatus -and ($current -cne $entry.gameName -or $ActivateDefault)) {
    throw 'Stop SPADS and synchronize its PVE preset before publishing server status.'
}
if ($PublishStatus) {
    $defaultSectionForPublish = [regex]::Match($spadsText, '(?ms)^\[default\]\r?\n.*?(?=^\[|\z)')
    if (-not $defaultSectionForPublish.Success -or
        $defaultSectionForPublish.Groups[0].Value -notmatch '(?m)^hostingPreset:pve\s*$') {
        throw 'The SPADS default hosting preset is not pve; refusing to publish online status.'
    }
}
$serverProcesses = @(Get-Process -Name perl, spring, spring-headless, spring-dedicated -ErrorAction SilentlyContinue)
if ($serverProcesses.Count -gt 0 -and -not $PublishStatus) {
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
if ($PublishStatus) {
    if ([string]::IsNullOrWhiteSpace($GitRepository)) {
        $GitRepository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    }
    $serverStatePath = Join-Path $root 'state\server.json'
    if (-not (Test-Path -LiteralPath $serverStatePath -PathType Leaf)) {
        throw 'SPADS is not running; refusing to publish online status.'
    }
    $serverState = Get-Content -LiteralPath $serverStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $spadsProcess = Get-Process -Id ([int]$serverState.Pid) -ErrorAction SilentlyContinue
    $expectedPerl = Join-Path $root 'perl-portable\perl\bin\perl.exe'
    if (-not $spadsProcess -or $spadsProcess.Path -ine $expectedPerl -or
        $spadsProcess.StartTime.ToUniversalTime().Ticks -ne [int64]$serverState.StartTicksUtc) {
        throw 'SPADS process state is stale; refusing to publish online status.'
    }
    $spadsLog = Join-Path $root 'spads\var\log\spads.log'
    if (-not (Test-Path -LiteralPath $spadsLog -PathType Leaf)) { throw 'SPADS hosting log is missing.' }
    $hostingLines = [regex]::Matches((Get-Content -LiteralPath $spadsLog -Raw -Encoding UTF8),
        '(?m)^(?<stamp>[0-9]{14}) - .*?Hosting game "(?<game>[^"]+)" using engine version "(?<engine>[^"]+)"')
    $started = $spadsProcess.StartTime.ToString('yyyyMMddHHmmss')
    $hosted = @($hostingLines | Where-Object { $_.Groups['stamp'].Value -ge $started } | Select-Object -Last 1)
    if ($hosted.Count -eq 0 -or $hosted[0].Groups['game'].Value -cne $entry.gameName -or
        $hosted[0].Groups['engine'].Value -cne $entry.engineVersion) {
        throw 'SPADS is not hosting the active PVE version and engine; refusing to publish online status.'
    }
    $GitRepository = (Resolve-Path -LiteralPath $GitRepository).Path
    $GitRepository = [IO.Path]::GetFullPath($GitRepository).TrimEnd('\')
    $repoRootOutput = (& git -C $GitRepository rev-parse --show-toplevel 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "GitRepository is invalid: $repoRootOutput" }
    $repoRoot = [IO.Path]::GetFullPath($repoRootOutput).TrimEnd('\')
    if ($LASTEXITCODE -ne 0 -or $repoRoot -ine $GitRepository) { throw 'GitRepository must be the BAR-PVE repository root.' }
    $branch = (& git -C $GitRepository branch --show-current 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $branch -cne 'pve/main') { throw 'PublishStatus requires the pve/main branch.' }
    $staged = & git -C $GitRepository diff --cached --name-only 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect Git index: $staged" }
    if (@($staged | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw 'Git index has staged changes; commit or unstage them before publishing status.'
    }
    $localChanges = & git -C $GitRepository status --porcelain -- status/server-version.json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect status file: $localChanges" }
    if (@($localChanges | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw 'status/server-version.json has local changes; inspect them before publishing.'
    }
    & git -C $GitRepository fetch origin pve/main
    if ($LASTEXITCODE -ne 0) { throw 'Unable to fetch origin/pve/main before publishing status.' }
    $divergence = (& git -C $GitRepository rev-list --left-right --count origin/pve/main...HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $divergence -cne "0`t0") {
        throw "Local pve/main must match origin/pve/main before publishing; divergence: $divergence"
    }
    $publicPath = Join-Path $GitRepository 'status\server-version.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $publicPath) -Force | Out-Null
    $publicTemporary = "$publicPath.tmp-$PID"
    try {
        [IO.File]::WriteAllText($publicTemporary, ($status | ConvertTo-Json -Depth 4),
            [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $publicPath -PathType Leaf) {
            [IO.File]::Replace($publicTemporary, $publicPath, "$publicPath.bak")
        } else {
            [IO.File]::Move($publicTemporary, $publicPath)
        }
    } finally {
        if (Test-Path -LiteralPath $publicTemporary) { Remove-Item -LiteralPath $publicTemporary -Force }
    }
    $publicStatusUrl = 'https://raw.githubusercontent.com/GodAlone945/Beyond-All-Reason/pve/main/status/server-version.json'
    $publicJson = Get-Content -LiteralPath $publicPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $serverJson = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($publicJson.version -cne $serverJson.version -or $publicJson.sha256 -cne $serverJson.sha256) {
        throw 'Public PVE status differs from the local server status.'
    }
    $publicChanges = & git -C $GitRepository status --porcelain -- status/server-version.json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect public PVE status: $publicChanges" }
    if (@($publicChanges | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        & git -C $GitRepository add -- status/server-version.json
        if ($LASTEXITCODE -ne 0) { throw 'Unable to stage public PVE status.' }
        & git -C $GitRepository -c user.name='BAR PVE Status' -c user.email='bar-pve-status@localhost' commit -m "Publish BAR PVE server status $($entry.version)"
        if ($LASTEXITCODE -ne 0) { throw 'Unable to commit public PVE status.' }
    }
    & git -C $GitRepository push origin pve/main
    if ($LASTEXITCODE -ne 0) { throw 'Unable to push public PVE status to origin/pve/main.' }
    Write-Output "Public PVE status: $publicStatusUrl"
}
