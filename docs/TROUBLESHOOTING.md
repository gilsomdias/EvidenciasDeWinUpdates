# Troubleshooting

## `LastTaskResult` diferente de 0

Execute:

```powershell
.\tools\Test-WindowsUpdateEvidence.ps1
```

Depois filtre o Event Viewer por:

```text
Source = WindowsUpdateEvidence
```

Procure especialmente pelos IDs `1098` e `1099`.

## ExecutionPolicy bloqueando scripts

Consulte:

```powershell
Get-ExecutionPolicy -List
```

O projeto não usa `ExecutionPolicy Bypass`.

Se o ambiente exigir scripts assinados, assine os arquivos conforme a política corporativa em vez de contornar a política.

## Event ID 1098

Significa que pelo menos um arquivo protegido não corresponde ao hash registrado em `Integrity.json`.

A execução do coletor é bloqueada.

Não corrija apenas editando o hash manualmente. Revise a alteração e reinstale a versão confiável pelo `install.ps1`.

## Event ID 1099

Erro interno de launcher ou coletor.

O próprio evento registra mensagem, linha e contexto quando disponíveis.

## Nenhuma atualização aparece

Confirme primeiro se há nova operação no histórico do Windows Update.

O coletor não executa `Check for updates` e não cria atividade artificial.

Também confirme:

```powershell
Get-ScheduledTaskInfo -TaskName 'Windows Update Evidence'
```

## Atualização aparece, mas usuário não

Isso pode ser esperado.

O Windows frequentemente executa a instalação como `SYSTEM`, mesmo quando um usuário iniciou a ação pela interface.

Quando não existe evidência confiável de autoria humana, o coletor registra `Nao identificado`.

## A task foi alterada manualmente

Rode:

```powershell
.\tools\Test-WindowsUpdateEvidence.ps1
```

Se `TaskActionOK` for `False`, reinstale a versão revisada com:

```powershell
.\install.ps1
```

Lembre que um Administrador local pode alterar também o próprio mecanismo de validação. Para detecção forte, use monitoramento externo.
