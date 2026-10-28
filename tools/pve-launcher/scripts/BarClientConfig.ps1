Set-StrictMode -Version Latest

function Get-BarClientConfigBackupPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $resolvedConfigPath = Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop
    return "$($resolvedConfigPath.Path).bar-selfhost-backup"
}

function Assert-BarClientConfigPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Chobby configuration file was not found: $ConfigPath"
    }

    if ((Split-Path -Leaf $ConfigPath) -ine 'chobby_config.json') {
        throw "The selected file must be named chobby_config.json: $ConfigPath"
    }

    return (Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop).Path
}

function Get-BarClientConfigCandidates {
    param(
        [string[]]$AdditionalSearchRoots = @()
    )

    $candidatePaths = @()
    $candidateRoots = @(
        (Join-Path $env:USERPROFILE 'Documents\My Games\Beyond All Reason'),
        (Join-Path $env:USERPROFILE 'Documents\My Games\BAR'),
        (Join-Path $env:USERPROFILE 'Beyond All Reason'),
        (Join-Path $env:LOCALAPPDATA 'Beyond All Reason'),
        (Join-Path $env:LOCALAPPDATA 'BAR'),
        (Join-Path $env:APPDATA 'Beyond All Reason'),
        (Join-Path $env:APPDATA 'BAR')
    )

    try {
        $fixedDriveRoots = @([IO.DriveInfo]::GetDrives() | Where-Object {
            $_.DriveType -eq [IO.DriveType]::Fixed -and $_.IsReady
        } | ForEach-Object { $_.RootDirectory.FullName })
        $barDataRelativePaths = @(
            'BAR\Beyond-All-Reason\data',
            'BAR\Beyond All Reason\data',
            'Beyond-All-Reason\data',
            'Beyond All Reason\data',
            'Games\Beyond-All-Reason\data',
            'Games\Beyond All Reason\data'
        )
        foreach ($fixedDriveRoot in $fixedDriveRoots) {
            foreach ($barDataRelativePath in $barDataRelativePaths) {
                $candidateRoots += (Join-Path $fixedDriveRoot $barDataRelativePath)
            }
        }
    }
    catch {
        Write-Verbose "Unable to enumerate fixed drives for BAR client configuration discovery: $($_.Exception.Message)"
    }

    $candidateRoots += $AdditionalSearchRoots
    $candidateRoots = @($candidateRoots | Where-Object {
        $_ -and (Test-Path -LiteralPath $_ -PathType Container)
    } | Select-Object -Unique)

    foreach ($candidateRoot in $candidateRoots) {
        $candidatePath = Join-Path $candidateRoot 'chobby_config.json'
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            $candidatePaths += (Resolve-Path -LiteralPath $candidatePath).Path
        }
    }

    return @($candidatePaths | Select-Object -Unique)
}

function Select-BarClientConfigPath {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = 'Select chobby_config.json'
        $dialog.Filter = 'Chobby configuration (chobby_config.json)|chobby_config.json|JSON files (*.json)|*.json'
        $dialog.FileName = 'chobby_config.json'
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            throw 'No Chobby configuration file was selected.'
        }

        return Assert-BarClientConfigPath -ConfigPath $dialog.FileName
    }
    finally {
        $dialog.Dispose()
    }
}

function Resolve-BarClientConfigPath {
    param(
        [string]$ConfigPath,

        [switch]$PromptForSelection
    )

    if ($ConfigPath) {
        return Assert-BarClientConfigPath -ConfigPath $ConfigPath
    }

    $candidates = @(Get-BarClientConfigCandidates)
    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    if ($PromptForSelection) {
        return Select-BarClientConfigPath
    }

    if ($candidates.Count -gt 1) {
        throw "Multiple Chobby configurations were found. Run again with -ConfigPath: $($candidates -join '; ')"
    }

    throw 'No chobby_config.json was found. Start the BAR launcher once, then rerun or pass -ConfigPath.'
}

