# Instalação passo a passo

## 1. Pré-requisitos

Confirme:

- Windows PowerShell 5.1 disponível;
- execução como Administrador local;
- serviço de Task Scheduler funcional;
- Windows Update Agent disponível;
- permissão para criar Event Source no log Application.

O projeto não exige acesso à PowerShell Gallery nem instalação de módulos externos.

## 2. Obter o repositório

Clone ou baixe o repositório para uma pasta local.

Exemplo com Git:

```powershell
git clone <URL-DO-REPOSITORIO>
cd windows-update-evidence
```

## 3. Revisar os arquivos

Antes de executar em produção, revise pelo menos:

```text
install.ps1
src\Collector.ps1
src\Launcher.ps1
tools\Test-WindowsUpdateEvidence.ps1
```

## 4. Tratar Mark of the Web, se aplicável

Arquivos obtidos da Internet podem ser marcados pelo Windows.

Se a política do ambiente permitir scripts locais não assinados e o conteúdo já tiver sido revisado, é possível remover a marca com:

```powershell
Get-ChildItem -Path . -Recurse -Filter *.ps1 | Unblock-File
```

Não use isso para contornar uma política corporativa que exija assinatura de código.

## 5. Abrir PowerShell como Administrador

Use **Windows PowerShell**, não é necessário PowerShell 7.

## 6. Executar a instalação

Padrão:

```powershell
.\install.ps1
```

Com parâmetros:

```powershell
.\install.ps1 `
    -PollMinutes 5 `
    -InitialLookbackHours 24 `
    -MaxHistoryItems 500
```

### Parâmetros

| Parâmetro | Padrão | Objetivo |
|---|---:|---|
| `PollMinutes` | 5 | Intervalo da Scheduled Task |
| `InitialLookbackHours` | 24 | Quantas horas anteriores podem ser processadas na primeira execução |
| `MaxHistoryItems` | 500 | Máximo de entradas consultadas por ciclo |
| `InstallPath` | `%ProgramData%\WindowsUpdateEvidence` | Diretório protegido de runtime |

## 7. Validar a saída do instalador

O final esperado deve indicar:

```text
Quantidade de tasks..: 1
Resultado da task....: 0
Task action valida...: True
Task como SYSTEM.....: True
ACL protegida........: True
Integridade SHA256...: True
```

Se algum desses itens falhar, não trate a instalação como concluída.

## 8. Executar health check

```powershell
.\tools\Test-WindowsUpdateEvidence.ps1
```

Resultado esperado:

```text
Healthy : True
```

## 9. Validar no Event Viewer

Abra:

```text
Event Viewer
  Windows Logs
    Application
```

Filtre:

```text
Source = WindowsUpdateEvidence
```

Deve existir pelo menos o evento de configuração `1000`.

## 10. Aguardar novas operações do Windows Update

O coletor não força nenhuma atualização. Quando uma nova operação aparecer no histórico do Windows Update Agent, ela será registrada pelo próximo ciclo da Scheduled Task.

## 11. Atualizar uma instalação existente

Atualize os arquivos do repositório e execute novamente:

```powershell
.\install.ps1
```

O instalador:

- remove a task anterior com o mesmo nome;
- substitui os arquivos de runtime;
- recalcula os hashes;
- preserva o estado quando compatível;
- recria e testa a task.

## 12. Desinstalar

```powershell
.\uninstall.ps1
```

Para remover também a Event Source:

```powershell
.\uninstall.ps1 -RemoveEventSource
```

Os eventos históricos já existentes no log Application não são apagados.
