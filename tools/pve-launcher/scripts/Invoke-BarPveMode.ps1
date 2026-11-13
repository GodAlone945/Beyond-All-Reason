[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Status', 'PreparePve', 'RollbackPve', 'LaunchDev')][string]$Action,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [string]$StatusSource,
    [string]$DevSource,
    [string]$Version,
    [string]$DevEngineVersion = '2026.07.04',
    [switch]$Roguelike
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'BarClientConfig.ps1')

function Read-ServerStatus {
    if ([string]::IsNullOrWhiteSpace($StatusSource)) { throw 'PVE server status source is not configured.' }
    if ($StatusSource -match '^https://') {
        $status = Invoke-RestMethod -Uri $StatusSource -UseBasicParsing
    } elseif ([IO.Path]::IsPathRooted($StatusSource) -and
        (Split-Path -Leaf $StatusSource) -ceq 'server-version.json') {
        $status = Get-Content -LiteralPath $StatusSource -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        throw 'PVE status source must be HTTPS or a local server-version.json path.'
    }
    if ($status.schemaVersion -ne 1 -or $status.channel -cne 'pve' -or
        [string]$status.version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?$' -or
        $status.gameName -cne "BAR PVE $($status.version)" -or
        [string]$status.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace([string]$status.engineVersion)) {
        throw 'Server PVE status is invalid.'
    }
    $expectedUrl = "https://github.com/GodAlone945/Beyond-All-Reason/releases/download/pve-v$($status.version)/manifest.json"
    if ($status.manifestUrl -cne $expectedUrl) { throw 'Server manifest URL is not the pinned PVE release.' }
    return $status
}
function Get-LocalServerReadiness([object]$status) {
    if ($StatusSource -match '^https://') {
        return [pscustomobject]@{ ready = $true; reason = 'HTTPS server status accepted.' }
    }
    $statusPath = [IO.Path]::GetFullPath($StatusSource)
    $pveData = Split-Path -Parent $statusPath
    if ((Split-Path -Leaf $pveData) -ine 'pve-data') {
        return [pscustomobject]@{ ready = $true; reason = 'Local status fixture accepted.' }
    }
    $serverRoot = Split-Path -Parent $pveData
    $spadsConfig = Join-Path $serverRoot 'spads\etc\spads.conf'
    $presets = Join-Path $serverRoot 'spads\etc\hostingPresets.conf'
    $statePath = Join-Path $serverRoot 'state\server.json'
    if (-not (Test-Path -LiteralPath $spadsConfig -PathType Leaf) -or
        -not (Test-Path -LiteralPath $presets -PathType Leaf)) {
        return [pscustomobject]@{ ready = $false; reason = 'Local SPADS configuration is missing.' }
    }
    $configText = Get-Content -LiteralPath $spadsConfig -Raw -Encoding UTF8
    $presetText = Get-Content -LiteralPath $presets -Raw -Encoding UTF8
    $default = [regex]::Match($configText, '(?ms)^\[default\]\s*(?<body>.*?)(?=^\[|\z)')
    $pve = [regex]::Match($presetText, '(?ms)^\[pve<default>\]\s*(?<body>.*?)(?=^\[|\z)')
    if (-not $default.Success -or $default.Groups['body'].Value -notmatch '(?m)^hostingPreset:pve\s*$') {
        return [pscustomobject]@{ ready = $false; reason = 'SPADS 默认托管预设尚未切到 pve。请先在空房间切换并重启本地服务器。' }
    }
    if (-not $pve.Success -or $pve.Groups['body'].Value -notmatch ('(?m)^modName:' + [regex]::Escape([string]$status.gameName) + '\s*$')) {
        return [pscustomobject]@{ ready = $false; reason = 'SPADS pve 预设游戏名与服务器版本状态不一致。' }
    }
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return [pscustomobject]@{ ready = $false; reason = '本地 SPADS 服务器未启动。' }
    }
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $process = Get-Process -Id ([int]$state.Pid) -ErrorAction SilentlyContinue
    $expectedExecutable = Join-Path $serverRoot 'perl-portable\perl\bin\perl.exe'
    if (-not $process -or $process.Path -ine $expectedExecutable -or
        $process.StartTime.ToUniversalTime().Ticks -ne [int64]$state.StartTicksUtc) {
        return [pscustomobject]@{ ready = $false; reason = '本地 SPADS 进程未运行，服务器状态文件已过期。' }
    }
    $spadsLog = Join-Path $serverRoot 'spads\var\log\spads.log'
    if (-not (Test-Path -LiteralPath $spadsLog -PathType Leaf)) {
        return [pscustomobject]@{ ready = $false; reason = 'SPADS 托管日志尚未生成。' }
    }
    $hostingLines = [regex]::Matches((Get-Content -LiteralPath $spadsLog -Raw -Encoding UTF8),
        '(?m)^(?<stamp>[0-9]{14}) - .*?Hosting game "(?<game>[^"]+)" using engine version "(?<engine>[^"]+)"')
    $started = $process.StartTime.ToString('yyyyMMddHHmmss')
    $hosted = @($hostingLines | Where-Object { $_.Groups['stamp'].Value -ge $started } | Select-Object -Last 1)
    if ($hosted.Count -eq 0) {
        return [pscustomobject]@{ ready = $false; reason = 'SPADS 已运行，但 PVE 房间尚未托管成功。' }
    }
    if ($hosted[0].Groups['game'].Value -cne $status.gameName -or
        $hosted[0].Groups['engine'].Value -cne $status.engineVersion) {
        return [pscustomobject]@{ ready = $false; reason = '当前 SPADS 房间的游戏包或引擎与 PVE 服务器状态不一致。' }
    }
    return [pscustomobject]@{ ready = $true; reason = '本地 PVE 房间和服务器进程已就绪。' }
}
function Assert-ManifestMatches([object]$status, [object]$manifest) {
    $expectedPackage = "BAR-PVE-$($status.version).sdz"
    $expectedUrl = "https://github.com/GodAlone945/Beyond-All-Reason/releases/download/pve-v$($status.version)/$expectedPackage"
    if ($manifest.schemaVersion -ne 1 -or $manifest.channel -cne 'pve' -or
        $manifest.version -cne $status.version -or $manifest.gameName -cne $status.gameName -or
        $manifest.package.fileName -cne $expectedPackage -or
        $manifest.package.url -cne $expectedUrl -or
        $manifest.package.sha256 -cne $status.sha256 -or
        [int64]$manifest.package.size -lt 1 -or
        $manifest.engine.version -cne $status.engineVersion) {
        throw 'Server PVE version and GitHub release manifest differ.'
    }
}
function Assert-GameFile([string]$path, [object]$entry) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing PVE game file: $path" }
    if ((Get-Item -LiteralPath $path).Length -ne [int64]$entry.size) { throw 'PVE game file size mismatch.' }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$entry.sha256) {
        throw 'PVE game file SHA-256 mismatch.'
    }
}
function Assert-GameEntry([object]$entry) {
    if ($null -eq $entry -or
        [string]$entry.version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?$' -or
        $entry.gameName -cne "BAR PVE $($entry.version)" -or
        $entry.fileName -cne "BAR-PVE-$($entry.version).sdz" -or
        [string]$entry.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [int64]$entry.size -lt 1) {
        throw 'Invalid PVE game entry in local state.'
    }
}
function Add-ClientGameLink([string]$dataDirectory, [string]$store, [object]$entry) {
    Assert-GameEntry $entry
    $source = Join-Path (Join-Path $store 'games') $entry.fileName
    Assert-GameFile $source $entry
    $games = Join-Path $dataDirectory 'games'
    if (-not (Test-Path -LiteralPath $games -PathType Container)) { throw "BAR games directory is missing: $games" }
    $destination = Join-Path $games $entry.fileName
    $corruptBackup = $null
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        try {
            Assert-GameFile $destination $entry
            return $destination
        } catch {
            $corruptBackup = "$destination.corrupt-$PID"
            [IO.File]::Move($destination, $corruptBackup)
        }
    }
    try {
        try {
            New-Item -ItemType HardLink -Path $destination -Target $source -ErrorAction Stop | Out-Null
        } catch {
            $stage = "$destination.part-$PID"
            try {
                Copy-Item -LiteralPath $source -Destination $stage -ErrorAction Stop
                Assert-GameFile $stage $entry
                [IO.File]::Move($stage, $destination)
            } finally {
                if (Test-Path -LiteralPath $stage -PathType Leaf) { Remove-Item -LiteralPath $stage -Force }
            }
        }
        Assert-GameFile $destination $entry
        if ($null -ne $corruptBackup) { Remove-Item -LiteralPath $corruptBackup -Force }
        return $destination
    } catch {
        if ($null -ne $corruptBackup) {
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                Remove-Item -LiteralPath $destination -Force
            }
            [IO.File]::Move($corruptBackup, $destination)
        }
        throw
    }
}
function Get-StoreState([string]$store) {
    $path = Join-Path $store 'state.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ schemaVersion = 1; active = $null; history = @() }
    }
    $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.schemaVersion -ne 1) { throw 'PVE client state schema is invalid.' }
    return $state
}
function Assert-Engine([string]$dataDirectory, [string]$engineVersion, [string]$executable) {
    $engine = Join-Path $dataDirectory ("engine\recoil_$engineVersion\$executable")
    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
        throw "Required stock RecoilEngine $engineVersion is missing: $engine"
    }
    return $engine
}
function Ensure-Junction([string]$path, [string]$target) {
    $resolvedTarget = (Resolve-Path -LiteralPath $target).Path
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or
            [IO.Path]::GetFullPath([string]$item.Target).TrimEnd('\') -ine
            $resolvedTarget.TrimEnd('\')) {
            throw "Development junction points elsewhere: $path"
        }
    } else {
        New-Item -ItemType Junction -Path $path -Target $resolvedTarget -ErrorAction Stop | Out-Null
    }
}
function Launch-DevelopmentGame([string]$dataDirectory) {
    if ([string]::IsNullOrWhiteSpace($DevSource) -or -not (Test-Path -LiteralPath $DevSource -PathType Container)) {
        throw 'Select a local BAR-PVE source directory first.'
    }
    $source = (Resolve-Path -LiteralPath $DevSource).Path
    $modinfoPath = Join-Path $source 'modinfo.lua'
    if (-not (Test-Path -LiteralPath $modinfoPath -PathType Leaf)) { throw 'Development source lacks modinfo.lua.' }
    $modinfo = Get-Content -LiteralPath $modinfoPath -Raw -Encoding UTF8
    if ($modinfo -cnotmatch "(?m)^\s*name\s*=\s*'BAR PVE'" -or
        $modinfo -cnotmatch "(?m)^\s*version\s*=\s*'(?<version>[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?)'") {
        throw 'Development source has no independent BAR PVE identity.'
    }
    $gameName = "BAR PVE $($Matches.version)"
    $engine = Assert-Engine $dataDirectory $DevEngineVersion 'spring.exe'
    $map = Join-Path $dataDirectory 'maps\comet_catcher_remake_1.8.sd7'
    if (-not (Test-Path -LiteralPath $map -PathType Leaf)) { throw 'Comet Catcher Remake 1.8 map is missing.' }
    $devRoot = Join-Path $dataDirectory 'bar-pve-dev'
    $games = Join-Path $devRoot 'games'
    $run = Join-Path $devRoot 'run'
    New-Item -ItemType Directory -Path $games,$run -Force | Out-Null
    Ensure-Junction (Join-Path $games 'BAR-PVE.sdd') $source
    Ensure-Junction (Join-Path $devRoot 'maps') (Join-Path $dataDirectory 'maps')
    $startScript = Join-Path $run 'startscript.txt'
    $script = @"
[GAME]
{
  MapName=Comet Catcher Remake 1.8;
  GameType=$gameName;
  GameStartDelay=0;
  StartPosType=0;
  RecordDemo=0;
  MyPlayerName=PveDev;
  IsHost=1;
  [ALLYTEAM0] { NumAllies=0; }
  [TEAM0] { TeamLeader=0; AllyTeam=0; Side=Armada; }
  [PLAYER0] { Team=0; }
  [MODOPTIONS] { roguelike_mode=$([int][bool]$Roguelike); roguelike_weapon_effect_tests=0; }
}
"@
    [IO.File]::WriteAllText($startScript, $script, [Text.UTF8Encoding]::new($false))
    $previousDataDir = $env:SPRING_DATADIR
    try {
        $env:SPRING_DATADIR = $devRoot
        $arguments = @('--isolation', '--write-dir', ('"' + $run + '"'), ('"' + $startScript + '"'))
        $process = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $engine) -PassThru
        Wait-Process -Id $process.Id
    } finally {
        if ($null -eq $previousDataDir) { Remove-Item Env:SPRING_DATADIR -ErrorAction SilentlyContinue }
        else { $env:SPRING_DATADIR = $previousDataDir }
    }
    return [pscustomobject]@{ mode = 'development'; roguelike = [bool]$Roguelike; gameName = $gameName; source = $source }
}

