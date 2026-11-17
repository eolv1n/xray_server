$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

Write-Host 'Обновление Xray на роутере Keenetic с XKeen'
Write-Host 'Пароль будет запрошен программой SSH и не сохраняется скриптом.'
Write-Host ''

$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
if (-not $ssh) {
    Write-Host 'Не найден OpenSSH Client в Windows. Установите его в дополнительных компонентах Windows и запустите снова.' -ForegroundColor Red
    exit 1
}

$gatewayDefault = ''
try {
    $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
        Where-Object { $_.NextHop -ne '0.0.0.0' } |
        Sort-Object -Property RouteMetric, InterfaceMetric |
        Select-Object -First 1
    if ($route) { $gatewayDefault = [string]$route.NextHop }
} catch { }

if ($gatewayDefault) {
    $gateway = Read-Host "Адрес роутера / шлюза [$gatewayDefault]"
    if ([string]::IsNullOrWhiteSpace($gateway)) { $gateway = $gatewayDefault }
} else {
    $gateway = Read-Host 'Адрес роутера / шлюза (например, 192.168.1.1)'
}
$gateway = $gateway.Trim()
if ($gateway -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$') {
    Write-Host 'Неверный адрес: укажите IPv4-адрес или имя роутера.' -ForegroundColor Red
    exit 1
}

$login = Read-Host 'Логин SSH Entware [root]'
if ([string]::IsNullOrWhiteSpace($login)) { $login = 'root' }
$login = $login.Trim()
if ($login -notmatch '^[A-Za-z_][A-Za-z0-9_.-]{0,31}$') {
    Write-Host 'Неверный логин SSH.' -ForegroundColor Red
    exit 1
}

$portText = Read-Host 'Порт SSH Entware [222]'
if ([string]::IsNullOrWhiteSpace($portText)) { $portText = '222' }
$port = 0
if (-not [int]::TryParse($portText.Trim(), [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
    Write-Host 'Порт должен быть числом от 1 до 65535.' -ForegroundColor Red
    exit 1
}

$routerScript = Join-Path $PSScriptRoot 'router-update.sh'
if (-not (Test-Path -LiteralPath $routerScript -PathType Leaf)) {
    Write-Host 'Не найден router-update.sh. Распакуйте весь архив, сохранив файлы вместе.' -ForegroundColor Red
    exit 1
}

$script = [System.IO.File]::ReadAllText($routerScript, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($script))
$remoteCommand = "printf %s $encoded | base64 -d | sh"
Write-Host ''
Write-Host "Подключение к ${login}@${gateway}:${port}. При первом подключении SSH может спросить о ключе устройства."
Write-Host 'Введите пароль в окне SSH; символы при вводе не показываются.'
Write-Host ''

& $ssh.Source -tt -p $port -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -- "${login}@${gateway}" $remoteCommand
$result = $LASTEXITCODE
Write-Host ''
if ($result -eq 0) {
    Write-Host 'Готово. Проверьте на компьютере сайты, которые открываются через VPN.' -ForegroundColor Green
} else {
    Write-Host "Обновление не завершилось (код $result). Сохраните текст окна и передайте его администратору; пароль не сообщайте." -ForegroundColor Yellow
}
exit $result
