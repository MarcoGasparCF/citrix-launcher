# Registo de manutenção

Este documento regista problemas identificados, o seu diagnóstico e a resolução aplicada, para que possam ser reproduzidos por outra pessoa.

## Identificação das ocorrências

- Cada ocorrência tem um ID no formato `AAAA/NNN`: ano de identificação seguido de um número sequencial com três algarismos.
- A sequência começa em `001` em cada ano e aumenta a cada nova ocorrência. Não reutilize IDs.
- Registe cada problema numa secção própria, usando o ID e uma descrição curta no título.
- Associe cada nova ocorrência a um issue do repositório e registe a ligação no campo correspondente.
- Separe o erro observado, o diagnóstico, a resolução e a respetiva verificação.

## 2026/001 — Incompatibilidade entre o Edge e o EdgeDriver

### Registo

| Campo | Informação |
|---|---|
| Data | 23 de novembro de 2026 |
| Estado | Resolvido |
| Componente | Microsoft Edge e EdgeDriver |
| ID | `2026/001` |

### Erro observado

Ao executar `OpenCitrix.bat`, o launcher apresentou:

```text
Erro: O Edge e a versao 158 e o EdgeDriver e a versao 157. Instale o EdgeDriver correspondente ao Edge.
Feche todas as janelas do Edge antes de executar e confirme que o Citrix Workspace esta instalado.
```

### Diagnóstico

O launcher compara as versões principais do Microsoft Edge e do EdgeDriver e interrompe a execução se forem diferentes. Nesta ocorrência:

- Edge instalado: `158.0.4370.33`
- EdgeDriver incluído: `157.0.4341.42`

### Resolução aplicada

Foi descarregado diretamente da Microsoft o EdgeDriver oficial para Windows x64, versão `158.0.4370.33`. O ZIP e o executável extraído foram atualizados no pacote do projeto e na instalação ativa em `%USERPROFILE%\apps\CitrixLauncher`.

**Importante:** quando já existe, o launcher utiliza `WebDriver\edgedriver_win64\msedgedriver.exe` e não volta a extrair o executável do ZIP. Atualizar apenas `WebDriver\edgedriver_win64.zip` não corrige uma instalação que ainda tenha o executável antigo.

### Procedimento automatizado

O script [Atualizar-EdgeDriver.ps1](./scripts/2026-001/Atualizar-EdgeDriver.ps1) descarrega a versão oficial correspondente ao Edge, atualiza e verifica o ZIP e o executável no pacote do projeto e na instalação habitual `%USERPROFILE%\apps\CitrixLauncher`, se existir. No fim, inicia `OpenCitrix.bat`; o login pode pedir o OTP e abrir uma sessão Citrix.

Execute a partir da pasta do projeto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\maintenance\scripts\2026-001\Atualizar-EdgeDriver.ps1"
```

Para atualizar também outra cópia, passe a pasta dessa instalação:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\maintenance\scripts\2026-001\Atualizar-EdgeDriver.ps1" -AdditionalLauncherPath "D:\Caminho\CitrixLauncher"
```

Se forem encontrados processos Edge ou EdgeDriver, o script mostra os processos e pede a confirmação `FECHAR` antes de os terminar. Isto pode fechar separadores sem guardar dados ou interromper outras automatizações. Qualquer outra resposta cancela a atualização.

Cada execução acrescenta ao ficheiro [maintenance.log](./maintenance.log) a data/hora local com fuso horário, o ID da manutenção, um identificador da execução, a conta Windows que executou o script e a descrição de cada fase, incluindo cancelamentos e erros. O script exige que o log possa ser escrito antes de iniciar as alterações.

### Procedimento manual alternativo

1. **Feche o launcher e todas as janelas do Edge.** Se uma execução anterior tiver deixado um `msedgedriver.exe` ativo, feche apenas esse processo depois de confirmar que não está a ser usado por outra automação.

2. **Consulte a versão do Edge.** Abra `edge://settings/help` e anote a versão completa apresentada, por exemplo `158.0.4370.33`.

3. **Descarregue o EdgeDriver oficial correspondente.** Aceda à [página oficial do Microsoft Edge WebDriver](https://developer.microsoft.com/microsoft-edge/tools/webdriver/) e escolha a versão correspondente ao Edge instalado e a arquitetura Windows x64. Prefira a mesma versão completa; se não estiver disponível, confirme na documentação da Microsoft qual é a versão compatível com essa compilação. Não descarregue executáveis de sites de terceiros.

4. **Atualize os dois ficheiros em cada cópia do launcher que será executada:**
   - Substitua `WebDriver\edgedriver_win64.zip` pelo ZIP oficial.
   - Extraia `msedgedriver.exe` do ZIP e substitua `WebDriver\edgedriver_win64\msedgedriver.exe`.

   Faça isto na pasta do pacote/projeto e na pasta instalada, normalmente `%USERPROFILE%\apps\CitrixLauncher`. Se o launcher for executado de outra pasta, atualize essa cópia também. Confirme que o ZIP contém `msedgedriver.exe` na raiz.

5. **Verifique as versões no PowerShell**, ajustando `$base` para a pasta onde está o launcher:

   ```powershell
   $base = Join-Path $env:USERPROFILE 'apps\CitrixLauncher'
   $edgePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
   $driverPath = Join-Path $base 'WebDriver\edgedriver_win64\msedgedriver.exe'
   (Get-Item -LiteralPath $edgePath).VersionInfo.ProductVersion
   (Get-Item -LiteralPath $driverPath).VersionInfo.ProductVersion
   & $driverPath --version
   ```

   Confirme que o EdgeDriver é compatível com a versão instalada e que o comando `--version` apresenta a versão esperada.

6. **Execute `OpenCitrix.bat` novamente** a partir da cópia atualizada. O Citrix Workspace deve estar instalado e associado a ficheiros `.ica`.

### Verificação da resolução

O Edge e o EdgeDriver apresentaram ambos a versão `158.0.4370.33`, e o executável EdgeDriver respondeu corretamente ao comando `--version`.

## Modelo para novas ocorrências

Copie esta secção para o fim do documento e atribua o próximo ID sequencial do ano:

```markdown
## AAAA/NNN — Descrição curta do problema

### Registo

| Campo | Informação |
|---|---|
| Data | AAAA-MM-DD |
| Estado | Em investigação / Resolvido |
| Componente | Componente afetado |
| ID | `AAAA/NNN` |
| Issue do repositório (obrigatório) | [#NNN](https://github.com/MarcoGasparCF/citrix-launcher/issues/NNN) |

### Erro observado

Mensagem exata, sintomas e passos para reproduzir.

### Diagnóstico

Causa identificada e evidências relevantes.

### Resolução aplicada

Alterações efetuadas e ficheiros/configurações afetados.

### Procedimento manual

Passos numerados suficientes para outra pessoa diagnosticar e resolver o problema.

### Verificação da resolução

Testes efetuados e resultado esperado.
```
