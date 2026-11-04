[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$ServerRoot = 'D:\BeyondAllReason\BAR-Server',
    [string]$ClientData = 'D:\BeyondAllReason\Beyond-All-Reason\data'
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..'
}
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
function Read-OptionalText([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return [IO.File]::ReadAllText($Path) }
    return ''
}
function Get-SourceLink([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $target = if ($item -and $item.LinkType -eq 'Junction') { [string](@($item.Target)[0]) } else { $null }
    [pscustomobject]@{
        path = $Path; target = $target
        matchesSource = [bool]($target -and [IO.Path]::GetFullPath($target).TrimEnd('\') -ieq $source.TrimEnd('\'))
    }
}
$metadata = Read-OptionalText (Join-Path $source 'modinfo.lua')
$version = [regex]::Match($metadata, "(?m)^\s*version\s*=\s*'([^']+)'").Groups[1].Value
$presetText = Read-OptionalText (Join-Path $ServerRoot 'spads\etc\hostingPresets.conf')
$preset = [regex]::Match($presetText, '(?ms)^\[pve<default>\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
$roomGame = [regex]::Match($preset, '(?m)^modName:([^\r\n]+)').Groups[1].Value.Trim()
$releasePath = Join-Path $ServerRoot 'pve-data\server-version.json'
$releaseText = Read-OptionalText $releasePath
$release = if ($releaseText) { $releaseText | ConvertFrom-Json } else { $null }
$startPath = Join-Path $ServerRoot 'spads\var\startscript.txt'
$startText = Read-OptionalText $startPath
$options = [ordered]@{}
foreach ($key in @('roguelike_mode','roguelike_coop','roguelike_weapon_effect_tests','startpostype','numplayers','gametype')) {
    $match = [regex]::Match($startText, '(?im)^\s*' + [regex]::Escape($key) + '\s*=\s*([^;\r\n]+)')
    $options[$key] = if ($match.Success) { $match.Groups[1].Value.Trim() } else { $null }
}
# Only feature files and named integration points: this is NOT an archive/engine checksum.
$paths = @('modinfo.lua','modoptions.lua','gamedata/alldefs_post.lua','modules/customcommands.lua',
    'luaui/rml_setup.lua','luaui/Widgets/gui_buildmenu.lua','luarules/gadgets/unit_aa_targeting_priority.lua',
    'luarules/gadgets/unit_lightning_splash_dmg.lua','scripts/Units/armcom_lus.lua',
    'scripts/Units/corcom_roguelike.cob','scripts/Units/legcom_roguelike.cob',
    'language/en/interface.json','language/en/commands.json','language/zh/commands.json',
    'luarules/gadgets/raptor_spawner_defense.lua','luarules/gadgets/scav_spawner_defense.lua',
    'tools/pve-launcher/Program.cs','tools/pve-launcher/scripts/Invoke-BarPveMode.ps1')
foreach ($folder in @('luarules/gadgets','unitbasedefs','weapons','effects','features')) {
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $source $folder) -File |
        Where-Object { $_.Name -like '*roguelike*.lua' } | ForEach-Object { $folder + '/' + $_.Name })
}
foreach ($folder in @('units/RoguelikeDrones','luaui/RmlWidgets/gui_roguelike')) {
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $source $folder) -File |
        Where-Object { $_.Extension -in @('.lua','.rml','.rcss') } | ForEach-Object { $folder + '/' + $_.Name })
}
$hashes = @($paths | Sort-Object -Unique | ForEach-Object {
    [pscustomobject]@{ path = $_; sha256 = (Get-FileHash -LiteralPath (Join-Path $source $_) -Algorithm SHA256).Hash.ToLowerInvariant() }
})
$canonical = ($hashes | ForEach-Object { $_.path + ':' + $_.sha256 }) -join "`n"
$algorithm = [Security.Cryptography.SHA256]::Create()
try { $fingerprint = [BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-','').ToLowerInvariant() }
finally { $algorithm.Dispose() }
[pscustomobject]@{
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    sourceVersion = $version
    roomGame = $roomGame
    roomMatchesSourceName = ($roomGame -ceq "BAR PVE $version")
    publishedGame = if ($release) { $release.gameName } else { $null }
    publishedMatchesRoomName = [bool]($release -and $release.gameName -ceq $roomGame)
    clientLink = Get-SourceLink (Join-Path $ClientData 'games\BAR-PVE.sdd')
    serverLink = Get-SourceLink (Join-Path $ServerRoot 'pve-data\games\BAR-PVE.sdd')
    lastStartscript = [pscustomobject]@{
        note = 'Last generated script, not the live room or evidence of current gameplay.'
        lastWriteUtc = if (Test-Path -LiteralPath $startPath) { (Get-Item -LiteralPath $startPath).LastWriteTimeUtc.ToString('o') } else { $null }
        settings = $options
    }
    roguelikeSourceFingerprint = $fingerprint
    fingerprintScope = 'Feature source and selected integration files only; compare full archive/engine hashes for release multiplayer.'
    files = $hashes
} | ConvertTo-Json -Depth 6
