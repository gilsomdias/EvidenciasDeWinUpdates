[CmdletBinding()]
param(
    [ValidateRange(1,60)]
    [int]$PollMinutes = 5,

    [ValidateRange(0,168)]
    [int]$InitialLookbackHours = 24,

    [ValidateRange(50,5000)]
    [int]$MaxHistoryItems = 500,

    [string]$InstallPath = "$env:ProgramData\WindowsUpdateEvidence"
)

$ErrorActionPreference = 'Stop'

$Version        = '1.0.0'
$TaskName       = 'Windows Update Evidence'
$TaskPath       = '\'
$EventSource    = 'WindowsUpdateEvidence'
$NativeLog      = 'Microsoft-Windows-WindowsUpdateClient/Operational'
$PowerShellExe  = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$SourcePath     = Join-Path $PSScriptRoot 'src'
$CollectorSrc   = Join-Path $SourcePath 'Collector.ps1'
$LauncherSrc    = Join-Path $SourcePath 'Launcher.ps1'
$Collector      = Join-Path $InstallPath 'Collector.ps1'
$Launcher       = Join-Path $InstallPath 'Launcher.ps1'
$ConfigFile     = Join-Path $InstallPath 'RuntimeConfig.json'
$IntegrityFile  = Join-Path $InstallPath 'Integrity.json'
$StateFile      = Join-Path $InstallPath 'WindowsUpdateHistoryState.json'

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

function Assert-Administrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $Identity

    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Execute o Windows PowerShell como Administrador.'
    }
}

function Assert-NoReparsePoint {
    param([string]$Path)

    $FullPath = [IO.Path]::GetFullPath($Path)
    $Cursor = $FullPath
    $Existing = @()

    while ($Cursor) {
        if (Test-Path -LiteralPath $Cursor) {
            $Existing += $Cursor
        }

        $Parent = Split-Path -Path $Cursor -Parent

        if ([string]::IsNullOrWhiteSpace($Parent) -or $Parent -eq $Cursor) {
            break
        }

        $Cursor = $Parent
    }

    foreach ($ItemPath in $Existing) {
        $Item = Get-Item -LiteralPath $ItemPath -Force

        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "O caminho '$ItemPath' e um ReparsePoint. Instalacao interrompida por seguranca."
        }
    }
}

function Set-SecureFolderAcl {
    param([string]$Path)

    $AdminsSid  = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-544'
    $SystemSid  = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-18'
    $AdminsAcct = $AdminsSid.Translate([System.Security.Principal.NTAccount])
    $SystemAcct = $SystemSid.Translate([System.Security.Principal.NTAccount])

    $Acl = New-Object System.Security.AccessControl.DirectorySecurity
    $Acl.SetOwner($AdminsAcct)
    $Acl.SetAccessRuleProtection($true, $false)

    $Inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $Propagation = [System.Security.AccessControl.PropagationFlags]::None
    $Allow       = [System.Security.AccessControl.AccessControlType]::Allow

    $AdminsRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
        $AdminsAcct,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $Inheritance,
        $Propagation,
        $Allow
    )

    $SystemRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
        $SystemAcct,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $Inheritance,
        $Propagation,
        $Allow
    )

    [void]$Acl.AddAccessRule($AdminsRule)
    [void]$Acl.AddAccessRule($SystemRule)

    Set-Acl -LiteralPath $Path -AclObject $Acl
}


function Set-SecureFileAcl {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $AdminsSid  = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-544'
    $SystemSid  = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-18'
    $AdminsAcct = $AdminsSid.Translate([System.Security.Principal.NTAccount])
    $SystemAcct = $SystemSid.Translate([System.Security.Principal.NTAccount])

    $Acl = New-Object System.Security.AccessControl.FileSecurity
    $Acl.SetOwner($AdminsAcct)
    $Acl.SetAccessRuleProtection($true, $false)

    $Allow = [System.Security.AccessControl.AccessControlType]::Allow

    $AdminsRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
        $AdminsAcct,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $Allow
    )

    $SystemRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
        $SystemAcct,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $Allow
    )

    [void]$Acl.AddAccessRule($AdminsRule)
    [void]$Acl.AddAccessRule($SystemRule)

    Set-Acl -LiteralPath $Path -AclObject $Acl
}

function Test-SecureAcl {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $AllowedSids = @('S-1-5-18', 'S-1-5-32-544')
    $Acl = Get-Acl -LiteralPath $Path

    foreach ($Rule in $Acl.Access) {
        if ($Rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
            continue
        }

        $RuleSid = try {
            $Rule.IdentityReference.Translate(
                [System.Security.Principal.SecurityIdentifier]
            ).Value
        }
        catch {
            $Rule.IdentityReference.Value
        }

        if ($AllowedSids -notcontains $RuleSid) {
            return $false
        }
    }

    return $true
}

