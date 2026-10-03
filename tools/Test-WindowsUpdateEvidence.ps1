[CmdletBinding()]
param(
    [string]$InstallPath = "$env:ProgramData\WindowsUpdateEvidence",
    [switch]$LogEvent
)

$ErrorActionPreference = 'Stop'

$TaskName      = 'Windows Update Evidence'
$TaskPath      = '\'
$EventSource   = 'WindowsUpdateEvidence'
$PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$Launcher      = Join-Path $InstallPath 'Launcher.ps1'
$IntegrityFile = Join-Path $InstallPath 'Integrity.json'
$StateFile     = Join-Path $InstallPath 'WindowsUpdateHistoryState.json'
$Collector     = Join-Path $InstallPath 'Collector.ps1'
$ConfigFile    = Join-Path $InstallPath 'RuntimeConfig.json'
$ExpectedArgs  = "-NoLogo -NoProfile -NonInteractive -File `"$Launcher`""

function Get-IntegrityStatus {
    if (-not (Test-Path -LiteralPath $IntegrityFile)) {
        return [PSCustomObject]@{
            OK      = $false
            Details = 'Integrity.json nao encontrado'
        }
    }

    try {
        $Manifest = Get-Content -LiteralPath $IntegrityFile -Raw | ConvertFrom-Json
        $Failures = @()

        foreach ($Item in @($Manifest.Files)) {
            $Target = Join-Path $InstallPath ([string]$Item.Name)

            if (-not (Test-Path -LiteralPath $Target)) {
                $Failures += "$($Item.Name): ausente"
                continue
            }

            $Actual = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToUpperInvariant()
            $Expected = ([string]$Item.SHA256).ToUpperInvariant()

            if ($Actual -ne $Expected) {
                $Failures += "$($Item.Name): hash divergente"
            }
        }

        return [PSCustomObject]@{
            OK      = ($Failures.Count -eq 0)
            Details = if ($Failures.Count -eq 0) { 'OK' } else { $Failures -join '; ' }
        }
    }
    catch {
        return [PSCustomObject]@{
            OK      = $false
            Details = $_.Exception.Message
        }
    }
}

function Get-AclStatus {
    if (-not (Test-Path -LiteralPath $InstallPath)) {
        return [PSCustomObject]@{
            OK      = $false
            Details = 'Diretorio de instalacao nao encontrado'
        }
    }

    $AllowedSids = @('S-1-5-18', 'S-1-5-32-544')
    $Acl = Get-Acl -LiteralPath $InstallPath
    $Unexpected = @()

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
            $Unexpected += $RuleSid
        }
    }

    $ProtectionOK = (-not $RequireProtected) -or $Acl.AreAccessRulesProtected
    $OK = $ProtectionOK -and $Unexpected.Count -eq 0

    return [PSCustomObject]@{
        OK      = $OK
        Details = if ($OK) { 'OK' } else { "HerancaOff=$($Acl.AreAccessRulesProtected); Permissoes inesperadas=$($Unexpected -join ', ')" }
    }
}

$Integrity = Get-IntegrityStatus
$Acl = Get-AclStatus -Path $InstallPath -RequireProtected
$RuntimeAclFailures = @()

foreach ($RuntimeFile in @(
    $Collector,
    $Launcher,
    $ConfigFile,
    $IntegrityFile,
    $StateFile
)) {
    $FileAcl = Get-AclStatus -Path $RuntimeFile

    if (-not $FileAcl.OK) {
        $RuntimeAclFailures += "$(Split-Path -Leaf $RuntimeFile): $($FileAcl.Details)"
    }
}

if ($RuntimeAclFailures.Count -gt 0) {
    $Acl = [PSCustomObject]@{
        OK      = $false
        Details = $RuntimeAclFailures -join '; '
    }
}

$Task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
$TaskInfo = $null
$TaskExists = ($null -ne $Task)
$TaskActionOK = $false
$TaskPrincipalOK = $false
$TaskResultOK = $false

if ($TaskExists) {
    $TaskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath
    $Action = @($Task.Actions)[0]

    $TaskActionOK = (
        $Action.Execute -ieq $PowerShellExe -and
        $Action.Arguments -eq $ExpectedArgs
    )

    $TaskPrincipalOK = (
        $Task.Principal.UserId -in @('SYSTEM', 'S-1-5-18', 'NT AUTHORITY\SYSTEM')
    )

    $TaskResultOK = ([int64]$TaskInfo.LastTaskResult -eq 0)
}

$EventSourceOK = $false

if ([System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    $EventSourceOK = (
        [System.Diagnostics.EventLog]::LogNameFromSourceName($EventSource, '.') -eq 'Application'
    )
}

$StateOK = $false

if (Test-Path -LiteralPath $StateFile) {
    try {
        $State = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        $StateOK = ([int]$State.Version -eq 1)
    }
    catch {
        $StateOK = $false
    }
}

$OverallOK = (
    $Integrity.OK -and
    $Acl.OK -and
    $TaskExists -and
    $TaskActionOK -and
    $TaskPrincipalOK -and
    $TaskResultOK -and
    $EventSourceOK -and
    $StateOK
)

$Result = [PSCustomObject]@{
    Host               = $env:COMPUTERNAME
    Healthy            = $OverallOK
    IntegrityOK        = $Integrity.OK
    IntegrityDetails   = $Integrity.Details
    AclOK              = $Acl.OK
    AclDetails         = $Acl.Details
    TaskExists         = $TaskExists
    TaskActionOK       = $TaskActionOK
    TaskPrincipalOK    = $TaskPrincipalOK
    LastTaskResultOK   = $TaskResultOK
    LastTaskResult     = if ($TaskInfo) { $TaskInfo.LastTaskResult } else { $null }
    LastRunTime        = if ($TaskInfo) { $TaskInfo.LastRunTime } else { $null }
    NextRunTime        = if ($TaskInfo) { $TaskInfo.NextRunTime } else { $null }
    EventSourceOK      = $EventSourceOK
    StateOK            = $StateOK
}

$Result | Format-List

if ($LogEvent -and [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    $EntryType = if ($OverallOK) {
        [System.Diagnostics.EventLogEntryType]::Information
    }
    else {
        [System.Diagnostics.EventLogEntryType]::Warning
    }

    $EventId = if ($OverallOK) { 1001 } else { 1097 }

    $Message = @"
==================================================================================================
 WINDOWS UPDATE EVIDENCE - HEALTH CHECK
==================================================================================================
 Host.................: $env:COMPUTERNAME
 Execucao.............: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
 Saudavel..............: $OverallOK
 Integridade...........: $($Integrity.OK)
 ACL...................: $($Acl.OK)
 Task existe...........: $TaskExists
 Task action valida....: $TaskActionOK
 Task como SYSTEM......: $TaskPrincipalOK
 LastTaskResult OK.....: $TaskResultOK
 Event Source..........: $EventSourceOK
 State.................: $StateOK
==================================================================================================
"@

    [System.Diagnostics.EventLog]::WriteEntry(
        $EventSource,
        $Message,
        $EntryType,
        $EventId
    )
}

if ($OverallOK) {
    exit 0
}

exit 2