$resolvedConfig = Assert-BarClientConfigPath -ConfigPath $ConfigPath
$data = Split-Path -Parent $resolvedConfig
$dataDrive = [IO.Path]::GetPathRoot($data)
if ($dataDrive -ieq 'C:\') {
    throw "PVE 游戏文件不能写入 C 盘。请先把 BAR 安装到其他盘，再选择该安装目录 data 下的 chobby_config.json：$resolvedConfig"
}
$installRoot = Split-Path -Parent $data
$launcherFiles = @('Beyond-All-Reason.exe', 'bar-launcher.exe', 'spring-launcher.exe')
if (-not @($launcherFiles | Where-Object { Test-Path -LiteralPath (Join-Path $installRoot $_) -PathType Leaf }).Count) {
    throw "所选配置不在 BAR 安装目录的 data 文件夹中。请选中与 BAR 启动程序同一安装目录下的 chobby_config.json：$resolvedConfig"
}
$store = Join-Path $data 'bar-pve'
# A local SPADS room can host the BAR-PVE.sdd worktree while release state remains pinned to an older archive.
if ($Action -in @('Status', 'PreparePve') -and
    -not [string]::IsNullOrWhiteSpace($DevSource) -and
    -not [string]::IsNullOrWhiteSpace($StatusSource) -and
    $StatusSource -notmatch '^https://' -and
    (Split-Path -Leaf $StatusSource) -ceq 'server-version.json' -and
    (Test-Path -LiteralPath $DevSource -PathType Container)) {
    $source = (Resolve-Path -LiteralPath $DevSource).Path
    $metadata = Get-Content -LiteralPath (Join-Path $source 'modinfo.lua') -Raw -Encoding UTF8
    $versionMatch = [regex]::Match($metadata, "(?m)^\s*version\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?)'")
    if ($metadata -match "(?m)^\s*name\s*=\s*'BAR PVE'" -and $versionMatch.Success) {
        $version = $versionMatch.Groups[1].Value
        $gameName = "BAR PVE $version"
        $pveData = Split-Path -Parent ([IO.Path]::GetFullPath($StatusSource))
        if ((Split-Path -Leaf $pveData) -ieq 'pve-data') {
            $presetPath = Join-Path (Split-Path -Parent $pveData) 'spads\etc\hostingPresets.conf'
            $presetText = Get-Content -LiteralPath $presetPath -Raw -Encoding UTF8
            $pvePreset = [regex]::Match($presetText, '(?ms)^\[pve<default>\]\s*(?<body>.*?)(?=^\[|\z)')
            if ($pvePreset.Success -and
                $pvePreset.Groups['body'].Value -match ('(?m)^modName:' + [regex]::Escape($gameName) + '\s*$')) {
                $devServer = [pscustomobject]@{
                    schemaVersion = 1
                    channel = 'pve-development'
                    version = $version
                    gameName = $gameName
                    engineVersion = $DevEngineVersion
                    source = $source
                }
                $readiness = Get-LocalServerReadiness $devServer
                $serverLink = Join-Path $pveData 'games\BAR-PVE.sdd'
                $clientLink = Join-Path $data 'games\BAR-PVE.sdd'
                $serverItem = Get-Item -LiteralPath $serverLink -Force -ErrorAction SilentlyContinue
                $serverLinkReady = $null -ne $serverItem -and $serverItem.LinkType -eq 'Junction' -and
                    [IO.Path]::GetFullPath([string](@($serverItem.Target)[0])).TrimEnd('\') -ieq $source.TrimEnd('\')
                if ($readiness.ready -and -not $serverLinkReady) {
                    $readiness = [pscustomobject]@{ ready = $false; reason = 'SPADS 的 BAR-PVE.sdd 未指向开发源码。' }
                }
                $clientItem = Get-Item -LiteralPath $clientLink -Force -ErrorAction SilentlyContinue
                $clientLinkReady = $null -ne $clientItem -and $clientItem.LinkType -eq 'Junction' -and
                    [IO.Path]::GetFullPath([string](@($clientItem.Target)[0])).TrimEnd('\') -ieq $source.TrimEnd('\')
                if ($Action -eq 'Status') {
                    if ($readiness.ready -and -not $clientLinkReady) {
                        $readiness = [pscustomobject]@{ ready = $false; reason = '客户端 BAR-PVE.sdd 未指向开发源码。' }
                    }
                    $active = if ($clientLinkReady) { $devServer } else { $null }
                    [pscustomobject]@{
                        server = $devServer
                        ready = $readiness.ready
                        reason = $readiness.reason
                        active = $active
                        history = @()
                    } | ConvertTo-Json -Depth 8 -Compress
                    exit 0
                }
                Assert-BarClientStopped -DataDirectory $data
                if (-not $readiness.ready) { throw $readiness.reason }
                $null = Assert-Engine $data $DevEngineVersion 'spring.exe'
                Ensure-Junction $clientLink $source
                [pscustomobject]@{ mode = 'pve-development'; active = $devServer; gameFile = $clientLink } |
                    ConvertTo-Json -Depth 5 -Compress
                exit 0
            }
        }
    }
}
if ($Action -eq 'Status') {
    $server = Read-ServerStatus
    $readiness = Get-LocalServerReadiness $server
    $state = Get-StoreState $store
    [pscustomobject]@{ server = $server; ready = $readiness.ready; reason = $readiness.reason; active = $state.active; history = @($state.history) } |
        ConvertTo-Json -Depth 8 -Compress
    exit 0
}
Assert-BarClientStopped -DataDirectory $data
if ($Action -eq 'LaunchDev') {
    Launch-DevelopmentGame $data | ConvertTo-Json -Depth 4 -Compress
    exit 0
}
$updater = Join-Path $PSScriptRoot 'pve-distribution\Update-BarPve.ps1'
if (-not (Test-Path -LiteralPath $updater -PathType Leaf)) { throw "Missing PVE updater: $updater" }
if ($Action -eq 'RollbackPve') {
    if ([string]::IsNullOrWhiteSpace($Version)) { throw 'Choose a historical PVE version.' }
    $previous = (Get-StoreState $store).active
    try {
        & $updater -Action Rollback -StoreRoot $store -Version $Version | Out-Null
        $state = Get-StoreState $store
        $link = Add-ClientGameLink $data $store $state.active
        [pscustomobject]@{ mode = 'pve'; active = $state.active; gameFile = $link } | ConvertTo-Json -Depth 5 -Compress
    } catch {
        if ($null -ne $previous) {
            $current = (Get-StoreState $store).active
            if ($null -ne $current -and $current.version -cne $previous.version) {
                & $updater -Action Rollback -StoreRoot $store -Version $previous.version | Out-Null
            }
        }
        throw
    }
    exit 0
}
$server = Read-ServerStatus
$readiness = Get-LocalServerReadiness $server
if (-not $readiness.ready) { throw $readiness.reason }
$manifest = Invoke-RestMethod -Uri $server.manifestUrl -UseBasicParsing
Assert-ManifestMatches $server $manifest
$null = Assert-Engine $data $server.engineVersion 'spring.exe'
$previous = (Get-StoreState $store).active
try {
    & $updater -Action Install -StoreRoot $store -Manifest $server.manifestUrl | Out-Null
    Assert-BarClientStopped -DataDirectory $data
    $state = Get-StoreState $store
    if ($state.active.gameName -cne $server.gameName -or $state.active.sha256 -cne $server.sha256) {
        throw 'Installed PVE state does not match the server.'
    }
    $link = Add-ClientGameLink $data $store $state.active
    [pscustomobject]@{ mode = 'pve'; active = $state.active; gameFile = $link } | ConvertTo-Json -Depth 5 -Compress
} catch {
    if ($null -ne $previous) {
        $current = (Get-StoreState $store).active
        if ($null -ne $current -and $current.version -cne $previous.version) {
            & $updater -Action Rollback -StoreRoot $store -Version $previous.version | Out-Null
        }
    }
    throw
}
