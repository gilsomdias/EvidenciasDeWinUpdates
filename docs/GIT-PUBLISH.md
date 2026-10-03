# Publicar no Git

## 1. Copiar a pasta do projeto

Use a pasta `windows-update-evidence` como raiz do repositório.

## 2. Revisar o conteúdo

Antes do primeiro commit:

```powershell
Get-ChildItem -Recurse
```

Confirme que não existem arquivos de runtime, logs, nomes de hosts, endereços IP ou dados específicos do seu ambiente.

## 3. Inicializar o repositório

```powershell
git init
```

## 4. Conferir o que será versionado

```powershell
git status
```

## 5. Adicionar os arquivos

```powershell
git add .
```

## 6. Criar o primeiro commit

```powershell
git commit -m "Initial release of Windows Update Evidence"
```

## 7. Adicionar o repositório remoto

```powershell
git remote add origin <URL-DO-REPOSITORIO>
```

## 8. Publicar

```powershell
git branch -M main
git push -u origin main
```

## 9. Validar o GitHub Actions

O workflow `.github/workflows/validate.yml` faz parse de todos os arquivos `.ps1` em um runner Windows.

Depois do push, confirme que o workflow **Validate PowerShell** terminou com sucesso.

## 10. Definir licença

Este pacote não inclui uma licença pré-escolhida. Defina a licença adequada antes de tornar o repositório público, caso seja necessário para o seu uso.
