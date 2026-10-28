[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('GetServerStatus', 'SwitchToPrivateServer', 'RestoreOfficialServer', 'StartGame')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9.\-:\[\]]+$')]
    [string]$LobbyHost,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 65535)]
    [int]$LobbyPort,

    [ValidateNotNullOrEmpty()]
    [string]$ServerName = 'BARcn'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'BarClientConfig.ps1')

function Write-ClientLauncherResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $json = ($Value | ConvertTo-Json -Depth 8 -Compress)
    $resultPath = $env:BAR_CLIENT_LAUNCHER_RESULT_PATH
    if ($resultPath) {
        $temporaryPath = "$resultPath.tmp-$PID"
        [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            Remove-Item -LiteralPath $resultPath -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $temporaryPath -Destination $resultPath -Force -ErrorAction Stop
    }
    else {
        Write-Output $json
    }
}

function Write-ClientLauncherError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $errorPath = $env:BAR_CLIENT_LAUNCHER_ERROR_PATH
    if ($errorPath) {
        $temporaryPath = "$errorPath.tmp-$PID"
        [IO.File]::WriteAllText($temporaryPath, $Message, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $errorPath -PathType Leaf) {
            Remove-Item -LiteralPath $errorPath -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $temporaryPath -Destination $errorPath -Force -ErrorAction Stop
    }
    else {
        Write-Error $Message
    }
}

function Test-EndpointMatch {
    param(
        [AllowNull()][string]$LeftHost,
        [int]$LeftPort,
        [AllowNull()][string]$RightHost,
        [int]$RightPort
    )

    if ([string]::IsNullOrWhiteSpace($LeftHost) -or [string]::IsNullOrWhiteSpace($RightHost)) {
        return $false
    }
    return $LeftHost.Equals($RightHost, [StringComparison]::OrdinalIgnoreCase) -and $LeftPort -eq $RightPort
}

function Start-BarOfficialLauncher {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [string]$ArgumentList
    )

    # Electron-based launchers switch into Node mode when this development
    # variable leaks in from VS Code/Codex or another Electron parent process.
    # In that mode the official BAR launcher rejects its own --config option.
    $hadElectronRunAsNode = Test-Path Env:ELECTRON_RUN_AS_NODE
    $previousElectronRunAsNode = $env:ELECTRON_RUN_AS_NODE
    try {
        Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
        $parameters = @{
            FilePath = $FilePath
            WorkingDirectory = $WorkingDirectory
            PassThru = $true
        }
        if ($ArgumentList) {
            $parameters.ArgumentList = $ArgumentList
        }
        return Start-Process @parameters
    }
    finally {
        if ($hadElectronRunAsNode) {
            $env:ELECTRON_RUN_AS_NODE = $previousElectronRunAsNode
        }
    }
}

function Get-PersistentLobbyValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataDirectory
    )

    $persistentConfigPath = Get-BarClientPersistentConfigPath -DataDirectory $DataDirectory
    $persistentConfigText = [IO.File]::ReadAllText($persistentConfigPath)
    $addressMatch = [regex]::Match($persistentConfigText, '(?m)^\s*serverAddress\s*=\s*"(?<value>[^"\r\n]*)"\s*,?\s*$')
    $portMatch = [regex]::Match($persistentConfigText, '(?m)^\s*serverPort\s*=\s*(?<value>\d+)\s*,?\s*$')
    if (-not $addressMatch.Success -or -not $portMatch.Success) {
        throw "无法读取 BAR 持久化大厅设置: $persistentConfigPath"
    }

    return [pscustomobject]@{
        ConfigPath = $persistentConfigPath
        LobbyHost = $addressMatch.Groups['value'].Value
        LobbyPort = [int]$portMatch.Groups['value'].Value
    }
}

function Get-ChobbyServerEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    # StrictMode-safe access: a fresh or damaged chobby_config.json may lack
    # the whole "server" object, and PSCustomObject property access throws.
    $address = $null
    $port = 0
    $serverProperty = $Configuration.PSObject.Properties['server']
    if ($serverProperty -and $null -ne $serverProperty.Value) {
        $server = $serverProperty.Value
        $addressProperty = $server.PSObject.Properties['address']
        if ($addressProperty -and $null -ne $addressProperty.Value) {
            $address = [string]$addressProperty.Value
        }
        $portProperty = $server.PSObject.Properties['port']
        if ($portProperty -and $null -ne $portProperty.Value) {
            $port = [int]$portProperty.Value
        }
    }
    return @($address, $port)
}

