# Windows Update Evidence

Coletor genérico de evidências do **Windows Update Agent (WUA)** para Windows.

O projeto registra no **Event Viewer > Windows Logs > Application** as operações encontradas no histórico do Windows Update, incluindo, quando disponível:

- atualização instalada ou removida;
- data da operação;
- resultado;
- KB;
- origem da atualização, como Windows Update, Microsoft Update ou WSUS;
- `ClientApplicationID`;
- indício de execução automática ou manual;
- usuário relacionado à operação, quando houver evidência confiável;
- conta que efetivamente executou a instalação, quando identificável;
- build observado no momento da coleta;
- estado atual de reboot pendente;
- Update ID, revisão e HResult.

> O coletor **não procura, não baixa, não instala e não remove atualizações**. Ele somente audita o histórico já registrado pelo Windows Update Agent.

## Compatibilidade

Projetado para ambientes Windows com:

- Windows PowerShell 5.1;
- Windows Update Agent;
- Task Scheduler;
- Event Log clássico do Windows.

O desenho é adequado para Windows Server 2016 ou superior e Windows 10/11. Versões anteriores podem funcionar, mas não fazem parte do escopo principal deste repositório.

## Estrutura do repositório

```text
windows-update-evidence/
├── README.md
├── SECURITY.md
├── CHANGELOG.md
├── .gitignore
├── .gitattributes
├── .editorconfig
├── .github/
│   └── workflows/
│       └── validate.yml
├── install.ps1
├── uninstall.ps1
├── src/
│   ├── Collector.ps1
│   └── Launcher.ps1
├── tools/
│   └── Test-WindowsUpdateEvidence.ps1
└── docs/
    ├── INSTALLATION.md
    ├── GIT-PUBLISH.md
    ├── ARCHITECTURE.md
    ├── EVENTS.md
    ├── HARDENING.md
    ├── TROUBLESHOOTING.md
    └── VALIDATION.md
```

## Instalação rápida

Abra o **Windows PowerShell como Administrador**, entre na pasta do repositório e execute:

```powershell
.\install.ps1
```

Padrões utilizados:

```text
Diretório.............: C:\ProgramData\WindowsUpdateEvidence
Scheduled Task........: Windows Update Evidence
Event Log.............: Application
Event Source..........: WindowsUpdateEvidence
Intervalo.............: 5 minutos
Lookback inicial......: 24 horas
```

Para alterar os parâmetros:

```powershell
.\install.ps1 -PollMinutes 10 -InitialLookbackHours 48 -MaxHistoryItems 1000
```

## O que o instalador faz

1. valida execução administrativa;
2. valida que o diretório de instalação não usa Reparse Point;
3. cria o diretório protegido;
4. remove herança de ACL do diretório;
5. permite Full Control somente para `SYSTEM` e `Administrators`;
6. cria a Event Source `WindowsUpdateEvidence` no log `Application`;
7. tenta habilitar o log operacional do Windows Update para enriquecer a correlação de autoria;
8. copia o `Collector.ps1` e o `Launcher.ps1` para a área protegida;
9. cria `RuntimeConfig.json`;
10. gera `Integrity.json` com SHA256 dos arquivos de runtime;
11. inicializa o estado do histórico;
12. cria a Scheduled Task executada como `SYSTEM`;
13. executa uma validação real da task;
14. valida ação da task, conta, ACL e hashes;
15. grava um evento `1000` indicando que o coletor foi configurado.

## Validação manual

Execute:

```powershell
.\tools\Test-WindowsUpdateEvidence.ps1
```

Para também registrar o resultado do health check no Event Viewer:

```powershell
.\tools\Test-WindowsUpdateEvidence.ps1 -LogEvent
```

Um ambiente saudável deve retornar principalmente:

```text
Healthy              : True
IntegrityOK          : True
AclOK                : True
TaskExists           : True
TaskActionOK         : True
TaskPrincipalOK      : True
LastTaskResultOK     : True
EventSourceOK        : True
StateOK              : True
```

## Onde consultar os eventos

Abra:

```text
Event Viewer
  Windows Logs
    Application
```

Filtre por:

```text
Source = WindowsUpdateEvidence
```

Os principais Event IDs estão documentados em [docs/EVENTS.md](docs/EVENTS.md).

## Atualização do projeto

Para atualizar uma instalação existente:

1. atualize o repositório;
2. revise as alterações;
3. execute novamente `install.ps1` como Administrador;
4. rode o health check;
5. confirme `LastTaskResult = 0`.

O instalador recria a task e os hashes usando os arquivos atuais do repositório. O arquivo de estado é preservado quando compatível.

## Desinstalação

```powershell
.\uninstall.ps1
```

Por padrão, a Event Source é mantida para preservar o contexto dos eventos históricos.

Para removê-la também:

```powershell
.\uninstall.ps1 -RemoveEventSource
```

Os eventos já existentes no log `Application` não são apagados pelo desinstalador.

## Execução manual x automática

A classificação é baseada em evidências disponíveis no Windows Update Agent e em eventos nativos próximos ao horário da operação.

Exemplos:

```text
Tipo de execucao......: Automatica
Disparado por.........: AutomaticUpdates
```

ou:

```text
Tipo de execucao......: Manual (evidencia de usuario)
Solicitado por........: DOMAIN\user
```

Quando o Windows não fornece informação suficiente:

```text
Tipo de execucao......: Nao identificado
```

Isso é intencional. O projeto prefere registrar `Nao identificado` a atribuir autoria sem evidência.

## Segurança

O projeto inclui controles locais de hardening, mas **não cria uma fronteira de segurança contra um Administrador local**.

Um Administrador local pode, por definição, alterar Scheduled Tasks, ACLs, arquivos e o próprio manifesto de hash. O SHA256 protege principalmente contra alteração acidental, corrupção e modificações parciais.

Para ambientes que exigem evidência resistente a Administrador local, combine o projeto com controles externos, como:

- assinatura de código;
- WDAC ou AppLocker;
- GPO;
- Windows Event Forwarding;
- SIEM;
- monitoramento central da Scheduled Task.

Leia [SECURITY.md](SECURITY.md) e [docs/HARDENING.md](docs/HARDENING.md) antes de tratar os eventos locais como evidência imutável.

## Privacidade

O repositório não contém nomes de empresas, hosts, endereços IP, domínios ou caminhos específicos de um ambiente.

Durante a execução, os eventos locais podem naturalmente registrar:

- hostname do computador;
- nome da atualização;
- domínio/usuário, quando correlacionável;
- origem WSUS, caso configurada no host.

Esses dados vêm do próprio ambiente em tempo de execução e não estão codificados no projeto.

## Publicação no Git

O passo a passo para inicializar e publicar o repositório está em [docs/GIT-PUBLISH.md](docs/GIT-PUBLISH.md).
