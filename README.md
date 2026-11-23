# Citrix Launcher

Configure `CITRIX_USERNAME` no ficheiro `.env` e execute `OpenCitrix.bat`. Com uma password protegida configurada, o script usa um perfil Edge temporario e pede apenas o OTP.

## Instruções de instalação

1. Extraia o ZIP para uma pasta temporária fora de `%USERPROFILE%\apps\`.
2. Execute [Instalar.bat](./Instalar.bat), mantendo-o junto dos restantes ficheiros do pacote.
3. Introduza o nome de utilizador e, quando for pedida, a palavra-passe do Citrix.
4. Após a confirmação da instalação, execute o atalho `CitrixLauncher` no ambiente de trabalho ou [OpenCitrix.bat](./OpenCitrix.bat) em `%USERPROFILE%\apps\CitrixLauncher\`.

O instalador cria a pasta `%USERPROFILE%\apps\CitrixLauncher`, copia os ficheiros do pacote, grava `CITRIX_USERNAME` no `.env` e cria ou atualiza o atalho `CitrixLauncher` no ambiente de trabalho e `UpdatePassword.lnk` na pasta da aplicação, com os respetivos ícones. Mantém as outras definições de um `.env` já instalado e não copia a palavra-passe do pacote. A palavra-passe é pedida pelo [updatePassword.bat](./updatePassword.bat) e protegida pelo Windows.

## Atualizar a password

Depois de mudar a password da conta da empresa, execute `UpdatePassword.lnk` na pasta `%USERPROFILE%\apps\CitrixLauncher` ou [updatePassword.bat](updatePassword.bat) e introduza a nova password quando for pedida. A introducao e oculta e a credencial anterior e substituida pela nova, protegida pelo Windows para a conta atual. Nao coloque a password no `.env`.

Este atalho atualiza apenas a password guardada neste computador; nao altera a password da empresa. Depois, execute `OpenCitrix.bat` normalmente.

Em alternativa, execute o comando abaixo na pasta do projeto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CitrixLauncher.ps1 -SetPassword
```

A credencial protegida fica em `.citrix-password`, excluida pelo `.gitignore`. A protecao esta associada a esta conta Windows e a este computador: outra conta nao a consegue descodificar normalmente. Uma pessoa ou programa com acesso a esta conta, ou com privilegios administrativos, pode ainda conseguir aceder a credenciais ou controlar o processo. Se existir uma entrada `CITRIX_PASSWORD` antiga no `.env`, o script migra-a e remove-a do ficheiro ao arrancar. Copias de seguranca ou historicos anteriores do `.env` podem ainda conter a password.

Sem password protegida, e usado o preenchimento automatico do perfil `Default` do Edge. Para outro perfil, configure `EDGE_PROFILE=Profile 1` no `.env`, substituindo pelo nome da pasta do perfil. Feche todas as janelas do Edge antes de executar.

Se o Edge nao arrancar com o perfil habitual, pode criar um perfil dedicado e guardar nele a password previamente. Por exemplo, execute uma vez:

```powershell
& "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" --user-data-dir="$env:LOCALAPPDATA\CitrixLauncher\Edge"
```

Nesse perfil, abra o portal Citrix e configure o preenchimento automatico da password. Feche o Edge e adicione ao `.env` o caminho completo, por exemplo `EDGE_USER_DATA=C:\Users\utilizador\AppData\Local\CitrixLauncher\Edge`. A utilizacao da password guardada depende do preenchimento automatico e das politicas do Edge e do portal.

Se houver varios recursos, configure `CITRIX_RESOURCE` com parte do nome de um unico recurso. O Citrix Workspace deve estar instalado e associado a ficheiros `.ica`. Durante a instalacao, o EdgeDriver em `WebDriver\edgedriver_win64.zip` e descomprimido automaticamente; deve ter a mesma versao principal que o Edge.

Para diagnosticar e resolver uma incompatibilidade de versões do Edge e do EdgeDriver, consulte [manutenção.md](./maintenance/manutenção.md).

O login completo, a selecao do recurso e a abertura da sessao dependem da configuracao da conta e devem ser testados com um OTP valido.

<br><br>

---

Marco Gaspar | Powered by GitHub Copilot