function Get-ServerStatusCore {
    $resolvedConfigPath = Assert-BarClientConfigPath -ConfigPath $ConfigPath
    $dataDirectory = Split-Path -Parent $resolvedConfigPath
    $configuration = Read-BarClientConfiguration -ConfigPath $resolvedConfigPath
    $endpoint = Get-ChobbyServerEndpoint -Configuration $configuration
    $address = $endpoint[0]
    $port = $endpoint[1]

    $hasClientBackup = Test-Path -LiteralPath (Get-BarClientConfigBackupPath -ConfigPath $resolvedConfigPath) -PathType Leaf
    $hasPersistentBackup = $false
    $persistentHost = $null
    $persistentPort = 0
    $persistentConfigPath = Join-Path $dataDirectory 'LuaMenu\Config\IGL_data.lua'
    if (Test-Path -LiteralPath $persistentConfigPath -PathType Leaf) {
        $persistentValues = Get-PersistentLobbyValues -DataDirectory $dataDirectory
        $persistentHost = $persistentValues.LobbyHost
        $persistentPort = $persistentValues.LobbyPort
        $hasPersistentBackup = Test-Path -LiteralPath (Get-BarClientPersistentConfigBackupPath -DataDirectory $dataDirectory) -PathType Leaf
    }

    $isPrivate = Test-EndpointMatch -LeftHost $address -LeftPort $port -RightHost $LobbyHost -RightPort $LobbyPort
    $state = 'unknown'
    if ($isPrivate) {
        $state = 'private'
    }
    elseif (-not $hasClientBackup -and -not $hasPersistentBackup) {
        $state = 'official'
    }

    return [pscustomobject]@{
        state = $state
        configPath = $resolvedConfigPath
        address = $address
        port = $port
        privateHost = $LobbyHost
        privatePort = $LobbyPort
        hasClientBackup = $hasClientBackup
        hasPersistentBackup = $hasPersistentBackup
        persistentAddress = $persistentHost
        persistentPort = $persistentPort
    }
}

function Switch-ToPrivateServerCore {
    $resolvedConfigPath = Assert-BarClientConfigPath -ConfigPath $ConfigPath
    $dataDirectory = Split-Path -Parent $resolvedConfigPath
    Assert-BarClientStopped -DataDirectory $dataDirectory

    $persistentConfigPath = Join-Path $dataDirectory 'LuaMenu\Config\IGL_data.lua'
    if (-not (Test-Path -LiteralPath $persistentConfigPath -PathType Leaf)) {
        throw '未找到 Chobby 持久化配置（LuaMenu\Config\IGL_data.lua）。请先完整启动一次游戏到大厅，再执行切换。'
    }

    $clientConfigSwitched = $false
    $persistentOverridesApplied = $false
    try {
        $result = Set-BarSelfHostServer `
            -ConfigPath $resolvedConfigPath `
            -LobbyHost $LobbyHost `
            -LobbyPort $LobbyPort `
            -ServerName $ServerName `
            -SkipClientProcessCheck
        $clientConfigSwitched = $true
        Set-BarClientPersistentLobbyOverrides `
            -DataDirectory $dataDirectory `
            -LobbyHost $LobbyHost `
            -LobbyPort $LobbyPort | Out-Null
        $persistentOverridesApplied = $true
    }
    catch {
        if ($clientConfigSwitched) {
            Restore-BarClientOfficialServer -ConfigPath $resolvedConfigPath -SkipClientProcessCheck | Out-Null
        }
        if (-not $persistentOverridesApplied) {
            $persistentBackupPath = Get-BarClientPersistentConfigBackupPath -DataDirectory $dataDirectory
            if (Test-Path -LiteralPath $persistentBackupPath -PathType Leaf) {
                Restore-BarClientPersistentLobbyOverrides -DataDirectory $dataDirectory | Out-Null
            }
        }
        throw
    }

    return [pscustomobject]@{
        state = 'private'
        configPath = $result.ConfigPath
        address = $result.LobbyHost
        port = $result.LobbyPort
        backupPath = $result.BackupPath
    }
}