function Get-AclValidation {
    param([string]$Path)

    $AllowedSids = @('S-1-5-18', 'S-1-5-32-544')
    $Acl = Get-Acl -LiteralPath $Path
    $UnexpectedAllow = @()

    foreach ($Rule in $Acl.Access) {
        if ($Rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
            continue
        }

        $RuleSid = try {
            $Rule.IdentityReference.Translate(
                [System.Security.Principal.SecurityIdentifier]
            ).Value
        }
        catch {
            $Rule.IdentityReference.Value
        }

        if ($AllowedSids -notcontains $RuleSid) {
            $UnexpectedAllow += $Rule
        }
    }

    return [PSCustomObject]@{
        InheritanceOff  = $Acl.AreAccessRulesProtected
        UnexpectedAllow = @($UnexpectedAllow)
    }
}

function Wait-TaskStop {
    param(
        [string]$Name,
        [string]$Path,
        [int]$TimeoutSeconds = 30
    )

    $Limit = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        $Task = Get-ScheduledTask -TaskName $Name -TaskPath $Path -ErrorAction SilentlyContinue

        if (-not $Task -or $Task.State -ne 'Running') {
            return
        }

        Start-Sleep -Milliseconds 500
    }
    while ((Get-Date) -lt $Limit)

    throw "A task '$Path$Name' continuou em execucao por mais de $TimeoutSeconds segundos."
}

function Remove-ExistingTasks {
    $ExistingTasks = @(
        Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -eq $TaskName }
    )

    foreach ($ExistingTask in $ExistingTasks) {
        if ($ExistingTask.State -eq 'Running') {
            Stop-ScheduledTask `
                -TaskName $ExistingTask.TaskName `
                -TaskPath $ExistingTask.TaskPath `
                -ErrorAction SilentlyContinue

            Wait-TaskStop -Name $ExistingTask.TaskName -Path $ExistingTask.TaskPath
        }

        Unregister-ScheduledTask `
            -TaskName $ExistingTask.TaskName `
            -TaskPath $ExistingTask.TaskPath `
            -Confirm:$false
    }
}

function New-IntegrityManifest {
    $Files = @(
        'Collector.ps1',
        'Launcher.ps1',
        'RuntimeConfig.json'
    )

    $Entries = @()

    foreach ($Name in $Files) {
        $Target = Join-Path $InstallPath $Name
        $Entries += [PSCustomObject]@{
            Name   = $Name
            SHA256 = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToUpperInvariant()
        }
    }

    [PSCustomObject]@{
        Version   = 1
        CreatedAt = (Get-Date).ToString('o')
        Files     = @($Entries)
    } |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $IntegrityFile -Encoding UTF8
}

function Test-InstalledIntegrity {
    if (-not (Test-Path -LiteralPath $IntegrityFile)) {
        return $false
    }

    try {
        $Manifest = Get-Content -LiteralPath $IntegrityFile -Raw | ConvertFrom-Json

        foreach ($Item in @($Manifest.Files)) {
            $Target = Join-Path $InstallPath ([string]$Item.Name)

            if (-not (Test-Path -LiteralPath $Target)) {
                return $false
            }

            $Actual = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToUpperInvariant()
            $Expected = ([string]$Item.SHA256).ToUpperInvariant()

            if ($Actual -ne $Expected) {
                return $false
            }
        }

        return $true
    }
    catch {
        return $false
    }
}

Assert-Administrator

if (-not (Test-Path -LiteralPath $PowerShellExe)) {
    throw "Windows PowerShell nao encontrado em '$PowerShellExe'."
}

if (-not (Test-Path -LiteralPath $CollectorSrc)) {
    throw "Arquivo fonte nao encontrado: $CollectorSrc"
}

if (-not (Test-Path -LiteralPath $LauncherSrc)) {
    throw "Arquivo fonte nao encontrado: $LauncherSrc"
}

$ResolvedInstallPath = [IO.Path]::GetFullPath($InstallPath)

if ($ResolvedInstallPath.StartsWith('\\')) {
    throw 'InstallPath deve apontar para um caminho local. Caminhos UNC nao sao suportados.'
}

Assert-NoReparsePoint -Path $ResolvedInstallPath
$InstallPath = $ResolvedInstallPath
$Collector   = Join-Path $InstallPath 'Collector.ps1'
$Launcher    = Join-Path $InstallPath 'Launcher.ps1'
$ConfigFile  = Join-Path $InstallPath 'RuntimeConfig.json'
$IntegrityFile = Join-Path $InstallPath 'Integrity.json'
$StateFile   = Join-Path $InstallPath 'WindowsUpdateHistoryState.json'

