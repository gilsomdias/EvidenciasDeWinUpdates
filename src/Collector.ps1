param(
    [switch]$Initialize,
    [ValidateRange(0,168)]
    [int]$LookbackHours = 0
)

$ErrorActionPreference = 'Stop'

$Version         = '1.0.0'
$BasePath        = $PSScriptRoot
$StateFile       = Join-Path $BasePath 'WindowsUpdateHistoryState.json'
$ConfigFile      = Join-Path $BasePath 'RuntimeConfig.json'
$IntegrityFile   = Join-Path $BasePath 'Integrity.json'
$EventSource     = 'WindowsUpdateEvidence'
$NativeLog       = 'Microsoft-Windows-WindowsUpdateClient/Operational'
$MutexName       = 'Global\WindowsUpdateEvidenceCollector'

function Write-EvidenceEvent {
    param(
        [int]$EventId,
        [System.Diagnostics.EventLogEntryType]$EntryType,
        [string]$Message
    )

    [System.Diagnostics.EventLog]::WriteEntry(
        $EventSource,
        $Message,
        $EntryType,
        $EventId
    )
}

function Assert-Integrity {
    if (-not (Test-Path -LiteralPath $IntegrityFile)) {
        throw 'Arquivo de integridade nao encontrado.'
    }

    $Manifest = Get-Content -LiteralPath $IntegrityFile -Raw | ConvertFrom-Json

    foreach ($Item in @($Manifest.Files)) {
        $Target = Join-Path $BasePath ([string]$Item.Name)

        if (-not (Test-Path -LiteralPath $Target)) {
            throw "Arquivo protegido nao encontrado: $($Item.Name)"
        }

        $Actual = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToUpperInvariant()
        $Expected = ([string]$Item.SHA256).ToUpperInvariant()

        if ($Actual -ne $Expected) {
            throw "Falha de integridade em '$($Item.Name)'."
        }
    }
}

function Get-RuntimeConfig {
    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        throw 'RuntimeConfig.json nao encontrado.'
    }

    return (Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json)
}

function Get-WuaHistory {
    param(
        [int]$MaxItems
    )

    $Session  = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()
    $Total    = [int]$Searcher.GetTotalHistoryCount()

    if ($Total -le 0) {
        return @()
    }

    $Count = [Math]::Min($Total, $MaxItems)
    $Collection = $Searcher.QueryHistory(0, $Count)
    $Result = @()

    for ($i = 0; $i -lt $Collection.Count; $i++) {
        $Result += $Collection.Item($i)
    }

    return $Result
}