function Restore-OfficialServerCore {
    $resolvedConfigPath = Assert-BarClientConfigPath -ConfigPath $ConfigPath
    $dataDirectory = Split-Path -Parent $resolvedConfigPath

    $currentConfiguration = Read-BarClientConfiguration -ConfigPath $resolvedConfigPath
    $currentEndpoint = Get-ChobbyServerEndpoint -Configuration $currentConfiguration
    $currentHost = $currentEndpoint[0]
    $currentPort = $currentEndpoint[1]
    if ([string]::IsNullOrWhiteSpace($currentHost) -or $currentPort -lt 1 -or $currentPort -gt 65535) {
        throw "Chobby 配置缺少有效的 server 段（配置损坏或尚未初始化），请先启动一次官方 BAR 启动器: $resolvedConfigPath"
    }

    # The persistent Chobby config (IGL_data.lua) only exists after the game
    # ran at least once; every persistent-path helper throws when it is
    # missing, so gate all of them on a real file.
    $persistentConfigPath = Join-Path $dataDirectory 'LuaMenu\Config\IGL_data.lua'
    $hasPersistentConfig = Test-Path -LiteralPath $persistentConfigPath -PathType Leaf
    $persistentBackupPath = $null
    $hasPersistentBackup = $false
    if ($hasPersistentConfig) {
        $persistentBackupPath = Get-BarClientPersistentConfigBackupPath -DataDirectory $dataDirectory
        $hasPersistentBackup = Test-Path -LiteralPath $persistentBackupPath -PathType Leaf
    }
    $clientBackupPath = Get-BarClientConfigBackupPath -ConfigPath $resolvedConfigPath
    $hasClientBackup = Test-Path -LiteralPath $clientBackupPath -PathType Leaf

    if (-not $hasPersistentBackup -and -not $hasClientBackup) {
        if (Test-EndpointMatch -LeftHost $currentHost -LeftPort $currentPort -RightHost $LobbyHost -RightPort $LobbyPort) {
            throw '配置仍指向国服但不存在官方备份。请先启动一次官方 BAR 启动器让它重写配置，然后再试。'
        }

        $persistentMatchesCurrent = $true
        if ($hasPersistentConfig) {
            $persistentValues = Get-PersistentLobbyValues -DataDirectory $dataDirectory
            $persistentMatchesCurrent = Test-EndpointMatch -LeftHost $persistentValues.LobbyHost -LeftPort $persistentValues.LobbyPort -RightHost $currentHost -RightPort $currentPort
        }
        if ($persistentMatchesCurrent) {
            return [pscustomobject]@{
                state = 'official'
                configPath = $resolvedConfigPath
                address = $currentHost
                port = $currentPort
                restored = @()
            }
        }
    }

    Assert-BarClientStopped -DataDirectory $dataDirectory -WaitSeconds 10

    $restoredPaths = @()
    if ($hasPersistentBackup) {
        $persistentResult = Restore-BarClientPersistentLobbyOverrides -DataDirectory $dataDirectory
        $restoredPaths += $persistentResult.ConfigPath
    }
    if ($hasClientBackup) {
        $clientResult = Restore-BarClientOfficialServer -ConfigPath $resolvedConfigPath -SkipClientProcessCheck
        $restoredPaths += $clientResult.ConfigPath
    }

    $finalConfiguration = Read-BarClientConfiguration -ConfigPath $resolvedConfigPath
    $finalEndpoint = Get-ChobbyServerEndpoint -Configuration $finalConfiguration
    $finalHost = $finalEndpoint[0]
    $finalPort = $finalEndpoint[1]
    if (Test-EndpointMatch -LeftHost $finalHost -LeftPort $finalPort -RightHost $LobbyHost -RightPort $LobbyPort) {
        throw '恢复失败：配置仍指向国服地址。请先启动一次官方 BAR 启动器让它重写配置，然后再试。'
    }

    if ($hasPersistentConfig) {
        $finalPersistentValues = Get-PersistentLobbyValues -DataDirectory $dataDirectory
        if (-not (Test-EndpointMatch -LeftHost $finalPersistentValues.LobbyHost -LeftPort $finalPersistentValues.LobbyPort -RightHost $finalHost -RightPort $finalPort)) {
            $synchronizationResult = Set-BarClientPersistentLobbySettings `
                -DataDirectory $dataDirectory `
                -LobbyHost $finalHost `
                -LobbyPort $finalPort `
                -AutoLogin $true
            if ($synchronizationResult.ConfigPath -notin $restoredPaths) {
                $restoredPaths += $synchronizationResult.ConfigPath
            }
        }
    }

    return [pscustomobject]@{
        state = 'official'
        configPath = $resolvedConfigPath
        address = $finalHost
        port = $finalPort
        restored = $restoredPaths
    }
}

