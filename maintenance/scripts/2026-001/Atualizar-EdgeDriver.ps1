[CmdletBinding()]
param(
    [string[]]$AdditionalLauncherPath = @()
)

$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$logPath = Join-Path $projectRoot 'maintenance\maintenance.log'
$executionId = [Guid]::NewGuid().ToString('N')
$executingUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

function Write-MaintenanceLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Phase,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz'
    $safeMessage = $Message -replace '[\r\n|]+', ' '
    $line = '{0} | ID=2026/001 | Run={1} | User={2} | Phase={3} | {4}' -f $timestamp, $executionId, $executingUser, $Phase, $safeMessage
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    Set-Content -LiteralPath $logPath -Value 'CitrixLauncher maintenance execution log' -Encoding UTF8
}
Write-MaintenanceLog -Phase 'INICIO' -Message 'Execucao do script de atualizacao do EdgeDriver iniciada.'

$temporaryDirectory = $null
try {
$installedRoot = Join-Path $env:USERPROFILE 'apps\CitrixLauncher'
$edgePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'

if (-not (Test-Path -LiteralPath $edgePath -PathType Leaf)) {
    throw "Microsoft Edge nao foi encontrado em: $edgePath"
}

$edgeVersion = (Get-Item -LiteralPath $edgePath).VersionInfo.ProductVersion
if ($edgeVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw "Nao foi possivel interpretar a versao do Edge: $edgeVersion"
}
Write-MaintenanceLog -Phase 'DETECAO' -Message "Versao do Edge detetada: $edgeVersion."

$targetPaths = @($projectRoot)
if (Test-Path -LiteralPath $installedRoot -PathType Container) {
    $targetPaths += $installedRoot
}
foreach ($path in $AdditionalLauncherPath) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw 'AdditionalLauncherPath nao pode estar vazio.'
    }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "A pasta adicional do launcher nao existe: $path"
    }
    $targetPaths += (Resolve-Path -LiteralPath $path).Path
}