function Get-HistoryKey {
    param($Entry)

    $UpdateId = ''
    $Revision = ''

    try {
        $UpdateId = [string]$Entry.UpdateIdentity.UpdateID
        $Revision = [string]$Entry.UpdateIdentity.RevisionNumber
    }
    catch {}

    return ('{0}|{1}|{2}|{3}|{4}|{5}' -f `
        $UpdateId,
        $Revision,
        ([datetime]$Entry.Date).Ticks,
        [int]$Entry.Operation,
        [int]$Entry.ResultCode,
        [int64]$Entry.HResult
    )
}

function Save-State {
    param(
        [string[]]$Keys,
        [string]$Reason = 'Normal'
    )

    $UniqueKeys = @(
        $Keys |
        Where-Object { $_ } |
        Select-Object -Unique
    )

    if ($UniqueKeys.Count -gt 4000) {
        $UniqueKeys = @($UniqueKeys | Select-Object -Last 4000)
    }

    $State = [PSCustomObject]@{
        Version       = 1
        Collector     = $Version
        UpdatedAt     = (Get-Date).ToString('o')
        Reason        = $Reason
        ProcessedKeys = @($UniqueKeys)
    }

    $Temp = "$StateFile.tmp"

    $State |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $Temp -Encoding UTF8

    Move-Item -LiteralPath $Temp -Destination $StateFile -Force
}

function Get-UpdateSource {
    param($Entry)

    $Selection = -1
    $ServiceId = ''

    try { $Selection = [int]$Entry.ServerSelection } catch {}
    try { $ServiceId = ([string]$Entry.ServiceID).Trim('{}') } catch {}

    if ($ServiceId -ieq '7971f918-a847-4430-9279-4a52d1efe18d') {
        return 'Microsoft Update'
    }

    if ($ServiceId -ieq '9482f4b4-e343-43b6-b170-9a65bc822c77') {
        return 'Windows Update'
    }

    switch ($Selection) {
        1 {
            $WUReg = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            $WUServer = (Get-ItemProperty -Path $WUReg -ErrorAction SilentlyContinue).WUServer

            if ($WUServer) {
                return "WSUS - $WUServer"
            }

            return 'Servidor gerenciado / WSUS'
        }

        2 {
            return 'Windows Update'
        }

        3 {
            if ($ServiceId) {
                return "Outro servico de atualizacao - $ServiceId"
            }

            return 'Outro servico de atualizacao'
        }

        default {
            $AUReg = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            $WUReg = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            $UseWUServer = (Get-ItemProperty -Path $AUReg -ErrorAction SilentlyContinue).UseWUServer
            $WUServer = (Get-ItemProperty -Path $WUReg -ErrorAction SilentlyContinue).WUServer

            if ($UseWUServer -eq 1 -and $WUServer) {
                return "WSUS - $WUServer"
            }

            return 'Windows Update Agent - origem padrao'
        }
    }
}

function Get-ActorEvidence {
    param($Entry)

    $Title = [string]$Entry.Title
    $ClientApplicationId = 'Unknown'

    try {
        $Candidate = [string]$Entry.ClientApplicationID
        if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
            $ClientApplicationId = $Candidate
        }
    }
    catch {}

    $StartTime = ([datetime]$Entry.Date).AddMinutes(-15)
    $EndTime   = ([datetime]$Entry.Date).AddMinutes(15)

    $KB = $null
    $KBMatch = [regex]::Match(
        $Title,
        'KB\d+',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($KBMatch.Success) {
        $KB = $KBMatch.Value
    }

    $NativeEvents = @()

    try {
        $NativeEvents += @(
            Get-WinEvent -FilterHashtable @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
                StartTime    = $StartTime
                EndTime      = $EndTime
            } -ErrorAction Stop
        )
    }
    catch {}

    try {
        $NativeEvents += @(
            Get-WinEvent -FilterHashtable @{
                LogName   = $NativeLog
                StartTime = $StartTime
                EndTime   = $EndTime
            } -ErrorAction Stop
        )
    }
    catch {}

    $Matched = @()

    foreach ($NativeEvent in $NativeEvents) {
        $Message = [string]$NativeEvent.Message

        if ([string]::IsNullOrWhiteSpace($Message)) {
            continue
        }

        $IsMatch = $false

        if ($KB) {
            if ($Message -match [regex]::Escape($KB)) {
                $IsMatch = $true
            }
        }
        else {
            $Fragment = $Title

            if ($Fragment.Length -gt 80) {
                $Fragment = $Fragment.Substring(0, 80)
            }

            if ($Fragment -and $Message.IndexOf(
                $Fragment,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -ge 0) {
                $IsMatch = $true
            }
        }

        if ($IsMatch) {
            $Matched += $NativeEvent
        }
    }

    $SystemSids = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')
    $SystemSeen = $false
    $UserAccount = $null

    foreach ($NativeEvent in $Matched) {
        if (-not $NativeEvent.UserId) {
            continue
        }

        $Sid = $NativeEvent.UserId.Value
        $Account = $Sid

        try {
            $Account = $NativeEvent.UserId.Translate(
                [System.Security.Principal.NTAccount]
            ).Value
        }
        catch {}

        if ($SystemSids -contains $Sid) {
            $SystemSeen = $true
            continue
        }

        if (-not $UserAccount -and
            $Account -notmatch '^(NT AUTHORITY|NT SERVICE)\\' -and
            $Account -notmatch '^DWM-' -and
            $Account -notmatch '^UMFD-') {
            $UserAccount = $Account
        }
    }

    $ExecutionType = 'Nao identificado'
    $RequestedBy   = 'Nao identificado'
    $InstalledBy   = 'Nao identificado'
    $Evidence      = "ClientApplicationID: $ClientApplicationId"

    if ($UserAccount) {
        $ExecutionType = 'Manual (evidencia de usuario)'
        $RequestedBy   = $UserAccount
        $Evidence      = "Usuario associado a evento nativo: $UserAccount; ClientApplicationID: $ClientApplicationId"
    }
    elseif ($ClientApplicationId -ieq 'AutomaticUpdates') {
        $ExecutionType = 'Automatica'
        $Evidence      = "ClientApplicationID: $ClientApplicationId"
    }

    if ($SystemSeen) {
        $InstalledBy = 'NT AUTHORITY\SYSTEM'
    }
    elseif ($UserAccount) {
        $InstalledBy = $UserAccount
    }

    return [PSCustomObject]@{
        ExecutionType     = $ExecutionType
        RequestedBy       = $RequestedBy
        InstalledBy       = $InstalledBy
        ClientApplication = $ClientApplicationId
        Evidence          = $Evidence
    }
}

function Get-RebootPending {
    $RebootCBS = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $RebootWU  = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $PendingRename = $null

    try {
        $PendingRename = (
            Get-ItemProperty `
                'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                -Name PendingFileRenameOperations `
                -ErrorAction SilentlyContinue
        ).PendingFileRenameOperations
    }
    catch {}

    return ($RebootCBS -or $RebootWU -or ($null -ne $PendingRename))
}