function Start-GameCore {
    $resolvedConfigPath = Assert-BarClientConfigPath -ConfigPath $ConfigPath
    $dataDirectory = Split-Path -Parent $resolvedConfigPath
    $launcherExecutablePath = Get-BarClientLauncherExecutable -DataDirectory $dataDirectory

    Assert-BarClientStopped -DataDirectory $dataDirectory

    $configuration = Read-BarClientConfiguration -ConfigPath $resolvedConfigPath
    $currentEndpoint = Get-ChobbyServerEndpoint -Configuration $configuration
    $currentHost = $currentEndpoint[0]
    $currentPort = $currentEndpoint[1]
    if ([string]::IsNullOrWhiteSpace($currentHost) -or $currentPort -lt 1) {
        throw "Chobby 配置缺少有效的 server 段（配置损坏或尚未初始化），请先启动一次官方 BAR 启动器: $resolvedConfigPath"
    }
    $isPrivate = Test-EndpointMatch -LeftHost $currentHost -LeftPort $currentPort -RightHost $LobbyHost -RightPort $LobbyPort

    if (-not $isPrivate) {
        # Official endpoint: start the stock launcher and return immediately;
        # nothing was switched, so there is nothing to restore afterwards.
        $null = Start-BarOfficialLauncher `
            -FilePath $launcherExecutablePath `
            -WorkingDirectory (Split-Path -Parent $launcherExecutablePath)
        return [pscustomobject]@{
            state = 'official'
            session = 'started'
            launcherPath = $launcherExecutablePath
        }
    }

    # Private endpoint (persistent 国服 state from SwitchToPrivateServer):
    # still launch through the official launcher with a derived configuration
    # so its download bridge stays alive (maps/updates come from official
    # sources) while the launcher writes the private lobby into
    # chobby_config.json right before starting spring.exe.
    $launcherConfigPath = Join-Path $dataDirectory 'config.json'
    if (-not (Test-Path -LiteralPath $launcherConfigPath -PathType Leaf)) {
        throw "找不到 BAR 启动器配置: $launcherConfigPath。请先启动一次官方 BAR 启动器。"
    }

    $tcpClient = New-Object System.Net.Sockets.TcpClient
    try {
        $connectResult = $tcpClient.BeginConnect($LobbyHost, $LobbyPort, $null, $null)
        if (-not $connectResult.AsyncWaitHandle.WaitOne(5000)) {
            throw "国服大厅没有响应 ${LobbyHost}:$LobbyPort。"
        }
        $tcpClient.EndConnect($connectResult)
    }
    catch {
        throw "无法连接国服大厅 ${LobbyHost}:$LobbyPort。$($_.Exception.Message)"
    }
    finally {
        $tcpClient.Dispose()
    }

    $privateLauncherConfigPath = Join-Path ([IO.Path]::GetTempPath()) ("bar-launcher-private-{0}.json" -f ([Guid]::NewGuid().ToString('N')))
    try {
        $null = New-BarLauncherPrivateConfiguration `
            -LauncherConfigPath $launcherConfigPath `
            -DestinationPath $privateLauncherConfigPath `
            -LobbyHost $LobbyHost `
            -LobbyPort $LobbyPort `
            -ServerName $ServerName

        $argumentList = "--config `"$privateLauncherConfigPath`" --disable-launcher-update"
        $launcherProcess = Start-BarOfficialLauncher `
            -FilePath $launcherExecutablePath `
            -ArgumentList $argumentList `
            -WorkingDirectory (Split-Path -Parent $launcherExecutablePath)
        Wait-Process -Id $launcherProcess.Id -ErrorAction SilentlyContinue
    }
    finally {
        if (Test-Path -LiteralPath $privateLauncherConfigPath -PathType Leaf) {
            Remove-Item -LiteralPath $privateLauncherConfigPath -Force -ErrorAction SilentlyContinue
        }
    }

    # The session ended. Chobby persists the lobby it actually used (the
    # private one), so the persistent 国服 state normally survives; if it
    # drifted, re-assert it idempotently (existing backups are kept).
    $afterConfiguration = Read-BarClientConfiguration -ConfigPath $resolvedConfigPath
    $afterEndpoint = Get-ChobbyServerEndpoint -Configuration $afterConfiguration
    $afterHost = $afterEndpoint[0]
    $afterPort = $afterEndpoint[1]
    $stateDrifted = -not (Test-EndpointMatch -LeftHost $afterHost -LeftPort $afterPort -RightHost $LobbyHost -RightPort $LobbyPort)
    if ($stateDrifted) {
        Set-BarSelfHostServer `
            -ConfigPath $resolvedConfigPath `
            -LobbyHost $LobbyHost `
            -LobbyPort $LobbyPort `
            -ServerName $ServerName `
            -SkipClientProcessCheck | Out-Null
        Set-BarClientPersistentLobbyOverrides `
            -DataDirectory $dataDirectory `
            -LobbyHost $LobbyHost `
            -LobbyPort $LobbyPort | Out-Null
    }

    return [pscustomobject]@{
        state = 'private'
        session = 'ended'
        stateDriftRepaired = $stateDrifted
        launcherPath = $launcherExecutablePath
    }
}

try {
    $result = $null
    switch ($Action) {
        'GetServerStatus' { $result = Get-ServerStatusCore }
        'SwitchToPrivateServer' { $result = Switch-ToPrivateServerCore }
        'RestoreOfficialServer' { $result = Restore-OfficialServerCore }
        'StartGame' { $result = Start-GameCore }
    }
    Write-ClientLauncherResult -Value $result
}
catch {
    Write-ClientLauncherError -Message $_.Exception.Message
    exit 1
}