Write-Host ''
Write-Host '==================================================================================================' -ForegroundColor Cyan
Write-Host ' WINDOWS UPDATE EVIDENCE - INSTALACAO' -ForegroundColor Cyan
Write-Host '==================================================================================================' -ForegroundColor Cyan
Write-Host " Host.................: $env:COMPUTERNAME"
Write-Host " Versao...............: $Version"
Write-Host " Caminho..............: $InstallPath"
Write-Host " Intervalo............: $PollMinutes minuto(s)"
Write-Host " Lookback inicial.....: $InitialLookbackHours hora(s)"

if (-not (Test-Path -LiteralPath $InstallPath)) {
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
}

Assert-NoReparsePoint -Path $InstallPath
Set-SecureFolderAcl -Path $InstallPath

if ([System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    $ExistingLog = [System.Diagnostics.EventLog]::LogNameFromSourceName($EventSource, '.')

    if ($ExistingLog -ne 'Application') {
        throw "A source '$EventSource' ja existe vinculada ao log '$ExistingLog'."
    }
}
else {
    $SourceData = New-Object -TypeName System.Diagnostics.EventSourceCreationData -ArgumentList @($EventSource, 'Application')
    [System.Diagnostics.EventLog]::CreateEventSource($SourceData)
}

try {
    & "$env:SystemRoot\System32\wevtutil.exe" sl $NativeLog /e:true | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Nao foi possivel habilitar '$NativeLog'. A coleta principal continua funcionando, mas a correlacao de autoria pode ficar limitada."
    }
}
catch {
    Write-Warning "Nao foi possivel habilitar '$NativeLog'. A coleta principal continua funcionando, mas a correlacao de autoria pode ficar limitada."
}

Remove-ExistingTasks

Copy-Item -LiteralPath $CollectorSrc -Destination $Collector -Force
Copy-Item -LiteralPath $LauncherSrc -Destination $Launcher -Force

$RuntimeConfig = [PSCustomObject]@{
    Version         = 1
    PollMinutes     = $PollMinutes
    MaxHistoryItems = $MaxHistoryItems
    EventSource     = $EventSource
    TaskName        = $TaskName
}

$RuntimeConfig |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $ConfigFile -Encoding UTF8

New-IntegrityManifest
Set-SecureFolderAcl -Path $InstallPath

foreach ($RuntimeFile in @(
    $Collector,
    $Launcher,
    $ConfigFile,
    $IntegrityFile
)) {
    Set-SecureFileAcl -Path $RuntimeFile
}

$StateIsCompatible = $false

if (Test-Path -LiteralPath $StateFile) {
    try {
        $ExistingState = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        $StateIsCompatible = ([int]$ExistingState.Version -eq 1)
    }
    catch {
        $StateIsCompatible = $false
    }
}

if (-not $StateIsCompatible) {
    $InitArguments = "-NoLogo -NoProfile -NonInteractive -File `"$Launcher`" -Initialize -LookbackHours $InitialLookbackHours"

    $Init = Start-Process `
        -FilePath $PowerShellExe `
        -ArgumentList $InitArguments `
        -Wait `
        -PassThru

    if ($Init.ExitCode -ne 0) {
        throw "Falha ao inicializar o estado. ExitCode: $($Init.ExitCode). Verifique a ExecutionPolicy e os eventos da source '$EventSource'."
    }
}

Set-SecureFileAcl -Path $StateFile

$ExpectedArguments = "-NoLogo -NoProfile -NonInteractive -File `"$Launcher`""

$Action = New-ScheduledTaskAction `
    -Execute $PowerShellExe `
    -Argument $ExpectedArguments

$Trigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $PollMinutes)

$TaskPrincipal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest

$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -TaskPath $TaskPath `
    -Description "Windows Update Evidence v$Version - auditoria do historico do Windows Update Agent." `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $TaskPrincipal `
    -Settings $Settings `
    -Force |
Out-Null

$ConfigMessage = @"
==================================================================================================
 WINDOWS UPDATE - COLETOR CONFIGURADO
