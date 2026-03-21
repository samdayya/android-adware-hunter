# ============================================================
#  Android Adware Hunter PRO — Instal·lador de l'Agent
#  Executa amb:  irm http://192.168.0.6:5000/install_agent.ps1 | iex
# ============================================================

# Forçar la consola a UTF-8 per mostrar accents i caràcters especials
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# ── Elevar a Administrador si cal (necessari per crear serveis) ──
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$SERVER     = "http://192.168.0.6:5000"
$BRIDGE_DIR = "C:\temp"
$BRIDGE_FILE    = "$BRIDGE_DIR\adb_bridge.py"
$SERVICE_NAME   = "AdbBridgeAgent"
$SERVICE_DISPLAY = "ADB Bridge Agent"
$NSSM_PATH      = "$BRIDGE_DIR\nssm.exe"

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

function RunWithSpinner($label, [scriptblock]$action) {
    $frames = @('|','/','-','\')
    $job = Start-Job -ScriptBlock $action
    $i = 0
    while ($job.State -eq 'Running') {
        $f = $frames[$i % 4]
        Write-Host "`r            $f  $label..." -NoNewline
        Start-Sleep -Milliseconds 200
        $i++
    }
    Write-Host "`r                                                  `r" -NoNewline
    Receive-Job $job | Out-Null
    Remove-Job $job
}

function Get-PythonwPath {
    $py = (py -3 -c "import sys; print(sys.executable)" 2>&1).Trim()
    $pw = $py -replace 'python\.exe$', 'pythonw.exe'
    if (Test-Path $pw) { return $pw } else { return $py }
}

function InstallNssm {
    if (Test-Path $NSSM_PATH) { return }

    #Intent 1: winget
    INFO "Instal·lant NSSM via winget..."
    winget install NSSM.NSSM --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    RefreshPath
    $nssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmCmd) { $wingetNssm = $nssmCmd.Source } else { $wingetNssm = $null }
    if ($wingetNssm) {
        Copy-Item $wingetNssm $NSSM_PATH -Force
        OK "NSSM instal·lat via winget"
        return
    }

    # Intent 2: descàrrega directa (múltiples fonts)
    $urls = @(
        "https://nssm.cc/release/nssm-2.24.zip",
        "https://github.com/nicholasgasior/nssm-mirror/raw/main/nssm-2.24.zip"
    )
    $zip = "$env:TEMP\nssm.zip"
    foreach ($url in $urls) {
        INFO "Provant descàrrega: $url"
        try {
            (New-Object Net.WebClient).DownloadFile($url, $zip)
            Expand-Archive $zip -DestinationPath "$env:TEMP\nssm_ext" -Force
            $exe = Get-ChildItem "$env:TEMP\nssm_ext" -Recurse -Filter "nssm.exe" |
                   Where-Object { $_.FullName -match "win64" } |
                   Select-Object -First 1
            if (-not $exe) {
                $exe = Get-ChildItem "$env:TEMP\nssm_ext" -Recurse -Filter "nssm.exe" | Select-Object -First 1
            }
            if ($exe) {
                Copy-Item $exe.FullName $NSSM_PATH -Force
                Remove-Item $zip, "$env:TEMP\nssm_ext" -Recurse -Force -ErrorAction SilentlyContinue
                OK "NSSM descarregat a $NSSM_PATH"
                return
            }
        } catch {
            INFO "Fallada: $_"
        }
    }

    ERR "No s'ha pogut obtenir NSSM per cap via. Comprova la connexió a internet."
    Read-Host "  Prem ENTER per sortir"
    exit 1
}