function Get-BarClientSpringExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataDirectory
    )

    if (-not (Test-Path -LiteralPath $DataDirectory -PathType Container)) {
        throw "BAR client data directory was not found: $DataDirectory"
    }

    $resolvedDataDirectory = (Resolve-Path -LiteralPath $DataDirectory -ErrorAction Stop).Path
    $engineDirectory = Join-Path $resolvedDataDirectory 'engine'
    if (-not (Test-Path -LiteralPath $engineDirectory -PathType Container)) {
        throw "BAR engine directory was not found: $engineDirectory"
    }

    $engineCandidates = @(Get-ChildItem -LiteralPath $engineDirectory -Filter 'spring.exe' -File -Recurse -ErrorAction Stop |
        Sort-Object -Property @(
            @{ Expression = 'LastWriteTimeUtc'; Descending = $true },
            @{ Expression = 'FullName'; Descending = $true }
        ))
    if ($engineCandidates.Count -eq 0) {
        throw "No spring.exe was found below the BAR engine directory: $engineDirectory"
    }

    return $engineCandidates[0].FullName
}

function Get-BarClientPersistentConfigPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataDirectory
    )

    if (-not (Test-Path -LiteralPath $DataDirectory -PathType Container)) {
        throw "BAR client data directory was not found: $DataDirectory"
    }

    $persistentConfigPath = Join-Path $DataDirectory 'LuaMenu\Config\IGL_data.lua'
    if (-not (Test-Path -LiteralPath $persistentConfigPath -PathType Leaf)) {
        throw "BAR persistent client configuration was not found: $persistentConfigPath"
    }

    return (Resolve-Path -LiteralPath $persistentConfigPath -ErrorAction Stop).Path
}

function Get-BarClientPersistentConfigBackupPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataDirectory
    )

    $persistentConfigPath = Get-BarClientPersistentConfigPath -DataDirectory $DataDirectory
    return "$persistentConfigPath.bar-selfhost-backup"
}

function Set-BarClientPersistentLobbySettings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataDirectory,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z0-9.\-:\[\]]+$')]
        [string]$LobbyHost,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$LobbyPort,

        [Parameter(Mandatory = $true)]
        [bool]$AutoLogin,

        [switch]$CreateBackup
    )

    $persistentConfigPath = Get-BarClientPersistentConfigPath -DataDirectory $DataDirectory
    $persistentConfigText = [IO.File]::ReadAllText($persistentConfigPath)
    $autoLoginValue = $AutoLogin.ToString().ToLowerInvariant()
    $replacementDefinitions = @(
        [pscustomobject]@{
            Name = 'autoLogin'
            Pattern = '(?m)^(\s*autoLogin\s*=\s*)(?:true|false)(\s*,?\s*)$'
            Replacement = '${1}' + $autoLoginValue + '${2}'
        },
        [pscustomobject]@{
            Name = 'battleFilterPassworded2'
            Pattern = '(?m)^(\s*battleFilterPassworded2\s*=\s*)(?:true|false)(\s*,?\s*)$'
            Replacement = '${1}false${2}'
        },
        [pscustomobject]@{
            Name = 'serverAddress'
            Pattern = '(?m)^(\s*serverAddress\s*=\s*)"[^"\r\n]*"(\s*,?\s*)$'
            Replacement = '${1}"' + $LobbyHost + '"${2}'
        },
        [pscustomobject]@{
            Name = 'serverPort'
            Pattern = '(?m)^(\s*serverPort\s*=\s*)\d+(\s*,?\s*)$'
            Replacement = '${1}' + $LobbyPort + '${2}'
        }
    )

    foreach ($replacementDefinition in $replacementDefinitions) {
        $matches = [regex]::Matches($persistentConfigText, $replacementDefinition.Pattern)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one $($replacementDefinition.Name) entry in: $persistentConfigPath"
        }
    }

    $backupPath = $null
    if ($CreateBackup) {
        $backupPath = Get-BarClientPersistentConfigBackupPath -DataDirectory $DataDirectory
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Copy-Item -LiteralPath $persistentConfigPath -Destination $backupPath -ErrorAction Stop
        }
    }

    $updatedConfigText = $persistentConfigText
    foreach ($replacementDefinition in $replacementDefinitions) {
        $updatedConfigText = [regex]::Replace(
            $updatedConfigText,
            $replacementDefinition.Pattern,
            $replacementDefinition.Replacement,
            [Text.RegularExpressions.RegexOptions]::None
        )
    }

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($persistentConfigPath, $updatedConfigText, $utf8WithoutBom)

    return [pscustomobject]@{
        ConfigPath = $persistentConfigPath
        BackupPath = $backupPath
        LobbyHost = $LobbyHost
        LobbyPort = $LobbyPort
        AutoLogin = $AutoLogin
    }
}

