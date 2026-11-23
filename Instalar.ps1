param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'

function New-LauncherShortcut {
    param(
        [string]$InstallDirectory,
        [string]$DesktopDirectory
    )

    $launcherPath = Join-Path $InstallDirectory 'OpenCitrix.bat'
    $iconPath = Join-Path $InstallDirectory 'icos\CitrixLauncher-cinza.ico'
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
        throw "Falta o launcher instalado: $launcherPath"
    }
    if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
        throw "Falta o icone do launcher: $iconPath"
    }
    if (-not $DesktopDirectory -or -not (Test-Path -LiteralPath $DesktopDirectory -PathType Container)) {
        throw 'Nao foi possivel encontrar o ambiente de trabalho do utilizador.'
    }

    $shortcutPath = Join-Path $DesktopDirectory 'CitrixLauncher.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $launcherPath
    $shortcut.WorkingDirectory = $InstallDirectory
    $shortcut.IconLocation = "$iconPath,0"
    $shortcut.Save()
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
        throw "Nao foi possivel criar o atalho: $shortcutPath"
    }
    Write-Host "Atalho criado no ambiente de trabalho: $shortcutPath"
}

try {
    $source = $PSScriptRoot.TrimEnd('\')
    if ($source -ne $destination -and (
            $destination.StartsWith("$source\", [StringComparison]::OrdinalIgnoreCase) -or
            $source.StartsWith("$destination\", [StringComparison]::OrdinalIgnoreCase))) {
        throw "Extraia o pacote para uma pasta separada, fora de $destination, e volte a executar o instalador."
    }

    foreach ($file in 'CitrixLauncher.ps1', 'OpenCitrix.bat', 'updatePassword.bat', 'icos\CitrixLauncher-cinza.ico') {
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

    Write-Host 'A criar o atalho do Citrix Launcher...'
    New-LauncherShortcut -InstallDirectory $destination -DesktopDirectory ([Environment]::GetFolderPath('DesktopDirectory'))
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
