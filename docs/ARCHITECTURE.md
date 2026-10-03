# Arquitetura

## Fluxo principal

```text
Windows Update / Microsoft Update / WSUS
                |
                v
      Windows Update Agent (WUA)
                |
                v
        Historico de updates
                |
                v
          Collector.ps1
                |
      +---------+---------+
      |                   |
      v                   v
correlacao de         estado local
Event Viewer          anti-duplicidade
      |
      v
Application Log
Source: WindowsUpdateEvidence
```

## Scheduled Task

A task executa:

```text
powershell.exe
  -> Launcher.ps1
      -> valida Integrity.json
      -> valida hashes
      -> executa Collector.ps1
```

## Arquivos de runtime

No diretório padrão:

```text
C:\ProgramData\WindowsUpdateEvidence
```

são criados:

```text
Collector.ps1
Launcher.ps1
RuntimeConfig.json
Integrity.json
WindowsUpdateHistoryState.json
```

## Responsabilidades

### Launcher.ps1

- valida os hashes dos arquivos protegidos;
- bloqueia execução quando encontra divergência;
- chama o coletor.

### Collector.ps1

- consulta o histórico do WUA;
- identifica novas entradas;
- tenta correlacionar autoria;
- registra eventos no Application;
- atualiza o estado.

### RuntimeConfig.json

Armazena parâmetros de runtime, como máximo de itens do histórico.

### Integrity.json

Armazena SHA256 de:

- `Collector.ps1`;
- `Launcher.ps1`;
- `RuntimeConfig.json`.

### WindowsUpdateHistoryState.json

Mantém as chaves já processadas para evitar duplicidade de eventos.

## Limite da arquitetura

Todos os componentes de confiança residem no mesmo host. Portanto, o projeto detecta alterações parciais e acidentais, mas não é uma raiz de confiança contra Administrador local.

Para evidência mais forte, envie os eventos para um sistema externo.