function Set-BarClientPersistentLobbyOverrides {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataDirectory,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z0-9.\-:\[\]]+$')]
        [string]$LobbyHost,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$LobbyPort
    )

    return Set-BarClientPersistentLobbySettings `
        -DataDirectory $DataDirectory `
        -LobbyHost $LobbyHost `
        -LobbyPort $LobbyPort `
        -AutoLogin $false `
        -CreateBackup
}
function Restore-BarClientPersistentLobbyOverrides {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataDirectory
    )

    $persistentConfigPath = Get-BarClientPersistentConfigPath -DataDirectory $DataDirectory
    $backupPath = Get-BarClientPersistentConfigBackupPath -DataDirectory $DataDirectory
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "No self-host backup exists for the BAR persistent configuration: $backupPath"
    }

    Copy-Item -LiteralPath $backupPath -Destination $persistentConfigPath -Force -ErrorAction Stop
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop

    return [pscustomobject]@{
        ConfigPath = $persistentConfigPath
        RestoredFrom = $backupPath
    }
}

function Test-BarClientProcess {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Process,

        [string]$DataDirectory
    )

    $clientProcessNames = @(
        'bar-launch',
        'beyond-all-reason',
        'beyondallreason',
        'chobby',
        'recoil',
        'spring',
        'spring-launcher'
    )
    if ($Process.ProcessName -notin $clientProcessNames) {
        return $false
    }
    if (-not $DataDirectory -or $Process.ProcessName -ine 'spring') {
        return $true
    }
    if (-not (Test-Path -LiteralPath $DataDirectory -PathType Container)) {
        throw "BAR client data directory was not found: $DataDirectory"
    }

    $processPath = $null
    try {
        $processPath = $Process.Path
    }
    catch {
    }
    if ([string]::IsNullOrWhiteSpace($processPath)) {
        return $true
    }

    $dataDirectoryPrefix = (Resolve-Path -LiteralPath $DataDirectory -ErrorAction Stop).Path.TrimEnd('\') + '\'
    return [IO.Path]::GetFullPath($processPath).StartsWith(
        $dataDirectoryPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Get-BarClientProcesses {
    param(
        [string]$DataDirectory
    )

    if ($DataDirectory -and -not (Test-Path -LiteralPath $DataDirectory -PathType Container)) {
        throw "BAR client data directory was not found: $DataDirectory"
    }

    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        Test-BarClientProcess -Process $_ -DataDirectory $DataDirectory
    })
}
function Format-BarClientProcessDescription {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Processes
    )

    return (($Processes | Sort-Object -Property Id | ForEach-Object {
        $processPath = $null
        try {
            $processPath = $_.Path
        }
        catch {
        }
        if ([string]::IsNullOrWhiteSpace($processPath)) {
            return "$($_.ProcessName) (PID $($_.Id))"
        }

        return "$($_.ProcessName) (PID $($_.Id), $processPath)"
    }) -join '; ')
}

function Wait-BarClientProcesses {
    param(
        [string]$DataDirectory,

        [ValidateRange(0, 60)]
        [int]$TimeoutSeconds = 0
    )

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        $clientProcesses = @(Get-BarClientProcesses -DataDirectory $DataDirectory)
        if ($clientProcesses.Count -eq 0) {
            return
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            return $clientProcesses
        }

        Start-Sleep -Milliseconds 250
    }
}

function Stop-BarClientProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Processes
    )

    foreach ($clientProcess in @($Processes | Sort-Object -Property Id -Unique)) {
        $currentProcess = Get-Process -Id $clientProcess.Id -ErrorAction SilentlyContinue
        if (-not $currentProcess -or $currentProcess.ProcessName -ine $clientProcess.ProcessName) {
            continue
        }

        Stop-Process -InputObject $currentProcess -Force -ErrorAction Stop
    }
}

function Assert-BarClientStopped {
    param(
        [switch]$SkipClientProcessCheck,

        [string]$DataDirectory,

        [ValidateRange(0, 60)]
        [int]$WaitSeconds = 0
    )

    if ($SkipClientProcessCheck) {
        return
    }

    $clientProcesses = @(Wait-BarClientProcesses -DataDirectory $DataDirectory -TimeoutSeconds $WaitSeconds)
    if ($clientProcesses.Count -gt 0) {
        $description = Format-BarClientProcessDescription -Processes $clientProcesses
        throw "Close BAR, Chobby, Recoil, and the BAR launcher before changing the lobby server. Running processes: $description"
    }
}
function Read-BarClientConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $configurationText = [IO.File]::ReadAllText($ConfigPath)
    try {
        $configuration = $configurationText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Chobby configuration is not valid JSON: $ConfigPath. $($_.Exception.Message)"
    }

    if ($null -eq $configuration) {
        throw "Chobby configuration is empty: $ConfigPath"
    }

    return $configuration
}

function Set-BarClientConfigurationValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $existingProperty = $Target.PSObject.Properties[$Name]
    if ($existingProperty) {
        $existingProperty.Value = $Value
        return
    }

    $Target | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
}

function Write-BarClientConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $configurationJson = $Configuration | ConvertTo-Json -Depth 32
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ConfigPath, ($configurationJson + [Environment]::NewLine), $utf8WithoutBom)
}

function Set-BarSelfHostServer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LobbyHost,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$LobbyPort,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerName,

        [switch]$SkipClientProcessCheck
    )

    $resolvedConfigPath = Assert-BarClientConfigPath -ConfigPath $ConfigPath
    Assert-BarClientStopped -SkipClientProcessCheck:$SkipClientProcessCheck -DataDirectory (Split-Path -Parent $resolvedConfigPath)

    $backupPath = Get-BarClientConfigBackupPath -ConfigPath $resolvedConfigPath
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        Copy-Item -LiteralPath $resolvedConfigPath -Destination $backupPath -ErrorAction Stop
    }

    $configuration = Read-BarClientConfiguration -ConfigPath $resolvedConfigPath
    if ($null -eq $configuration.PSObject.Properties['server']) {
        $configuration | Add-Member -MemberType NoteProperty -Name 'server' -Value ([pscustomobject]@{})
    }
    if ($null -eq $configuration.server) {
        $configuration.server = [pscustomobject]@{}
    }

    Set-BarClientConfigurationValue -Target $configuration.server -Name 'address' -Value $LobbyHost
    Set-BarClientConfigurationValue -Target $configuration.server -Name 'port' -Value $LobbyPort
    Set-BarClientConfigurationValue -Target $configuration.server -Name 'serverName' -Value $ServerName
    Set-BarClientConfigurationValue -Target $configuration.server -Name 'protocol' -Value 'spring'
    Write-BarClientConfiguration -ConfigPath $resolvedConfigPath -Configuration $configuration

    return [pscustomobject]@{
        ConfigPath = $resolvedConfigPath
        BackupPath = $backupPath
        LobbyHost = $LobbyHost
        LobbyPort = $LobbyPort
        ServerName = $ServerName
    }
}

function Restore-BarClientOfficialServer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [switch]$SkipClientProcessCheck
    )

    $resolvedConfigPath = Assert-BarClientConfigPath -ConfigPath $ConfigPath
    Assert-BarClientStopped -SkipClientProcessCheck:$SkipClientProcessCheck -DataDirectory (Split-Path -Parent $resolvedConfigPath)

    $backupPath = Get-BarClientConfigBackupPath -ConfigPath $resolvedConfigPath
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "No self-host backup exists for this Chobby configuration: $backupPath"
    }

    Copy-Item -LiteralPath $backupPath -Destination $resolvedConfigPath -Force -ErrorAction Stop
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop

    return [pscustomobject]@{
        ConfigPath = $resolvedConfigPath
        RestoredFrom = $backupPath
    }
}

function Get-BarClientLauncherExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataDirectory,

        [string]$Path
    )

    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "The BAR launcher executable was not found: $Path"
        }
        return (Resolve-Path -LiteralPath $Path).Path
    }

    if (-not (Test-Path -LiteralPath $DataDirectory -PathType Container)) {
        throw "BAR client data directory was not found: $DataDirectory"
    }

    $installRoot = Split-Path -Parent (Resolve-Path -LiteralPath $DataDirectory).Path
    $candidatePaths = @(
        (Join-Path $installRoot 'Beyond-All-Reason.exe'),
        (Join-Path $installRoot 'bar-launcher.exe'),
        (Join-Path $installRoot 'spring-launcher.exe')
    )
    if ($env:LOCALAPPDATA) {
        $candidatePaths += @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Beyond All Reason\Beyond-All-Reason.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\beyond-all-reason\Beyond-All-Reason.exe'),
            (Join-Path $env:LOCALAPPDATA 'Beyond All Reason\Beyond-All-Reason.exe')
        )
    }

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidatePath).Path
        }
    }

    throw "No BAR launcher executable was found near the client data directory. Install the official BAR launcher next to its data directory, or rerun with -LauncherPath. Searched: $($candidatePaths -join '; ')"
}

function New-BarLauncherPrivateConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LauncherConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LobbyHost,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 65535)]
        [int]$LobbyPort,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerName
    )

    if (-not (Test-Path -LiteralPath $LauncherConfigPath -PathType Leaf)) {
        throw "The BAR launcher configuration was not found: $LauncherConfigPath"
    }

    $configuration = Read-BarClientConfiguration -ConfigPath $LauncherConfigPath

    if ($null -eq $configuration.PSObject.Properties['json_files']) {
        $configuration | Add-Member -MemberType NoteProperty -Name 'json_files' -Value ([pscustomobject]@{})
    }
    if ($null -eq $configuration.json_files) {
        $configuration.json_files = [pscustomobject]@{}
    }

    $chobbyEntry = $configuration.json_files.PSObject.Properties['chobby_config.json']
    if ($null -eq $chobbyEntry -or $null -eq $chobbyEntry.Value) {
        $chobbyConfig = [pscustomobject]@{}
        $configuration.json_files | Add-Member -MemberType NoteProperty -Name 'chobby_config.json' -Value $chobbyConfig
    }
    else {
        $chobbyConfig = $chobbyEntry.Value
    }

    if ($null -eq $chobbyConfig.PSObject.Properties['server']) {
        $chobbyConfig | Add-Member -MemberType NoteProperty -Name 'server' -Value ([pscustomobject]@{})
    }
    if ($null -eq $chobbyConfig.server) {
        $chobbyConfig.server = [pscustomobject]@{}
    }

    # The launcher rewrites chobby_config.json from this template right before
    # starting spring.exe, so the template itself must carry the private lobby.
    Set-BarClientConfigurationValue -Target $chobbyConfig.server -Name 'address' -Value $LobbyHost
    Set-BarClientConfigurationValue -Target $chobbyConfig.server -Name 'port' -Value $LobbyPort
    Set-BarClientConfigurationValue -Target $chobbyConfig.server -Name 'serverName' -Value $ServerName
    Set-BarClientConfigurationValue -Target $chobbyConfig.server -Name 'protocol' -Value 'spring'
    Set-BarClientConfigurationValue -Target $chobbyConfig -Name 'game' -Value 'byar'

    # auto_start and config_url are per-setup keys in the launcher
    # configuration: patch every setup so the selected one starts spring.exe
    # without waiting for a click and never consults the remote configuration
    # (a remote refresh would reload the wizard and rewrite chobby_config.json
    # from the official template mid-session).
    Set-BarClientConfigurationValue -Target $configuration -Name 'auto_start' -Value $true
    $setupObjects = @()
    $setupsProperty = $configuration.PSObject.Properties['setups']
    if ($null -ne $setupsProperty -and $null -ne $setupsProperty.Value) {
        $setupObjects = @($setupsProperty.Value)
    }
    foreach ($targetObject in @($configuration) + $setupObjects) {
        Set-BarClientConfigurationValue -Target $targetObject -Name 'auto_start' -Value $true
        $configUrlProperty = $targetObject.PSObject.Properties['config_url']
        if ($configUrlProperty) {
            $configUrlProperty.Value = $null
        }
        else {
            $targetObject | Add-Member -MemberType NoteProperty -Name 'config_url' -Value $null
        }
    }

    $destinationDirectory = Split-Path -Parent $DestinationPath
    if ($destinationDirectory) {
        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    }
    Write-BarClientConfiguration -ConfigPath $DestinationPath -Configuration $configuration

    return [pscustomobject]@{
        Path = $DestinationPath
        SourcePath = $LauncherConfigPath
        LobbyHost = $LobbyHost
        LobbyPort = $LobbyPort
        ServerName = $ServerName
    }
}
