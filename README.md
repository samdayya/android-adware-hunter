# Android Adware Hunter PRO

Eina web per detectar, analitzar i eliminar aplicacions sospitoses d'un dispositiu Android connectat per USB, accessible des de qualsevol navegador de la xarxa local (LAN).

---

## Arquitectura

```
┌─────────────────────────────────────┐
│  Navegador client (qualsevol PC)    │
│  http://192.168.0.6:5000            │
└────────────────┬────────────────────┘
                 │ HTTP (LAN)
                 ▼
┌─────────────────────────────────────┐
│  SERVIDOR  192.168.0.6              │
│  server.py  (Flask, port 5000)      │
│  - Serveix index.html               │
│  - API /api/info (Play + APKMirror) │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  PC CLIENT  (on hi ha el mòbil USB) │
│  adb_bridge.py  (Flask, port 5038)  │
│  escolta a 127.0.0.1:5038           │
│  - Executa adb localment            │
│  - Exposa API per al navegador      │
└──────────────┬──────────────────────┘
               │ USB
               ▼
        📱 Dispositiu Android
```

> El servidor central (`server.py`) **no necessita tenir cap dispositiu Android connectat**. Només serveix la interfície web i consulta informació externa (Play Store, APKMirror). Tota la comunicació ADB es fa des del PC client a través del bridge local.

---

## Fitxers del projecte

| Fitxer | Ubicació | Descripció |
|---|---|---|
| `server.py` | Servidor Linux | Backend Flask central. Serveix la web i l'API d'informació d'apps. |
| `index.html` | Servidor Linux | Interfície web completa (HTML/CSS/JS). |
| `adb_bridge.py` | PC client (Windows) | Agent local que executa les comandes ADB i les exposa via HTTP. |
| `install_agent.ps1` | Servidor Linux | Wizard PowerShell d'instal·lació i gestió del servei Windows. |
| `README.md` | Servidor Linux | Aquest document. |

---

## Servidor (`server.py`)

### Requisits
- Python 3.10+
- Flask: `pip install flask`

### Execució
```bash
cd /var/www/html
python3 server.py
```

Escolta a `http://0.0.0.0:5000` (accessible des de tota la LAN).

### Execució com a servei systemd (arrencada automàtica)

```ini
# /etc/systemd/system/android-adware-hunter.service
[Unit]
Description=Android Adware Hunter Web Server
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/html
ExecStart=/usr/bin/python3 /var/www/html/server.py
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now android-adware-hunter.service
```

### Endpoints del servidor

| Mètode | Ruta | Descripció |
|---|---|---|
| `GET` | `/` | Serveix `index.html` |
| `GET` | `/api/info?package=<pkg>` | Consulta nom, descripció i resultats de Google Play Store i APKMirror |

---

## Bridge local (`adb_bridge.py`)

### Descripció

Agent lleuger que s'executa al **PC del client** (on hi ha el dispositiu Android connectat per USB). Exposa una API HTTP local (`127.0.0.1:5038`) que el navegador crida directament.

### Requisits (PC client Windows)
- Python 3.x instal·lat i al PATH
- `adb` instal·lat i accessible des de la consola
- Flask: `pip install flask` o `py -3 -m pip install flask`
- Dispositiu Android amb **depuració USB activada** i **autorització concedida**

### Execució
```powershell
cd C:\temp
py -3 adb_bridge.py
```

Ha d'aparèixer:
```
ADB Local Bridge on http://127.0.0.1:5038
```

### Execució com a servei Windows (instal·lació automàtica)

L'instal·lador configura `adb_bridge.py` com a **servei Windows real** utilitzant [NSSM](https://nssm.cc/) (`C:\temp\nssm.exe`).

- **Inici:** Automàtic (arrenca amb Windows, sense necessitat de login)
- **Nom del servei:** `AdbBridgeAgent`
- **Log:** `C:\temp\adb_bridge.log` (rotació automàtica a 1 MB)
- **Gestió:** des de `services.msc` o PowerShell com a Administrador:

```powershell
Start-Service AdbBridgeAgent
Stop-Service AdbBridgeAgent
Restart-Service AdbBridgeAgent
Get-Service AdbBridgeAgent
```

### Endpoints del bridge

