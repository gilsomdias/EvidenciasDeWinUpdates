# Eventos gerados

Todos os eventos são gravados em:

```text
Log    : Application
Source : WindowsUpdateEvidence
```

## IDs

| Event ID | Tipo | Significado |
|---:|---|---|
| 1000 | Information | Coletor configurado |
| 1001 | Information | Health check saudável |
| 1002 | Information/Warning | Estado local recriado |
| 1097 | Warning | Health check encontrou problema |
| 1098 | Error | Falha de integridade SHA256 |
| 1099 | Error | Erro interno do launcher/coletor |
| 1100 | Information | Operação concluída com sucesso |
| 1101 | Warning | Operação concluída com erros |
| 1102 | Error | Operação falhou |
| 1103 | Warning | Operação cancelada |
| 1104 | Information | Outro estado do WUA |

## Exemplo de evento

```text
==================================================================================================
 WINDOWS UPDATE
==================================================================================================
 Host.................: HOSTNAME
 Execucao.............: 03/10/2026 18:00:00

 Atualizacao...........: <titulo informado pelo Windows Update Agent>
 KB....................: KB1234567
 Data da operacao......: 03/10/2026 17:55:00
 Operacao..............: Installation
 Resultado.............: Sucesso

 Tipo de execucao......: Automatica
 Disparado por.........: AutomaticUpdates
 Solicitado por........: Nao identificado
 Instalado por.........: NT AUTHORITY\SYSTEM
 Evidencia.............: ClientApplicationID: AutomaticUpdates
 Origem................: Microsoft Update

 Sistema...............: <sistema operacional>
 Build observado.......: <build atual>
 Reboot pendente atual.: False

 Update ID.............: <GUID>
 Revisao...............: 1
 HResult...............: 0x00000000
 Coletor...............: 1.0.0
==================================================================================================
```

## Interpretação de autoria

### `Tipo de execucao`

Pode ser:

```text
Automatica
Manual (evidencia de usuario)
Nao identificado
```

### `Disparado por`

Vem principalmente de `ClientApplicationID` do Windows Update Agent.

### `Solicitado por`

Usuário humano correlacionado com evento nativo próximo à operação, quando houver evidência.

### `Instalado por`

Conta associada ao evento nativo. Muitas operações são efetivamente executadas por `SYSTEM`, mesmo quando iniciadas por um usuário.

### `Evidencia`

Expõe a evidência usada na classificação para facilitar auditoria posterior.
