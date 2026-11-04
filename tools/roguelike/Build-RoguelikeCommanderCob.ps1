param(
    [ValidateSet('all', 'corcom', 'legcom')]
    [string]$Commander = 'all'
)

# Append Roguelike-only weapon callbacks to the original COB without changing
# the original code or function indexes. Slots 5-13 need independent, immediate
# aim approval; the original commander COBs only implement their base slots.
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$units = if ($Commander -eq 'all') { @('corcom', 'legcom') } else { @($Commander) }

function Read-U32([byte[]]$bytes, [int]$offset) {
    return [BitConverter]::ToUInt32($bytes, $offset)
}

function Read-Name([byte[]]$bytes, [int]$offset) {
    $end = $offset
    while ($end -lt $bytes.Length -and $bytes[$end] -ne 0) { $end++ }
    if ($end -ge $bytes.Length) { throw "Unterminated COB name at $offset" }
    return [Text.Encoding]::ASCII.GetString($bytes, $offset, $end - $offset)
}

foreach ($unit in $units) {
    $sourcePath = Join-Path $repoRoot "scripts\Units\$unit.cob"
    $outputPath = Join-Path $repoRoot "scripts\Units\${unit}_roguelike.cob"
    $source = [IO.File]::ReadAllBytes($sourcePath)
    $version = Read-U32 $source 0
    $scriptCount = [int](Read-U32 $source 4)
    $pieceCount = [int](Read-U32 $source 8)
    $codeWords = [int](Read-U32 $source 12)
    $staticVars = Read-U32 $source 16
    $field5 = Read-U32 $source 20
    $indexOffset = [int](Read-U32 $source 24)
    $scriptNameOffset = [int](Read-U32 $source 28)
    $pieceNameOffset = [int](Read-U32 $source 32)
    $codeOffset = [int](Read-U32 $source 36)
    $poolOffset = [int](Read-U32 $source 40)
    $validLayout = $version -eq 4 -and $codeOffset -eq 44 -and $field5 -eq 0 -and
        $indexOffset -eq ($codeOffset + 4 * $codeWords) -and
        $scriptNameOffset -eq ($indexOffset + 4 * $scriptCount) -and
        $pieceNameOffset -eq ($scriptNameOffset + 4 * $scriptCount) -and
        $poolOffset -eq ($pieceNameOffset + 4 * $pieceCount)
    if (-not $validLayout) {
        throw "$unit COB layout differs from the supported version-4 layout"
    }

    $oldEntries = @()
    $oldScriptOffsets = @()
    $oldPieceOffsets = @()
    $entryByName = @{}
    for ($i = 0; $i -lt $scriptCount; $i++) {
        $entry = Read-U32 $source ($indexOffset + 4 * $i)
        $nameOffset = [int](Read-U32 $source ($scriptNameOffset + 4 * $i))
        if ($nameOffset -lt $poolOffset -or $nameOffset -ge $source.Length) { throw "Invalid script name offset in $unit" }
        $name = Read-Name $source $nameOffset
        $oldEntries += $entry
        $oldScriptOffsets += $nameOffset
        $entryByName[$name] = $entry
    }
    for ($i = 0; $i -lt $pieceCount; $i++) {
        $nameOffset = [int](Read-U32 $source ($pieceNameOffset + 4 * $i))
        if ($nameOffset -lt $poolOffset -or $nameOffset -ge $source.Length) { throw "Invalid piece name offset in $unit" }
        $oldPieceOffsets += $nameOffset
    }

    $querySource = if ($unit -eq 'corcom') { 'QueryPrimary' } else { 'QueryWeapon1' }
    $aimFromSource = if ($unit -eq 'corcom') { 'AimFromPrimary' } else { 'AimFromWeapon1' }
    if (-not $entryByName.ContainsKey($querySource) -or -not $entryByName.ContainsKey($aimFromSource)) {
        throw "$unit lacks the expected source muzzle callbacks"
    }

    # COB opcodes: push immediate 1/0, then return. These callbacks do not
    # rotate or signal the primary aim piece, so crowded targets cannot cancel
    # the primary laser's AimWeapon thread.
    [uint32[]]$stubCode = @(0x10021001, 1, 0x10065000, 0x10021001, 0, 0x10065000)
    $aimEntry = [uint32]$codeWords
    $fireEntry = [uint32]($codeWords + 3)
    $additions = [Collections.Generic.List[object]]::new()
    $firstSlot = if ($unit -eq 'corcom') { 4 } else { 5 }
    for ($slot = $firstSlot; $slot -le 13; $slot++) {
        if ($slot -ge 5) {
            $additions.Add([pscustomobject]@{ Name = "AimFromWeapon$slot"; Entry = $entryByName[$aimFromSource] })
            $additions.Add([pscustomobject]@{ Name = "QueryWeapon$slot"; Entry = $entryByName[$querySource] })
        }
        $additions.Add([pscustomobject]@{ Name = "AimWeapon$slot"; Entry = $aimEntry })
        $additions.Add([pscustomobject]@{ Name = "FireWeapon$slot"; Entry = $fireEntry })
    }
    foreach ($addition in $additions) {
        if ($entryByName.ContainsKey($addition.Name)) { throw "$unit already defines $($addition.Name)" }
    }

    $newScriptCount = $scriptCount + $additions.Count
    $newCodeWords = $codeWords + $stubCode.Length
    $newIndexOffset = $codeOffset + 4 * $newCodeWords
    $newScriptNameOffset = $newIndexOffset + 4 * $newScriptCount
    $newPieceNameOffset = $newScriptNameOffset + 4 * $newScriptCount
    $newPoolOffset = $newPieceNameOffset + 4 * $pieceCount
    $oldPoolLength = $source.Length - $poolOffset
    $newNameOffsets = @()
    $nextNameOffset = $newPoolOffset + $oldPoolLength
    foreach ($addition in $additions) {
        $newNameOffsets += [uint32]$nextNameOffset
        $nextNameOffset += [Text.Encoding]::ASCII.GetByteCount($addition.Name) + 1
    }

    $stream = [IO.MemoryStream]::new()
    $writer = [IO.BinaryWriter]::new($stream)
    foreach ($value in @($version, $newScriptCount, $pieceCount, $newCodeWords, $staticVars, $field5,
        $newIndexOffset, $newScriptNameOffset, $newPieceNameOffset, $codeOffset, $newPoolOffset)) {
        $writer.Write([uint32]$value)
    }
    $writer.Write($source, $codeOffset, 4 * $codeWords)
    foreach ($word in $stubCode) { $writer.Write([uint32]$word) }
    foreach ($entry in $oldEntries) { $writer.Write([uint32]$entry) }
    foreach ($addition in $additions) { $writer.Write([uint32]$addition.Entry) }
    foreach ($offset in $oldScriptOffsets) { $writer.Write([uint32]($newPoolOffset + $offset - $poolOffset)) }
    foreach ($offset in $newNameOffsets) { $writer.Write([uint32]$offset) }
    foreach ($offset in $oldPieceOffsets) { $writer.Write([uint32]($newPoolOffset + $offset - $poolOffset)) }
    $writer.Write($source, $poolOffset, $oldPoolLength)
    foreach ($addition in $additions) {
        $writer.Write([Text.Encoding]::ASCII.GetBytes($addition.Name))
        $writer.Write([byte]0)
    }
    $writer.Flush()
    $output = $stream.ToArray()
    $writer.Dispose()
    $stream.Dispose()
    if ($output.Length -ne $nextNameOffset) { throw "$unit COB output length mismatch" }

    # Validate the generated name table, every preserved entry point and all
    # newly added call-in names before replacing the output file.
    if ((Read-U32 $output 4) -ne $newScriptCount -or (Read-U32 $output 12) -ne $newCodeWords) {
        throw "$unit COB header validation failed"
    }
    for ($i = 0; $i -lt $scriptCount; $i++) {
        if ((Read-U32 $output ($newIndexOffset + 4 * $i)) -ne $oldEntries[$i]) { throw "$unit original callback changed" }
        $nameOffset = [int](Read-U32 $output ($newScriptNameOffset + 4 * $i))
        if ((Read-Name $output $nameOffset) -ne (Read-Name $source $oldScriptOffsets[$i])) {
            throw "$unit original callback name changed"
        }
    }
    for ($i = 0; $i -lt $additions.Count; $i++) {
        $slot = $scriptCount + $i
        $nameOffset = [int](Read-U32 $output ($newScriptNameOffset + 4 * $slot))
        if ((Read-Name $output $nameOffset) -ne $additions[$i].Name -or
            (Read-U32 $output ($newIndexOffset + 4 * $slot)) -ne $additions[$i].Entry) {
            throw "$unit new callback validation failed"
        }
    }
    [IO.File]::WriteAllBytes($outputPath, $output)
    Write-Output "$unit`: $scriptCount -> $newScriptCount callbacks, $($source.Length) -> $($output.Length) bytes"
}