| Mètode | Ruta | Descripció |
|---|---|---|
| `GET` | `/api/check-device` | Comprova si hi ha un dispositiu ADB autoritzat |
| `GET` | `/api/device-info` | Model, marca, Android, SDK, CPU, RAM, resolució, número de sèrie |
| `GET` | `/api/list-apps` | Llista totes les apps de tercers instal·lades |
| `GET` | `/api/foreground` | Retorna el package de l'app en primer pla |
| `POST` | `/api/kill` | Força l'aturada d'un procés (`am force-stop`) |
| `POST` | `/api/start` | Inicia una app (`monkey -c LAUNCHER`) |
| `POST` | `/api/uninstall` | Desinstal·la una app per a l'usuari 0 |

---

## Interfície web (`index.html`)

### Funcionalitats

- **Comprovar dispositiu** — Verifica la connexió ADB i mostra les característiques de hardware i software del dispositiu.
- **Llistar apps** — Mostra totes les aplicacions de tercers instal·lades, ordenades alfabèticament. Si s'ha consultat informació prèviament, mostra el nom resolt en groc.
- **Cercar apps** — Filtre en temps real sobre el llistat.
- **Detectar app en foreground** — Identifica i selecciona automàticament l'app que l'usuari té oberta al mòbil.
- **Obtenir informació** — Consulta el nom, descripció i resultats de Google Play Store i APKMirror per al package seleccionat.
- **Matar procés** — Força l'aturada de l'app seleccionada.
- **Iniciar procés** — Llança l'app seleccionada.
- **Desinstal·lar package** — Desinstal·la l'app amb confirmació prèvia.
- **Menú contextual** — Clic dret sobre qualsevol app del llistat per accedir a totes les accions. El menú s'ajusta automàticament per no sortir dels límits de la pantalla.

### Configuració del bridge local

A la part superior del panell dret hi ha el camp **ADB local** amb el valor per defecte `http://127.0.0.1:5038`. Es pot modificar si el bridge escolta en un altre port. El valor es desa automàticament al `localStorage` del navegador.

---

## Passos del client per connectar-se

### 1. Preparar el dispositiu Android
- Activar **Opcions de desenvolupador** al mòbil.
- Activar **Depuració USB**.
- Connectar el mòbil al PC per USB.
- Acceptar el missatge d'autorització que apareix al mòbil.

### 2. Instal·lar i arrencar l'Agent (primera vegada)

Obre **PowerShell com a Administrador** i executa aquesta única comanda:

```powershell
$f="$env:TEMP\install_agent.ps1"; (New-Object Net.WebClient).DownloadFile("http://192.168.0.6:5000/install_agent.ps1",$f); & $f
```

Si el PowerShell no és Administrador, l'assistent demanarà elevació (UAC) automàticament.

L'assistent instal·larà automàticament:
- Android Platform Tools (ADB) via `winget`
- Python 3 via `winget`
- Flask i flask-cors via `pip`
- L'agent `adb_bridge.py` a `C:\temp`
- **NSSM** (`C:\temp\nssm.exe`) per registrar el servei Windows
- El servei **`AdbBridgeAgent`** (inici automàtic amb Windows)
- Un accés directe a l'escriptori (opcional)

Al final preguntarà si vols arrencar l'Agent immediatament.

> El botó **"Connecta ADB local"** de la interfície web copia aquesta comanda al porta-retalls.

### 3. Properes vegades (Agent ja instal·lat)

Fes doble clic a l'accés directe **Android Adware Hunter PRO** de l'escriptori. L'script verificarà que tots els components estan correctes i et preguntarà si vols arrancar el servei.

O bé, directament des de PowerShell com a Administrador:

```powershell
Start-Service AdbBridgeAgent
```

### 4. Obrir la interfície web
```
http://192.168.0.6:5000
```

### 5. Comprovar dispositiu
Fer clic a **Comprovar dispositiu** a la capçalera. Si tot és correcte apareixerà un missatge verd i les dades del dispositiu.

---

## Seguretat

- Els noms de package es validen amb regex `[a-zA-Z0-9_.]+` abans d'executar qualsevol comanda ADB, evitant injeccions de comandes.
- El bridge escolta **únicament a `127.0.0.1`** (loopback), no és accessible des de la xarxa.
- El servidor central no té accés directe al dispositiu Android.

---

## Llicència

Ús intern / privat.