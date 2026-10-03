[CmdletBinding()]
param(
    [string]$InstallPath = "$env:ProgramData\WindowsUpdateEvidence",
    [switch]$RemoveEventSource
)

$ErrorActionPreference = 'Stop'

$TaskName    = 'Windows Update Evidence'
$EventSource = 'WindowsUpdateEvidence'

function Assert-Administrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $Identity

    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Execute o Windows PowerShell como Administrador.'
    }
}

Assert-Administrator

$Tasks = @(
    Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -eq $TaskName }
)

foreach ($Task in $Tasks) {
    if ($Task.State -eq 'Running') {
        Stop-ScheduledTask `
            -TaskName $Task.TaskName `
            -TaskPath $Task.TaskPath `
            -ErrorAction SilentlyContinue
    }

    Unregister-ScheduledTask `
        -TaskName $Task.TaskName `
        -TaskPath $Task.TaskPath `
        -Confirm:$false
}

if (Test-Path -LiteralPath $InstallPath) {
    Remove-Item -LiteralPath $InstallPath -Recurse -Force
}

if ($RemoveEventSource -and [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    Remove-EventLog -Source $EventSource
}

Write-Host ''
Write-Host 'Desinstalacao concluida.' -ForegroundColor Green
Write-Host "Task removida.........: $TaskName"
Write-Host "Diretorio removido....: $InstallPath"
Write-Host "Event Source removida.: $RemoveEventSource"
Write-Host ''
Write-Host 'Os eventos historicos ja gravados no log Application nao sao apagados.'
