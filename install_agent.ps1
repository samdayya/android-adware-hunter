# ============================================================
#  Android Adware Hunter PRO — Instal·lador de l'Agent
#  Executa amb:  irm http://192.168.0.6:5000/install_agent.ps1 | iex
# ============================================================

# Forçar la consola a UTF-8 per mostrar accents i caràcters especials
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$SERVER     = "http://192.168.0.6:5000"
$BRIDGE_DIR = "C:\temp"
$BRIDGE_FILE = "$BRIDGE_DIR\adb_bridge.py"

# ── helpers visuals ──
function Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║   Android Adware Hunter PRO                  ║" -ForegroundColor Magenta
    Write-Host "  ║   Instal·lador de l'Agent  v1.0              ║" -ForegroundColor Magenta
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
}

function Step($n, $total, $text) {
    Write-Host ""
    Write-Host "  [$n/$total] $text" -ForegroundColor Cyan
}

function OK($text)   { Write-Host "        OK  $text" -ForegroundColor Green }
function SKIP($text) { Write-Host "        --  $text" -ForegroundColor Yellow }
function ERR($text)  { Write-Host "        !!  $text" -ForegroundColor Red }
function INFO($text) { Write-Host "            $text" -ForegroundColor Gray }

function RefreshPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") `
              + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# ── inici ──
Banner

Write-Host "  Aquest assistent instal·larà tot el necessari per" -ForegroundColor White
Write-Host "  connectar el teu mòbil Android amb la web." -ForegroundColor White
Write-Host ""
Read-Host "  Prem ENTER per continuar"

$total = 5

# ── Pas 1: ADB / Platform Tools ──
Step 1 $total "Android Platform Tools (ADB)"
if (Get-Command adb -ErrorAction SilentlyContinue) {
    SKIP "ADB ja instal·lat ($(adb version | Select-Object -First 1))"
} else {
    INFO "Instal·lant via winget..."
    winget install Google.PlatformTools --accept-source-agreements --accept-package-agreements --silent
    RefreshPath
    if (Get-Command adb -ErrorAction SilentlyContinue) {
        OK "Platform Tools instal·lat correctament"
    } else {
        ERR "No s'ha pogut detectar ADB. Reinicia el terminal i torna a executar."
        Read-Host "  Prem ENTER per sortir"
        exit 1
    }
}

# ── Pas 2: Python ──
Step 2 $total "Python 3"
if (Get-Command python -ErrorAction SilentlyContinue) {
    SKIP "Python ja instal·lat ($(python --version 2>&1))"
} else {
    INFO "Instal·lant via winget..."
    winget install Python.Python.3 --accept-source-agreements --accept-package-agreements --silent
    RefreshPath
    if (Get-Command python -ErrorAction SilentlyContinue) {
        OK "Python instal·lat correctament"
    } else {
        ERR "No s'ha pogut detectar Python. Reinicia el terminal i torna a executar."
        Read-Host "  Prem ENTER per sortir"
        exit 1
    }
}

# ── Pas 3: Flask ──
Step 3 $total "Llibreries Python (flask, flask-cors)"
INFO "Instal·lant..."
pip install flask flask-cors --quiet 2>&1 | Out-Null
OK "flask i flask-cors instal·lats"

# ── Pas 4: Directori i bridge ──
Step 4 $total "Descarregant l'Agent (adb_bridge.py)"
if (-not (Test-Path $BRIDGE_DIR)) {
    New-Item -ItemType Directory -Path $BRIDGE_DIR | Out-Null
    INFO "Directori $BRIDGE_DIR creat"
}
try {
    Invoke-WebRequest "$SERVER/adb_bridge.py" -OutFile $BRIDGE_FILE -UseBasicParsing
    OK "Agent descarregat a $BRIDGE_FILE"
} catch {
    ERR "No s'ha pogut descarregar adb_bridge.py. Comprova que el servidor ($SERVER) és accessible."
    Read-Host "  Prem ENTER per sortir"
    exit 1
}

# ── Pas 5: Resum i arrencada ──
Step 5 $total "Verificant dispositiu Android"
INFO "Comprova si hi ha algun mòbil connectat per USB..."
$adbOut = adb devices 2>&1
if ($adbOut -match "\tdevice") {
    OK "Dispositiu detectat!"
} else {
    Write-Host "        ??  Cap dispositiu detectat. Connecta el mòbil per USB" -ForegroundColor Yellow
    Write-Host "            i activa la Depuració USB (Ajustos → Op. Desenvolupador)." -ForegroundColor Yellow
}

# ── Final ──
Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║   Instal·lació completada!                   ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Un cop l'agent estigui actiu, obre el navegador a:" -ForegroundColor White
Write-Host "  $SERVER" -ForegroundColor Cyan
Write-Host ""

$resp = Read-Host "  Vols arrancar l'Agent ara? [S/n]"
if ($resp -eq "" -or $resp -match "^[Ss]") {
    Write-Host ""
    Write-Host "  Arrancant l'Agent... Deixa aquesta finestra oberta." -ForegroundColor Green
    Write-Host "  Per aturar-lo, prem Ctrl+C" -ForegroundColor Yellow
    Write-Host ""
    Set-Location $BRIDGE_DIR
    py -3 adb_bridge.py
}
