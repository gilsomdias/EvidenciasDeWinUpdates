param(
    [switch]$Initialize,
    [ValidateRange(0,168)]
    [int]$LookbackHours = 0
)

$ErrorActionPreference = 'Stop'

$BasePath      = $PSScriptRoot
$Collector     = Join-Path $BasePath 'Collector.ps1'
$ConfigFile    = Join-Path $BasePath 'RuntimeConfig.json'
$IntegrityFile = Join-Path $BasePath 'Integrity.json'
$EventSource   = 'WindowsUpdateEvidence'

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

function Get-IntegrityManifest {
    if (-not (Test-Path -LiteralPath $IntegrityFile)) {
        throw 'Arquivo de integridade nao encontrado.'
    }

    return (Get-Content -LiteralPath $IntegrityFile -Raw | ConvertFrom-Json)
}

function Assert-Integrity {
    $Manifest = Get-IntegrityManifest

    foreach ($Item in @($Manifest.Files)) {
        $Target = Join-Path $BasePath ([string]$Item.Name)

        if (-not (Test-Path -LiteralPath $Target)) {
            throw "Arquivo protegido nao encontrado: $($Item.Name)"
        }

        $Actual = (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToUpperInvariant()
        $Expected = ([string]$Item.SHA256).ToUpperInvariant()

        if ($Actual -ne $Expected) {
            $Message = @"
==================================================================================================
 WINDOWS UPDATE - FALHA DE INTEGRIDADE
==================================================================================================
 Host.................: $env:COMPUTERNAME
 Execucao.............: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
 Resultado............: COLETOR NAO EXECUTADO
 Arquivo...............: $($Item.Name)
 Motivo................: Hash SHA256 divergente
 Hash esperado.........: $Expected
 Hash encontrado.......: $Actual
==================================================================================================
"@
            Write-EvidenceEvent -EventId 1098 -EntryType Error -Message $Message
            exit 10
        }
    }
}

try {
    Assert-Integrity

    if (-not (Test-Path -LiteralPath $Collector)) {
        throw 'Collector.ps1 nao encontrado.'
    }

    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        throw 'RuntimeConfig.json nao encontrado.'
    }

    if ($Initialize) {
        & $Collector -Initialize -LookbackHours $LookbackHours
    }
    else {
        & $Collector
    }

    if ($null -ne $LASTEXITCODE) {
        exit $LASTEXITCODE
    }

    exit 0
}
catch {
    $Message = @"
==================================================================================================
 WINDOWS UPDATE - ERRO DO LAUNCHER
==================================================================================================
 Host.................: $env:COMPUTERNAME
 Execucao.............: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
 Erro..................: $($_.Exception.Message)
==================================================================================================
"@

    try {
        Write-EvidenceEvent -EventId 1099 -EntryType Error -Message $Message
    }
    catch {}

    exit 11
}
