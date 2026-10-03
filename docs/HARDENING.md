# Hardening

## Controles já aplicados

O instalador aplica automaticamente:

- Scheduled Task como `SYSTEM`;
- `RunLevel Highest`;
- sem `ExecutionPolicy Bypass`;
- ACL sem herança;
- Full Control somente para `SYSTEM` e `Administrators`;
- validação de Reparse Point;
- SHA256 dos arquivos de runtime;
- validação da ação da Scheduled Task;
- teste real da task após a instalação.

## O que ainda depende do ambiente

### 1. Code Signing

Em ambientes corporativos, assine os scripts com certificado de Code Signing e prefira política `AllSigned` quando aplicável.

### 2. WDAC ou AppLocker

Use allowlisting para restringir quais scripts e executáveis podem rodar no host.

### 3. Windows Event Forwarding

Encaminhe os eventos da source `WindowsUpdateEvidence` para um coletor central.

Isso evita que a única cópia da evidência permaneça no host que está sendo auditado.

### 4. SIEM

Crie alertas para:

- Event ID `1098`;
- Event ID `1099`;
- Event ID `1097`;
- alteração ou remoção da Scheduled Task;
- limpeza do log Application.

### 5. Auditoria de Scheduled Tasks

Considere habilitar auditoria corporativa para criação e alteração de tasks e encaminhar esses eventos para o sistema central.

## Por que o hash não basta contra Administrador local

O manifesto de hash está no mesmo host. Um Administrador local consegue alterar:

```text
arquivo + hash + task
```

Portanto, SHA256 local é útil para integridade operacional, mas não substitui uma raiz de confiança externa.
