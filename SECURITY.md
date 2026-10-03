# Segurança

## Objetivo dos controles locais

A instalação aplica alguns controles para reduzir alterações acidentais e dificultar modificações por contas sem privilégio:

- execução da Scheduled Task como `SYSTEM`;
- sem `ExecutionPolicy Bypass`;
- diretório com herança de ACL desabilitada;
- Full Control somente para `SYSTEM` e `Administrators`;
- recusa de instalação em caminho identificado como Reparse Point;
- SHA256 dos arquivos de runtime;
- validação da ação configurada na Scheduled Task;
- validação manual por `tools/Test-WindowsUpdateEvidence.ps1`.

## O que o SHA256 protege

Se apenas um arquivo protegido for alterado e o manifesto permanecer intacto, o launcher detecta a divergência e não executa o coletor.

Exemplo:

```text
Collector.ps1 alterado
        ↓
SHA256 diferente do Integrity.json
        ↓
Launcher bloqueia a execução
        ↓
Event ID 1098
```

## Limite de segurança importante

Esses controles **não impedem um Administrador local malicioso ou comprometido** de contornar o mecanismo.

Um Administrador local pode, por exemplo:

- alterar a Scheduled Task para executar outro comando;
- alterar o launcher;
- alterar o coletor e o manifesto de hashes ao mesmo tempo;
- mudar ACLs;
- apagar ou limpar o Event Viewer;
- desabilitar a task.

Nenhum hash armazenado no mesmo host consegue criar uma raiz de confiança contra quem administra esse próprio host.

## Recomendações para ambientes de maior criticidade

Para elevar a confiança da evidência:

1. assine os scripts com certificado corporativo de Code Signing;
2. utilize `AllSigned`, WDAC ou AppLocker conforme a política da organização;
3. monitore criação e alteração da Scheduled Task via auditoria central;
4. encaminhe os eventos para WEC ou SIEM;
5. restrinja e monitore o grupo local Administrators;
6. monitore alterações no diretório de instalação;
7. mantenha o repositório em controle de versão e revisão por pull request.

## Evidência de autoria

O projeto tenta correlacionar usuário, `ClientApplicationID` e eventos nativos do Windows.

Isso não significa que toda atualização terá um usuário humano identificável. Uma operação iniciada manualmente pode ser executada tecnicamente por `SYSTEM`.

Por isso o evento separa:

```text
Tipo de execucao
Disparado por
Solicitado por
Instalado por
Evidencia
```

Quando não há evidência suficiente, o valor permanece `Nao identificado`.