function Get-HResultHex {
    param([int64]$Value)

    $Unsigned = ($Value -band 0xFFFFFFFFL)
    return ('0x{0:X8}' -f $Unsigned)
}

$Mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList @($false, $MutexName)
$HasMutex = $false

try {
    Assert-Integrity
    $Config = Get-RuntimeConfig

    $MaxHistoryItems = 500

    if ($Config.MaxHistoryItems) {
        $MaxHistoryItems = [int]$Config.MaxHistoryItems
    }

    $HasMutex = $Mutex.WaitOne(0, $false)

    if (-not $HasMutex) {
        exit 0
    }

    $History = @(Get-WuaHistory -MaxItems $MaxHistoryItems)
    $CurrentKeys = @()

    foreach ($Entry in $History) {
        $CurrentKeys += Get-HistoryKey -Entry $Entry
    }

    if ($Initialize) {
        $Cutoff = (Get-Date).AddHours(-1 * $LookbackHours)
        $Processed = @()

        foreach ($Entry in $History) {
            if ($LookbackHours -eq 0 -or ([datetime]$Entry.Date) -lt $Cutoff) {
                $Processed += Get-HistoryKey -Entry $Entry
            }
        }

        Save-State -Keys $Processed -Reason "Initialize lookback=$LookbackHours"
        exit 0
    }

    if (-not (Test-Path -LiteralPath $StateFile)) {
        Save-State -Keys $CurrentKeys -Reason 'State recreated - missing'

        $Message = @"
==================================================================================================
 WINDOWS UPDATE - STATE RECRIADO
==================================================================================================
 Host.................: $env:COMPUTERNAME
 Execucao.............: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
 Motivo................: Arquivo de estado ausente
 Acao..................: Historico atual marcado como conhecido para evitar duplicidade
==================================================================================================
"@
        Write-EvidenceEvent -EventId 1002 -EntryType Information -Message $Message
        exit 0
    }

    try {
        $State = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
    }
    catch {
        Save-State -Keys $CurrentKeys -Reason 'State recreated - invalid JSON'

        $Message = @"
==================================================================================================
 WINDOWS UPDATE - STATE RECRIADO
==================================================================================================
 Host.................: $env:COMPUTERNAME
 Execucao.............: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
 Motivo................: Arquivo de estado invalido
 Acao..................: Historico atual marcado como conhecido para evitar duplicidade
==================================================================================================
"@
        Write-EvidenceEvent -EventId 1002 -EntryType Warning -Message $Message
        exit 0
    }

    if ([int]$State.Version -ne 1) {
        Save-State -Keys $CurrentKeys -Reason 'State recreated - incompatible version'
        exit 0
    }

    $ProcessedKeys = @($State.ProcessedKeys)
    $ProcessedMap = @{}

    foreach ($Key in $ProcessedKeys) {
        if ($Key) {
            $ProcessedMap[[string]$Key] = $true
        }
    }

    $NewEntries = @()

    foreach ($Entry in $History) {
        $Key = Get-HistoryKey -Entry $Entry

        if (-not $ProcessedMap.ContainsKey($Key)) {
            $NewEntries += $Entry
        }
    }

    $NewEntries = @($NewEntries | Sort-Object Date)

    foreach ($Entry in $NewEntries) {
        $Key = Get-HistoryKey -Entry $Entry
        $OS = Get-CimInstance Win32_OperatingSystem
        $CV = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $Build = "$($CV.CurrentBuild).$($CV.UBR)"
        $Title = [string]$Entry.Title

        $KB = '-'
        $KBMatch = [regex]::Match(
            $Title,
            'KB\d+',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($KBMatch.Success) {
            $KB = $KBMatch.Value
        }

        switch ([int]$Entry.Operation) {
            1 { $Operation = 'Installation' }
            2 { $Operation = 'Uninstallation' }
            default { $Operation = "Unknown ($($Entry.Operation))" }
        }

        switch ([int]$Entry.ResultCode) {
            0 {
                $Result    = 'Nao iniciado'
                $EntryType = [System.Diagnostics.EventLogEntryType]::Information
                $EventId   = 1104
            }
            1 {
                $Result    = 'Em andamento'
                $EntryType = [System.Diagnostics.EventLogEntryType]::Information
                $EventId   = 1104
            }
            2 {
                $Result    = 'Sucesso'
                $EntryType = [System.Diagnostics.EventLogEntryType]::Information
                $EventId   = 1100
            }
            3 {
                $Result    = 'Sucesso com erros'
                $EntryType = [System.Diagnostics.EventLogEntryType]::Warning
                $EventId   = 1101
            }
            4 {
                $Result    = 'Falhou'
                $EntryType = [System.Diagnostics.EventLogEntryType]::Error
                $EventId   = 1102
            }
            5 {
                $Result    = 'Cancelado'
                $EntryType = [System.Diagnostics.EventLogEntryType]::Warning
                $EventId   = 1103
            }
            default {
                $Result    = "Desconhecido ($($Entry.ResultCode))"
                $EntryType = [System.Diagnostics.EventLogEntryType]::Information
                $EventId   = 1104
            }
        }

        $Source = Get-UpdateSource -Entry $Entry
        $Actor  = Get-ActorEvidence -Entry $Entry
        $RebootPending = Get-RebootPending

        $UpdateId = '-'
        $Revision = '-'

        try {
            $UpdateId = [string]$Entry.UpdateIdentity.UpdateID
            $Revision = [string]$Entry.UpdateIdentity.RevisionNumber
        }
        catch {}

        $HResultHex = Get-HResultHex -Value ([int64]$Entry.HResult)

        $Message = @"
==================================================================================================
 WINDOWS UPDATE
==================================================================================================
 Host.................: $env:COMPUTERNAME
 Execucao.............: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')

 Atualizacao...........: $Title
 KB....................: $KB
 Data da operacao......: $(([datetime]$Entry.Date).ToString('dd/MM/yyyy HH:mm:ss'))
 Operacao..............: $Operation
 Resultado.............: $Result

 Tipo de execucao......: $($Actor.ExecutionType)
 Disparado por.........: $($Actor.ClientApplication)
 Solicitado por........: $($Actor.RequestedBy)
 Instalado por.........: $($Actor.InstalledBy)
 Evidencia.............: $($Actor.Evidence)
 Origem................: $Source

 Sistema...............: $($OS.Caption)
 Build observado.......: $Build
 Reboot pendente atual.: $RebootPending

 Update ID.............: $UpdateId
 Revisao...............: $Revision
 HResult...............: $HResultHex
 Coletor...............: $Version
==================================================================================================
"@

        Write-EvidenceEvent -EventId $EventId -EntryType $EntryType -Message $Message

        $ProcessedKeys += $Key
        $ProcessedMap[$Key] = $true
        Save-State -Keys $ProcessedKeys -Reason 'Normal'
    }

    exit 0
}
catch {
    $ErrorMessage = @"
==================================================================================================
 WINDOWS UPDATE - ERRO DO COLETOR
==================================================================================================
 Host.................: $env:COMPUTERNAME
 Execucao.............: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
 Erro..................: $($_.Exception.Message)
 Linha.................: $($_.InvocationInfo.ScriptLineNumber)
 Comando...............: $($_.InvocationInfo.Line)
 Coletor...............: $Version
==================================================================================================
"@

    try {
        Write-EvidenceEvent -EventId 1099 -EntryType Error -Message $ErrorMessage
    }
    catch {}

    exit 1
}
finally {
    if ($HasMutex) {
        try { $Mutex.ReleaseMutex() } catch {}
    }

    if ($Mutex) {
        $Mutex.Dispose()
    }
}
