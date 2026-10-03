# Validação do pacote

Checklist recomendado antes de cada release.

## Funcional

- [ ] `install.ps1` executa como Administrador.
- [ ] Scheduled Task é criada uma única vez.
- [ ] Task executa como `SYSTEM`.
- [ ] `LastTaskResult` retorna `0`.
- [ ] Event Source `WindowsUpdateEvidence` existe no log `Application`.
- [ ] Evento `1000` é criado na instalação.
- [ ] `tools/Test-WindowsUpdateEvidence.ps1` retorna `Healthy : True`.
- [ ] Nova operação do WUA gera evento `1100`, `1101`, `1102`, `1103` ou `1104`.

## Segurança

- [ ] Nenhum script usa `ExecutionPolicy Bypass`.
- [ ] Diretório de runtime tem ACL restrita.
- [ ] Hashes SHA256 estão válidos.
- [ ] Ação da Scheduled Task aponta para `Launcher.ps1`.
- [ ] Não existem Reparse Points no caminho de instalação.
- [ ] Não existem segredos ou credenciais no repositório.
- [ ] Limitação contra Administrador local está documentada.

## Privacidade

- [ ] Nenhum nome de empresa está codificado.
- [ ] Nenhum hostname real está codificado.
- [ ] Nenhum endereço IP real está codificado.
- [ ] Nenhum domínio corporativo está codificado.
- [ ] Nenhum usuário real está codificado.

## Escopo

- [ ] Collector não chama download de update.
- [ ] Collector não chama instalação de update.
- [ ] Collector não força scan do Windows Update.
- [ ] Collector não reinicia o host.