==================================================================================================
 Host.................: $env:COMPUTERNAME
 Execucao.............: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
 Versao...............: $Version

 Fonte principal.......: Historico do Windows Update Agent (WUA)
 Event Log.............: Application
 Source................: $EventSource
 Task..................: $TaskName
 Intervalo............: $PollMinutes minuto(s)
 Lookback inicial.....: $InitialLookbackHours hora(s)

 Procura updates?......: Nao
 Baixa updates?........: Nao
 Instala updates?......: Nao
 Reinicia o host?......: Nao
 ExecutionPolicy Bypass: Nao
 Conta da task.........: SYSTEM
 Integridade...........: SHA256 de arquivos de runtime
 ACL...................: SYSTEM e Administrators com Full Control
==================================================================================================
"@

Write-EvidenceEvent -EventId 1000 -EntryType Information -Message $ConfigMessage

Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath

$Limit = (Get-Date).AddSeconds(60)

do {
    Start-Sleep -Seconds 1
    $Task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
}
while ($Task.State -eq 'Running' -and (Get-Date) -lt $Limit)

if ($Task.State -eq 'Running') {
    throw 'A task de validacao permaneceu em execucao por mais de 60 segundos.'
}

$TaskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath

if ([int64]$TaskInfo.LastTaskResult -ne 0) {
    throw "A task foi criada, mas a execucao de teste falhou. LastTaskResult: $($TaskInfo.LastTaskResult)."
}

$TasksValidation = @(
    Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -eq $TaskName }
)

if ($TasksValidation.Count -ne 1) {
    throw "Validacao falhou. Foram encontradas $($TasksValidation.Count) tasks com o nome '$TaskName'."
}

$TaskValidation = $TasksValidation[0]
$ActionValidation = @($TaskValidation.Actions)[0]
$TaskActionOK = (
    $ActionValidation.Execute -ieq $PowerShellExe -and
    $ActionValidation.Arguments -eq $ExpectedArguments
)

$TaskPrincipalOK = (
    $TaskValidation.Principal.UserId -in @('SYSTEM', 'S-1-5-18', 'NT AUTHORITY\SYSTEM')
)

$AclValidation = Get-AclValidation -Path $InstallPath
$AclOK = (
    $AclValidation.InheritanceOff -and
    $AclValidation.UnexpectedAllow.Count -eq 0
)

$RuntimeAclOK = $true

foreach ($RuntimeFile in @(
    $Collector,
    $Launcher,
    $ConfigFile,
    $IntegrityFile,
    $StateFile
)) {
    if (-not (Test-SecureAcl -Path $RuntimeFile)) {
        $RuntimeAclOK = $false
        break
    }
}

$AclOK = ($AclOK -and $RuntimeAclOK)
$IntegrityOK = Test-InstalledIntegrity

if (-not $TaskActionOK) {
    throw 'Validacao final falhou: a acao da Scheduled Task nao corresponde ao launcher instalado.'
}

if (-not $TaskPrincipalOK) {
    throw 'Validacao final falhou: a Scheduled Task nao esta configurada para SYSTEM.'
}

if (-not $AclOK) {
    throw 'Validacao final falhou: a ACL do diretorio nao esta no padrao esperado.'
}

if (-not $IntegrityOK) {
    throw 'Validacao final falhou: hash de um ou mais arquivos de runtime divergente.'
}

$LastEvent = Get-WinEvent -FilterHashtable @{
    LogName      = 'Application'
    ProviderName = $EventSource
} -MaxEvents 1

Write-Host ''
Write-Host '==================================================================================================' -ForegroundColor Cyan
Write-Host ' CONFIGURACAO FINALIZADA E VALIDADA' -ForegroundColor Cyan
Write-Host '==================================================================================================' -ForegroundColor Cyan
Write-Host " Host.................: $env:COMPUTERNAME"
Write-Host " Versao...............: $Version"
Write-Host " Task.................: $($TaskValidation.TaskPath)$($TaskValidation.TaskName)"
Write-Host " Quantidade de tasks..: $($TasksValidation.Count)"
Write-Host " Task status..........: $($TaskValidation.State)"
Write-Host " Ultima execucao......: $($TaskInfo.LastRunTime)"
Write-Host " Resultado da task....: $($TaskInfo.LastTaskResult)"
Write-Host " Proxima execucao.....: $($TaskInfo.NextRunTime)"
Write-Host " Task action valida...: $TaskActionOK"
Write-Host " Task como SYSTEM.....: $TaskPrincipalOK"
Write-Host " ACL protegida........: $AclOK"
Write-Host " Integridade SHA256...: $IntegrityOK"
Write-Host " Event Log............: Application"
Write-Host " Source...............: $EventSource"
Write-Host " Ultimo Event ID......: $($LastEvent.Id)"
Write-Host " Ultimo evento........: $($LastEvent.TimeCreated)"
Write-Host '==================================================================================================' -ForegroundColor Cyan
