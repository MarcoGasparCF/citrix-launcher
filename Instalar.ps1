param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'

function New-Shortcut {
    param(
        [string]$InstallDirectory,
        [string]$ShortcutDirectory,
        [string]$ShortcutName,
        [string]$TargetFile,
        [string]$IconFile
    )

    $targetPath = Join-Path $InstallDirectory $TargetFile
    $iconPath = Join-Path $InstallDirectory $IconFile
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw "Falta o destino do atalho: $targetPath"
    }
    if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
        throw "Falta o icone do atalho: $iconPath"
    }
    if (-not $ShortcutDirectory -or -not (Test-Path -LiteralPath $ShortcutDirectory -PathType Container)) {
        throw "Nao foi possivel encontrar a pasta dos atalhos: $ShortcutDirectory"
    }

    $shortcutPath = Join-Path $ShortcutDirectory $ShortcutName
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetPath
    $shortcut.WorkingDirectory = $InstallDirectory
    $shortcut.IconLocation = "$iconPath,0"
    $shortcut.Save()
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        throw "Nao foi possivel criar o atalho: $shortcutPath"
    }
    Write-Host "Atalho criado: $shortcutPath"
}

try {
    $source = $PSScriptRoot.TrimEnd('\')
    if ($source -ne $destination -and (
            $destination.StartsWith("$source\", [StringComparison]::OrdinalIgnoreCase) -or
            $source.StartsWith("$destination\", [StringComparison]::OrdinalIgnoreCase))) {
        throw "Extraia o pacote para uma pasta separada, fora de $destination, e volte a executar o instalador."
    }

    foreach ($file in 'CitrixLauncher.ps1', 'OpenCitrix.bat', 'updatePassword.bat', 'WebDriver\edgedriver_win64.zip', 'icos\CitrixLauncher-cinza.ico', 'icos\CitrixLauncher-password.ico') {
        if (-not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) {
            throw "Falta $file. Extraia o pacote completo antes de instalar."
        }
    }

    do {
        $username = (Read-Host 'Nome de utilizador Citrix').Trim()
        if (-not $username) { Write-Host 'O nome de utilizador nao pode estar vazio.' }
    } until ($username)

    if ($source -ne $destination) {
        & robocopy.exe $source $destination /E /XJ /R:1 /W:1 /XF .env .citrix-password /XD .git /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) {
            throw "Falha ao copiar os ficheiros (Robocopy: $LASTEXITCODE)."
        }
    }

    $driverArchive = Join-Path $destination 'WebDriver\edgedriver_win64.zip'
    $driverDirectory = Join-Path $destination 'WebDriver\edgedriver_win64'
    New-Item -ItemType Directory -Path $driverDirectory -Force | Out-Null
    Expand-Archive -LiteralPath $driverArchive -DestinationPath $driverDirectory -Force
    if (-not (Test-Path -LiteralPath (Join-Path $driverDirectory 'msedgedriver.exe') -PathType Leaf)) {
        throw 'O arquivo edgedriver_win64.zip nao contem msedgedriver.exe.'
    }

    $envFile = Join-Path $destination '.env'
    $settingsFile = if (Test-Path -LiteralPath $envFile) { $envFile } else { Join-Path $source '.env' }
    $settings = @(
        if (Test-Path -LiteralPath $settingsFile) {
            Get-Content -LiteralPath $settingsFile -Encoding UTF8 |
                Where-Object { $_ -notmatch '^\s*CITRIX_(USERNAME|PASSWORD)\s*=' }
        }
        'CITRIX_USERNAME="{0}"' -f $username
    )
    Set-Content -LiteralPath $envFile -Value $settings -Encoding UTF8

    $desktopDirectory = [Environment]::GetFolderPath('DesktopDirectory')
    Write-Host 'A criar os atalhos do Citrix Launcher...'
    New-Shortcut -InstallDirectory $destination -ShortcutDirectory $desktopDirectory -ShortcutName 'CitrixLauncher.lnk' -TargetFile 'OpenCitrix.bat' -IconFile 'icos\CitrixLauncher-cinza.ico'
    New-Shortcut -InstallDirectory $destination -ShortcutDirectory $destination -ShortcutName 'UpdatePassword.lnk' -TargetFile 'updatePassword.bat' -IconFile 'icos\CitrixLauncher-password.ico'
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