function RegisterService {
    InstallNssm
    # Eliminar servei anterior si existeix
    $existing = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.Status -eq 'Running') { Stop-Service -Name $SERVICE_NAME -Force | Out-Null }
        & $NSSM_PATH remove $SERVICE_NAME confirm 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    }
    $pythonw = Get-PythonwPath
    & $NSSM_PATH install $SERVICE_NAME $pythonw "`"$BRIDGE_FILE`"" 2>&1 | Out-Null
    & $NSSM_PATH set $SERVICE_NAME AppDirectory $BRIDGE_DIR 2>&1 | Out-Null
    & $NSSM_PATH set $SERVICE_NAME AppStdout "$BRIDGE_DIR\adb_bridge.log" 2>&1 | Out-Null
    & $NSSM_PATH set $SERVICE_NAME AppStderr "$BRIDGE_DIR\adb_bridge.log" 2>&1 | Out-Null
    & $NSSM_PATH set $SERVICE_NAME AppRotateFiles 1 2>&1 | Out-Null
    & $NSSM_PATH set $SERVICE_NAME AppRotateBytes 1048576 2>&1 | Out-Null
    & $NSSM_PATH set $SERVICE_NAME DisplayName $SERVICE_DISPLAY 2>&1 | Out-Null
    & $NSSM_PATH set $SERVICE_NAME Description "Android Adware Hunter PRO - ADB Local Bridge" 2>&1 | Out-Null
    & $NSSM_PATH set $SERVICE_NAME Start SERVICE_AUTO_START 2>&1 | Out-Null
}

# ── Comprovació ràpida de components ──
function CheckAll {
    $ok = $true
    Write-Host "  Comprovant components instal·lats..." -ForegroundColor White
    Write-Host ""

    if (Get-Command adb -ErrorAction SilentlyContinue) {
        OK "ADB: $(adb version 2>&1 | Select-Object -First 1)"
    } else {
        ERR "ADB: no instal·lat"
        $ok = $false
    }

    $pyOk = (Get-Command py -ErrorAction SilentlyContinue) -and ((py --version 2>&1) -notmatch "not found|Store")
    if ($pyOk) {
        OK "Python: $(py --version 2>&1)"
    } else {
        ERR "Python: no instal·lat"
        $ok = $false
    }

    if ($pyOk) { py -3 -c "import flask" 2>&1 | Out-Null; $flaskOk = ($LASTEXITCODE -eq 0) } else { $flaskOk = $false }
    if ($flaskOk) {
        OK "Flask: instal·lat"
    } else {
        ERR "Flask: no instal·lat"
        $ok = $false
    }

    if (Test-Path $BRIDGE_FILE) {
        OK "Agent: present a $BRIDGE_FILE"
    } else {
        ERR "Agent (adb_bridge.py): no trobat a $BRIDGE_FILE"
        $ok = $false
    }

    $svc = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
    if ($svc) {
        OK "Servei: registrat (estat: $($svc.Status))"
    } else {
        INFO "Servei: no registrat (es configurarà)"
    }

    Write-Host ""
    return $ok
}

# ── inici ──
Banner

$allOk = CheckAll

if ($allOk) {
    Write-Host "  Tot instal·lat correctament!" -ForegroundColor Green
    Write-Host ""
    if (-not (Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue)) {
        RegisterService
        OK "Servei registrat"
        Write-Host ""
    }
} else {
    Write-Host "  Falten components. S'iniciarà la instal·lació." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  Prem ENTER per continuar (o Ctrl+C per sortir)"

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
    $pyOk = (Get-Command py -ErrorAction SilentlyContinue) -and ((py --version 2>&1) -notmatch "not found|Store")
    if ($pyOk) {
        SKIP "Python ja instal·lat ($(py --version 2>&1))"
    } else {
        INFO "Instal·lant via winget..."
        $pyIds = @('Python.Python.3.13','Python.Python.3.12','Python.Python.3.11','Python.Python.3.10')
        $installed = $false
        foreach ($id in $pyIds) {
            INFO "Provant $id..."
            RunWithSpinner "Instal·lant $id" { winget install --id $using:id --source winget --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null }
            RefreshPath
            if (Get-Command py -ErrorAction SilentlyContinue) {
                OK "Python instal·lat correctament ($(py --version 2>&1))"
                $installed = $true
                break
            }
        }
        if (-not $installed) {
            ERR "No s'ha pogut instal·lar Python automaticament."
            INFO "Descarrega'l manualment de https://www.python.org/downloads/"
            INFO "Assegura't de marcar 'Add Python to PATH' durant la instal·lacio."
            Read-Host "  Un cop instal·lat, prem ENTER per continuar"
            RefreshPath
            if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
                ERR "Python segueix sense detectar-se. Reinicia el terminal i torna a executar."
                Read-Host "  Prem ENTER per sortir"
                exit 1
            }
        }
    }

    # ── Pas 3: Flask ──
    Step 3 $total "Llibreries Python (flask, flask-cors)"
    RunWithSpinner "Instal·lant flask i flask-cors" { py -3 -m pip install flask flask-cors --quiet 2>&1 | Out-Null }
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

    # ── Pas 5: Servei i verificació dispositiu ──
    Step 5 $total "Configurant servei Windows i verificant dispositiu"
    RegisterService
    OK "Servei registrat — s'iniciarà automàticament a cada inici de sessió"
    Write-Host ""
    INFO "Comprova si hi ha algun mòbil connectat per USB..."
    $adbOut = adb devices 2>&1
    if ($adbOut -match "\tdevice") {
        OK "Dispositiu detectat!"
    } else {
        Write-Host "        ??  Cap dispositiu detectat. Connecta el mòbil per USB" -ForegroundColor Yellow
        Write-Host "            i activa la Depuració USB (Ajustos → Op. Desenvolupador)." -ForegroundColor Yellow
    }

    # ── Banner final ──
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║   Instal·lació completada!                   ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
}

# ── Arrancar ──
Write-Host "  Un cop l'agent estigui actiu, obre el navegador a:" -ForegroundColor White
Write-Host "  $SERVER" -ForegroundColor Cyan
Write-Host ""

$resp = Read-Host "  Vols arrancar l'Agent ara? [S/n]"
if ($resp -eq "" -or $resp -match "^[Ss]") {
    $svc = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -eq 'Running') {
            INFO "Agent ja en execució. Reiniciant..."
            Restart-Service -Name $SERVICE_NAME -Force
        } else {
            Start-Service -Name $SERVICE_NAME
        }
    } else {
        ERR "Servei no trobat. Torna a executar l'instal·lador."
        Read-Host "  Prem ENTER per sortir"
        exit 1
    }
    Start-Sleep -Seconds 2
    Write-Host ""
    Write-Host "  Agent iniciat com a servei de Windows." -ForegroundColor Green
    Write-Host "  S'iniciarà automàticament a cada engegada de Windows." -ForegroundColor Gray
    Write-Host "  Log: $BRIDGE_DIR\adb_bridge.log" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Obrint el navegador..." -ForegroundColor Green
    Start-Process $SERVER
}
