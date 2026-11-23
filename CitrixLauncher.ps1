param(
    [switch]$SetPassword,
    [switch]$MigratePassword
)

$ErrorActionPreference = 'Stop'

try {
    $envFile = Join-Path $PSScriptRoot '.env'
    if (-not (Test-Path -LiteralPath $envFile)) {
        throw 'Falta o ficheiro .env. Configure CITRIX_USERNAME antes de executar.'
    }

    $envLines = @(Get-Content -LiteralPath $envFile -Encoding UTF8)
    $settings = @{}
    foreach ($line in $envLines) {
        if ($line -match '^\s*(CITRIX_USERNAME|CITRIX_PASSWORD|CITRIX_RESOURCE|EDGE_PROFILE|EDGE_USER_DATA)\s*=\s*(.*?)\s*$') {
            $value = $matches[2]
            if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $settings[$matches[1]] = $value
        }
    }
    $credentialFile = Join-Path $PSScriptRoot '.citrix-password'
    $newPassword = $null
    if ($SetPassword) {
        $newPassword = Read-Host 'Password Citrix' -AsSecureString
        if ($newPassword.Length -eq 0) { throw 'A password nao pode estar vazia.' }
    }
    elseif (-not [string]::IsNullOrEmpty($settings['CITRIX_PASSWORD'])) {
        $newPassword = ConvertTo-SecureString $settings['CITRIX_PASSWORD'] -AsPlainText -Force
    }
    if ($newPassword) {
        $protectedPassword = ConvertFrom-SecureString $newPassword
        Set-Content -LiteralPath $credentialFile -Value $protectedPassword -Encoding ASCII -NoNewline
        $verifiedPassword = Get-Content -LiteralPath $credentialFile -Raw | ConvertTo-SecureString
        if ($verifiedPassword.Length -ne $newPassword.Length) { throw 'Nao foi possivel validar a password protegida.' }
        $verifiedPassword.Dispose()
        $newPassword.Dispose()
    }
    if ($envLines -match '^\s*CITRIX_PASSWORD\s*=') {
        $remainingLines = @($envLines | Where-Object { $_ -notmatch '^\s*CITRIX_PASSWORD\s*=' })
        Set-Content -LiteralPath $envFile -Value $remainingLines -Encoding UTF8
        $settings.Remove('CITRIX_PASSWORD')
        $envLines = $null
    }
    if ($SetPassword -or $MigratePassword) {
        if (-not (Test-Path -LiteralPath $credentialFile)) { throw 'Nao existe uma password para proteger.' }
        Write-Host 'Password protegida para a conta Windows atual.'
        return
    }
    if ([string]::IsNullOrWhiteSpace($settings['CITRIX_USERNAME'])) {
        throw 'Configure CITRIX_USERNAME no ficheiro .env.'
    }

    $driverDirectory = Join-Path $PSScriptRoot 'WebDriver\edgedriver_win64'
    $driverPath = Join-Path $driverDirectory 'msedgedriver.exe'
    if (-not (Test-Path -LiteralPath $driverPath)) {
        $driverArchive = Join-Path $PSScriptRoot 'WebDriver\edgedriver_win64.zip'
        if (-not (Test-Path -LiteralPath $driverArchive)) {
            throw 'Falta o msedgedriver.exe e o arquivo edgedriver_win64.zip.'
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($driverArchive)
        try {
            $entry = $archive.GetEntry('msedgedriver.exe')
            if ($null -eq $entry) { throw 'O arquivo nao contem msedgedriver.exe.' }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $driverPath)
        }
        finally { $archive.Dispose() }
    }

    $edgePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
    if (-not (Test-Path -LiteralPath $edgePath)) { throw 'Microsoft Edge nao encontrado.' }
    $edgeVersion = (Get-Item -LiteralPath $edgePath).VersionInfo.ProductVersion.Split('.')[0]
    $driverVersion = (Get-Item -LiteralPath $driverPath).VersionInfo.ProductVersion.Split('.')[0]
    if ($edgeVersion -ne $driverVersion) {
        throw "O Edge e a versao $edgeVersion e o EdgeDriver e a versao $driverVersion. Instale o EdgeDriver correspondente ao Edge."
    }

    $hasPassword = Test-Path -LiteralPath $credentialFile
    if ($hasPassword) {
        try { $securePassword = Get-Content -LiteralPath $credentialFile -Raw | ConvertTo-SecureString }
        catch { throw 'Nao foi possivel ler a password protegida. Configure-a novamente nesta conta Windows com -SetPassword.' }
    }
    $edgeOptions = @{ binary = $edgePath; args = @('--headless=new', '--window-size=1920,1080') }
    if ($hasPassword) {
        $edgeOptions.prefs = @{ 'credentials_enable_service' = $false; 'profile.password_manager_enabled' = $false }
    }
    else {
        $userData = if ($settings['EDGE_USER_DATA']) { $settings['EDGE_USER_DATA'] } elseif ($env:EDGE_USER_DATA) { $env:EDGE_USER_DATA } else { Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data' }
        if (-not (Test-Path -LiteralPath $userData)) { throw 'Perfil do Microsoft Edge nao encontrado.' }
        $profile = if ($settings['EDGE_PROFILE']) { $settings['EDGE_PROFILE'] } else { 'Default' }
        if (-not (Test-Path -LiteralPath (Join-Path $userData $profile))) {
            throw "Perfil Edge '$profile' nao encontrado. Configure EDGE_PROFILE no .env."
        }
        $edgeOptions.args += @("user-data-dir=$userData", "profile-directory=$profile")
    }

    $downloadDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('CitrixLauncher-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $downloadDirectory | Out-Null
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $driverProcess = Start-Process -FilePath $driverPath -ArgumentList "--port=$port" -WindowStyle Hidden -PassThru
    $driverUrl = "http://127.0.0.1:$port"
    $deadline = (Get-Date).AddSeconds(15)
    do {
        try { $status = Invoke-RestMethod -Uri "$driverUrl/status" -TimeoutSec 2; break }
        catch { Start-Sleep -Milliseconds 250 }
    } while ((Get-Date) -lt $deadline)
    if (-not $status) { throw 'Nao foi possivel iniciar o EdgeDriver.' }

    function Invoke-Driver($method, $path, $body = $null) {
        $arguments = @{ Method = $method; Uri = "$driverUrl$path"; TimeoutSec = 60 }
        if ($null -ne $body) {
            $arguments.ContentType = 'application/json; charset=utf-8'
            $arguments.Body = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 20 -Compress))
        }
        try { (Invoke-RestMethod @arguments).value }
        catch {
            if ($_.ErrorDetails.Message) {
                try { $response = $_.ErrorDetails.Message | ConvertFrom-Json } catch { $response = $null }
                if ($response.value.message) { throw $response.value.message }
            }
            if ($_.Exception.Response) {
                $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                try { $response = $reader.ReadToEnd() | ConvertFrom-Json }
                finally { $reader.Dispose() }
                if ($response.value.message) { throw $response.value.message }
            }
            throw
        }
    }

    $session = Invoke-Driver Post '/session' @{
        capabilities = @{ alwaysMatch = @{
            browserName = 'MicrosoftEdge'
            'ms:edgeOptions' = $edgeOptions
        } }
    }
    $sessionPath = '/session/' + $session.sessionId
    Invoke-Driver Post "$sessionPath/ms/cdp/execute" @{ cmd = 'Browser.setDownloadBehavior'; params = @{ behavior = 'allow'; downloadPath = $downloadDirectory } }
    Invoke-Driver Post "$sessionPath/url" @{ url = 'https://citrixaccesspriv.cgd.pt/logon/LogonPoint/tmindex.html' }

    function Get-Elements($selector) {
        @(Invoke-Driver Post "$sessionPath/elements" @{ using = 'css selector'; value = $selector })
    }

    function Get-ElementId($element) {
        $element.'element-6066-11e4-a52e-4f735466cecf'
    }

    function Send-ElementText($element, $text) {
        $elementId = Get-ElementId $element
        Invoke-Driver Post "$sessionPath/element/$elementId/value" @{ text = $text }
    }

    function Click-Element($element) {
        $elementId = Get-ElementId $element
        Invoke-Driver Post "$sessionPath/element/$elementId/click" @{}
    }

    function Wait-VisibleElement($selector, $seconds = 30) {
        $deadline = (Get-Date).AddSeconds($seconds)
        do {
            foreach ($element in (Get-Elements $selector)) {
                $elementId = Get-ElementId $element
                if ((Invoke-Driver Get "$sessionPath/element/$elementId/displayed") -and
                    (Invoke-Driver Get "$sessionPath/element/$elementId/enabled")) { return $element }
            }
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)
        throw "Elemento nao encontrado: $selector"
    }

    $login = Wait-VisibleElement 'input#login:not([disabled])'
    $loginId = Get-ElementId $login
    Invoke-Driver Post "$sessionPath/element/$loginId/clear" @{}
    Send-ElementText $login $settings['CITRIX_USERNAME']
    Send-ElementText $login ([string][char]0xE007)

    $password = Wait-VisibleElement 'input#passwd'
    Click-Element $password
    if ($hasPassword) {
        $passwordId = Get-ElementId $password
        Invoke-Driver Post "$sessionPath/element/$passwordId/clear" @{}
        $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        try {
            $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
            Send-ElementText $password $plainPassword
        }
        finally {
            $plainPassword = $null
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
            $securePassword.Dispose()
        }
    }
    else {
        $deadline = (Get-Date).AddSeconds(20)
        do {
            $passwordFilled = Invoke-Driver Post "$sessionPath/execute/sync" @{ script = "return document.querySelector('#passwd').value.length > 0"; args = @() }
            if ($passwordFilled) { break }
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)
        if (-not $passwordFilled) {
            throw 'O Edge nao preencheu a password. Verifique o perfil ou configure a password com -SetPassword.'
        }
    }

    $passcode = Wait-VisibleElement 'input#passwd1'
    $otp = Read-Host 'OTP do smartphone'
    if ([string]::IsNullOrWhiteSpace($otp)) { throw 'O OTP nao pode estar vazio.' }
    Send-ElementText $passcode $otp
    $otp = $null
    Click-Element (Wait-VisibleElement '#Logon')

    $deadline = (Get-Date).AddSeconds(90)
    $resource = $null
    do {
        $ica = Get-ChildItem -LiteralPath $downloadDirectory -Filter '*.ica' -File | Select-Object -First 1
        if ($ica -and -not (Get-ChildItem -LiteralPath $downloadDirectory -Filter '*.crdownload' -File)) { break }
        $ica = $null
        $resources = @(Get-Elements '.storeapp-list .storeapp' | Where-Object {
            $resourceId = Get-ElementId $_
            (Invoke-Driver Get "$sessionPath/element/$resourceId/displayed") -and (Invoke-Driver Get "$sessionPath/element/$resourceId/enabled")
        })
        if ($resources.Count -gt 0) {
            if ($settings['CITRIX_RESOURCE']) {
                $resources = @($resources | Where-Object {
                    $resourceId = Get-ElementId $_
                    $resourceText = Invoke-Driver Get "$sessionPath/element/$resourceId/text"
                    $resourceText.Trim().IndexOf($settings['CITRIX_RESOURCE'], [StringComparison]::OrdinalIgnoreCase) -ge 0
                })
            }
            if ($resources.Count -ne 1) {
                throw 'Nao foi possivel identificar um unico recurso. Configure CITRIX_RESOURCE no .env.'
            }
            $resource = $resources[0]
            $resourceId = Get-ElementId $resource
            $launchLink = Invoke-Driver Post "$sessionPath/element/$resourceId/element" @{ using = 'css selector'; value = '.storeapp-details-link' }
            Click-Element $launchLink
            break
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    if (-not $ica -and -not $resource) { throw 'O login nao terminou ou nao foram encontrados recursos Citrix.' }
    if (-not $ica) {
        $deadline = (Get-Date).AddSeconds(60)
        do {
            $ica = Get-ChildItem -LiteralPath $downloadDirectory -Filter '*.ica' -File | Select-Object -First 1
            if ($ica -and -not (Get-ChildItem -LiteralPath $downloadDirectory -Filter '*.crdownload' -File)) { break }
            $ica = $null
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)
    }
    if (-not $ica) { throw 'O ficheiro ICA nao foi descarregado.' }
    Start-Process -FilePath $ica.FullName
    Write-Host 'Ficheiro ICA enviado para abertura.'
}
catch {
    Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Feche todas as janelas do Edge antes de executar e confirme que o Citrix Workspace esta instalado.'
    exit 1
}
finally {
    if ($sessionPath) { try { Invoke-Driver Delete $sessionPath } catch { } }
    if ($driverProcess -and -not $driverProcess.HasExited) {
        & "$env:SystemRoot\System32\taskkill.exe" /PID $driverProcess.Id /T /F 2>$null | Out-Null
        if (-not $driverProcess.HasExited) { Stop-Process -Id $driverProcess.Id -Force -ErrorAction SilentlyContinue }
    }
}