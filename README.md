# Evidências do Windows Update

Este projeto registra no **Event Viewer** as atualizações processadas pelo Windows Update.

A ideia é simples: facilitar a identificação do que foi instalado, quando aconteceu, qual foi o resultado e, quando o Windows fornecer informação suficiente, se a execução foi automática ou manual e qual usuário esteve relacionado.

> O projeto **não procura, não baixa, não instala e não remove atualizações**. Ele apenas registra evidências do que já foi processado pelo Windows Update.

## O que ele registra

- atualização instalada ou removida;
- data e resultado da operação;
- KB e origem da atualização;
- execução automática ou manual, quando identificável;
- usuário relacionado à operação, quando houver evidência;
- conta que executou a instalação, quando identificável;
- build observado no momento da coleta;
- reboot pendente;
- Update ID, revisão e HResult.

## Como funciona

```text
Windows Update / Microsoft Update / WSUS
                  |
                  v
       Histórico do Windows Update
                  |
                  v
          Coletor PowerShell
                  |
                  v
       Event Viewer > Application
```

O coletor é executado por uma tarefa agendada e verifica periodicamente o histórico do Windows Update. Quando encontra uma nova operação, grava uma evidência padronizada no log `Application`.

## Como fica o registro no Event Viewer

Exemplo de uma atualização registrada:

```text
==================================================================================================
 WINDOWS UPDATE
==================================================================================================
 Host.................: SERVER01
 Execucao.............: 03/10/2026 16:50:00

 Atualizacao...........: Security Intelligence Update for Microsoft Defender Antivirus - KB2267602
 KB....................: KB2267602
 Data da operacao......: 03/10/2026 15:41:00
 Operacao..............: Installation
 Resultado.............: Sucesso

 Tipo de execucao......: Automatica
 Disparado por.........: AutomaticUpdates
 Solicitado por........: Nao identificado
 Instalado por.........: NT AUTHORITY\SYSTEM
 Evidencia.............: ClientApplicationID: AutomaticUpdates
 Origem................: Microsoft Update

 Sistema...............: Microsoft Windows Server
 Build observado.......: 26100.xxxxx
 Reboot pendente atual.: False

 Update ID.............: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
 Revisao...............: 1
 HResult...............: 0x00000000
==================================================================================================
```

Quando o Windows não fornece informação suficiente para identificar autoria ou tipo de execução, o projeto registra `Nao identificado` em vez de assumir uma informação sem evidência.

## Instalação

Abra o **Windows PowerShell como Administrador**, entre na pasta do projeto e execute:

```powershell
.\install.ps1
```

Padrão utilizado:

```text
Diretorio.............: C:\ProgramData\WindowsUpdateEvidence
Tarefa agendada.......: Windows Update Evidence
Event Log.............: Application
Event Source..........: WindowsUpdateEvidence
Intervalo.............: 5 minutos
Lookback inicial......: 24 horas
```

## Onde consultar

No Windows:

```text
Event Viewer
  > Windows Logs
    > Application
```

Filtre por:

```text
Source = WindowsUpdateEvidence
```

## Validação

Depois da instalação, execute:

```powershell
.\tools\Test-WindowsUpdateEvidence.ps1
```

O teste valida os principais pontos da instalação, como tarefa agendada, integridade dos arquivos, ACL, Event Source e estado do coletor.

## Compatibilidade

Projetado para ambientes com:

- Windows PowerShell 5.1;
- Windows Update Agent;
- Task Scheduler;
- Event Log clássico do Windows.

O foco principal é **Windows Server 2016 ou superior** e **Windows 10/11**.

## Segurança

O projeto protege os arquivos locais com ACL e validação de integridade por SHA256.

Esses controles ajudam contra alterações acidentais ou parciais, mas **não tornam o servidor inviolável contra um Administrador local**. Um administrador continua tendo capacidade de alterar tarefas, arquivos e permissões do próprio sistema.

Para cenários que exigem evidência mais resistente a alteração, consulte a documentação de hardening e considere controles externos como assinatura de código, WDAC/AppLocker, WEC ou SIEM.

## Documentação

Se precisar de mais detalhes, a documentação completa está separada por assunto:

- [Instalação](docs/INSTALLATION.md)
- [Arquitetura](docs/ARCHITECTURE.md)
- [Eventos gerados](docs/EVENTS.md)
- [Segurança e hardening](docs/HARDENING.md)
- [Validação](docs/VALIDATION.md)
- [Solução de problemas](docs/TROUBLESHOOTING.md)
- [Política de segurança](SECURITY.md)