$uniqueTargetPaths = @()
foreach ($path in $targetPaths) {
    $fullPath = [System.IO.Path]::GetFullPath($path)
    if ($uniqueTargetPaths -notcontains $fullPath) {
        $uniqueTargetPaths += $fullPath
    }
    $driverDirectory = Join-Path $fullPath 'WebDriver\edgedriver_win64'
    $archiveDestination = Join-Path $fullPath 'WebDriver\edgedriver_win64.zip'
    if (-not (Test-Path -LiteralPath $driverDirectory -PathType Container)) {
        throw "A pasta do EdgeDriver nao existe: $driverDirectory"
    }
    if (-not (Test-Path -LiteralPath $archiveDestination -PathType Leaf)) {
        throw "O arquivo do EdgeDriver nao existe: $archiveDestination"
    }
}
Write-MaintenanceLog -Phase 'DESTINOS' -Message ("Copias a atualizar: {0}" -f ($uniqueTargetPaths -join '; '))

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('CitrixLauncher-EdgeDriver-' + [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryDirectory 'edgedriver_win64.zip'
$driverPath = Join-Path $temporaryDirectory 'msedgedriver.exe'

    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $downloadUri = "https://msedgedriver.microsoft.com/$edgeVersion/edgedriver_win64.zip"
    Write-MaintenanceLog -Phase 'DESCARGA' -Message "A iniciar descarga oficial da versao $edgeVersion."
    Write-Host "A descarregar o EdgeDriver oficial $edgeVersion..."
    Invoke-WebRequest -Uri $downloadUri -OutFile $archivePath -UseBasicParsing -TimeoutSec 120

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entry = $archive.GetEntry('msedgedriver.exe')
        if (-not $entry -or $entry.Length -le 0) {
            throw 'O ZIP oficial nao contem um msedgedriver.exe valido na raiz.'
        }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $driverPath)
    }
    finally {
        $archive.Dispose()
    }

    $downloadedVersion = (Get-Item -LiteralPath $driverPath).VersionInfo.ProductVersion
    if ($downloadedVersion -ne $edgeVersion) {
        throw "A versao descarregada ($downloadedVersion) nao corresponde a versao do Edge ($edgeVersion)."
    }
    Write-MaintenanceLog -Phase 'DESCARGA' -Message "ZIP extraido e validado; versao do EdgeDriver: $downloadedVersion."

    $runningProcesses = @(Get-Process -Name msedge, msedgedriver -ErrorAction SilentlyContinue)
    if ($runningProcesses.Count -gt 0) {
        Write-MaintenanceLog -Phase 'PROCESSOS' -Message ("Encontrados processos Edge/EdgeDriver: {0}" -f (($runningProcesses | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ', '))
        Write-Warning 'Para atualizar, e necessario fechar todos os processos Edge e EdgeDriver encontrados. Isto pode fechar separadores sem guardar dados e interromper outras automatizacoes.'
        foreach ($process in $runningProcesses) {
            Write-Host ("{0} (PID {1})" -f $process.ProcessName, $process.Id)
        }
        $confirmation = Read-Host "Escreva FECHAR para terminar estes processos e continuar"
        if ($confirmation -cne 'FECHAR') {
            Write-MaintenanceLog -Phase 'CANCELADO' -Message 'Utilizador nao confirmou o fecho dos processos; ficheiros nao alterados.'
            throw 'Atualizacao cancelada; nenhum processo foi terminado e os ficheiros nao foram alterados.'
        }

        foreach ($process in $runningProcesses) {
            if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            }
        }

        $deadline = (Get-Date).AddSeconds(15)
        do {
            $remainingProcesses = @(Get-Process -Name msedge, msedgedriver -ErrorAction SilentlyContinue)
            if ($remainingProcesses.Count -eq 0) { break }
            Start-Sleep -Milliseconds 250
        } while ((Get-Date) -lt $deadline)

        if ($remainingProcesses.Count -gt 0) {
            throw 'Ainda existem processos Edge ou EdgeDriver em execucao. Os ficheiros nao foram atualizados.'
        }
        Write-MaintenanceLog -Phase 'PROCESSOS' -Message 'Processos Edge e EdgeDriver terminados apos confirmacao.'
    }
    else {
        Write-MaintenanceLog -Phase 'PROCESSOS' -Message 'Nao foram encontrados processos Edge ou EdgeDriver em execucao.'
    }

    $sourceArchiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    $sourceDriverHash = (Get-FileHash -LiteralPath $driverPath -Algorithm SHA256).Hash
    foreach ($target in $uniqueTargetPaths) {
        $archiveDestination = Join-Path $target 'WebDriver\edgedriver_win64.zip'
        $driverDestination = Join-Path $target 'WebDriver\edgedriver_win64\msedgedriver.exe'

        Write-MaintenanceLog -Phase 'ATUALIZACAO' -Message "A atualizar os ficheiros em: $target."
        Copy-Item -LiteralPath $archivePath -Destination $archiveDestination -Force
        Copy-Item -LiteralPath $driverPath -Destination $driverDestination -Force

        $archiveHash = (Get-FileHash -LiteralPath $archiveDestination -Algorithm SHA256).Hash
        $driverHash = (Get-FileHash -LiteralPath $driverDestination -Algorithm SHA256).Hash
        $installedDriverVersion = (Get-Item -LiteralPath $driverDestination).VersionInfo.ProductVersion
        if ($archiveHash -ne $sourceArchiveHash -or $driverHash -ne $sourceDriverHash -or $installedDriverVersion -ne $edgeVersion) {
            throw "A verificacao dos ficheiros atualizados falhou em: $target"
        }

        Write-Host "Atualizado e verificado: $target"
        Write-MaintenanceLog -Phase 'VERIFICACAO' -Message "ZIP e executavel atualizados e validados em: $target; versao $installedDriverVersion."
    }

    Write-Host "Edge: $edgeVersion; EdgeDriver: $downloadedVersion"
    Write-MaintenanceLog -Phase 'VERIFICACAO' -Message "Versoes compativeis: Edge $edgeVersion; EdgeDriver $downloadedVersion."

    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    $temporaryDirectory = $null
    Write-MaintenanceLog -Phase 'LIMPEZA' -Message 'Ficheiros temporarios removidos.'

    $launcherRoot = if (Test-Path -LiteralPath $installedRoot -PathType Container) { $installedRoot } else { $projectRoot }
    $launcherPath = Join-Path $launcherRoot 'OpenCitrix.bat'
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
        throw "OpenCitrix.bat nao foi encontrado em: $launcherRoot"
    }

    Write-MaintenanceLog -Phase 'INICIO_LAUNCHER' -Message "A iniciar o launcher em: $launcherRoot."
    Write-Host 'A iniciar OpenCitrix.bat. O login pode pedir o OTP e abrir uma sessao Citrix.'
    Start-Process -FilePath $launcherPath -WorkingDirectory $launcherRoot
    Write-MaintenanceLog -Phase 'CONCLUIDO' -Message 'Atualizacao verificada e OpenCitrix.bat iniciado.'
}
catch {
    Write-MaintenanceLog -Phase 'ERRO' -Message $_.Exception.Message
    throw
}
finally {
    if ($temporaryDirectory -and (Test-Path -LiteralPath $temporaryDirectory)) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
        Write-MaintenanceLog -Phase 'LIMPEZA' -Message 'Ficheiros temporarios removidos apos falha.'
    }
}
