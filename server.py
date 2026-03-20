"""
Android Adware Hunter PRO — Web Server
Executa al PC on hi ha el dispositiu Android connectat per USB.
Accessible des de qualsevol navegador de la LAN.

  pip install flask
  python server.py

Obre http://<IP_DEL_PC>:5000 des de qualsevol dispositiu de la xarxa.
"""

import subprocess
import re
import html as html_mod
import urllib.request
from flask import Flask, jsonify, request, send_from_directory

app = Flask(__name__, static_folder=".", static_url_path="")

# ── resolved names cache ──
_app_names: dict[str, str] = {}

# ── helpers ──

ALLOWED_ADB_COMMANDS = {
    "devices", "shell pm list packages -3", "shell dumpsys window",
}


def _is_safe_package(pkg: str) -> bool:
    """Only allow valid Android package names (letters, digits, dots, underscores)."""
    return bool(re.fullmatch(r"[a-zA-Z0-9_.]+", pkg))


def run_cmd(cmd: str) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, shell=True)
    return result.stdout.strip()


def fetch_page(url: str) -> str | None:
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept-Language": "ca,es,en;q=0.5",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except Exception:
        return None


def extract_meta(page: str | None, name: str) -> str | None:
    if not page:
        return None
    match = re.search(
        rf'<meta\s[^>]*(?:name|property)=["\'](?:og:)?{name}["\'][^>]*content=["\']([^"\']+)["\']',
        page, re.IGNORECASE,
    )
    if not match:
        match = re.search(
            rf'<meta\s[^>]*content=["\']([^"\']+)["\'][^>]*(?:name|property)=["\'](?:og:)?{name}["\']',
            page, re.IGNORECASE,
        )
    return html_mod.unescape(match.group(1).strip()) if match else None


def extract_title(page: str | None) -> str | None:
    if not page:
        return None
    match = re.search(r"<title[^>]*>([^<]+)</title>", page, re.IGNORECASE)
    return html_mod.unescape(match.group(1).strip()) if match else None


# ── routes ──

@app.route("/favicon.ico")
def favicon():
    return "", 204


@app.route("/")
def index():
    return send_from_directory(".", "index.html")


@app.route("/api/check-device")
def api_check_device():
    output = run_cmd("adb devices")
    found = any("\tdevice" in line for line in output.splitlines())
    return jsonify({"connected": found})


@app.route("/api/list-apps")
def api_list_apps():
    output = run_cmd("adb shell pm list packages -3")
    apps = []
    for line in output.splitlines():
        pkg = line.replace("package:", "").strip()
        if pkg:
            apps.append({"pkg": pkg, "name": _app_names.get(pkg)})
    apps.sort(key=lambda x: (x["name"] or x["pkg"]).lower())
    return jsonify(apps)


@app.route("/api/device-info")
def api_device_info():
    def prop(key):
        return run_cmd(f"adb shell getprop {key}").strip()

    model      = prop("ro.product.model")
    brand      = prop("ro.product.brand")
    android    = prop("ro.build.version.release")
    sdk        = prop("ro.build.version.sdk")
    build      = prop("ro.build.display.id")
    cpu        = prop("ro.product.cpu.abi")
    serial     = run_cmd("adb get-serialno").strip()

    # RAM
    mem_raw = run_cmd("adb shell cat /proc/meminfo")
    ram = ""
    for line in mem_raw.splitlines():
        if line.startswith("MemTotal"):
            try:
                kb = int(line.split()[1])
                ram = f"{round(kb / 1024 / 1024, 1)} GB"
            except Exception:
                ram = line.split(":")[-1].strip()
            break

    # Resolution
    res_raw = run_cmd("adb shell wm size")
    resolution = res_raw.replace("Physical size:", "").strip() if res_raw else ""

    return jsonify({
        "model": model, "brand": brand, "android": android,
        "sdk": sdk, "build": build, "cpu": cpu,
        "ram": ram, "resolution": resolution, "serial": serial,
    })


@app.route("/api/foreground")
def api_foreground():
    output = run_cmd("adb shell dumpsys window")
    for line in output.splitlines():
        if "mCurrentFocus" in line:
            parts = line.split()
            for p in parts:
                if "/" in p:
                    return jsonify({"package": p.split("/")[0]})
    return jsonify({"package": None})


@app.route("/api/kill", methods=["POST"])
def api_kill():
    pkg = (request.json or {}).get("package", "")
    if not _is_safe_package(pkg):
        return jsonify({"error": "Package invàlid"}), 400
    run_cmd(f"adb shell am force-stop {pkg}")
    return jsonify({"ok": True, "message": f"{pkg} aturat"})


@app.route("/api/start", methods=["POST"])
def api_start():
    pkg = (request.json or {}).get("package", "")
    if not _is_safe_package(pkg):
        return jsonify({"error": "Package invàlid"}), 400
    run_cmd(f"adb shell monkey -p {pkg} -c android.intent.category.LAUNCHER 1")
    return jsonify({"ok": True, "message": f"{pkg} iniciat"})


@app.route("/api/uninstall", methods=["POST"])
def api_uninstall():
    pkg = (request.json or {}).get("package", "")
    if not _is_safe_package(pkg):
        return jsonify({"error": "Package invàlid"}), 400
    run_cmd(f"adb shell pm uninstall --user 0 {pkg}")
    return jsonify({"ok": True, "message": f"{pkg} desinstal·lat"})


@app.route("/api/info")
def api_info():
    pkg = request.args.get("package", "")
    if not _is_safe_package(pkg):
        return jsonify({"error": "Package invàlid"}), 400

    play_url = f"https://play.google.com/store/apps/details?id={pkg}&hl=ca"
    apk_url = f"https://www.apkmirror.com/?s={pkg}"

    play_page = fetch_page(play_url)
    apk_page = fetch_page(apk_url)

    resolved_name = None
    info = {"package": pkg, "play": {}, "apkmirror": []}

    # Play Store
    if play_page and "\u2019re sorry" not in play_page and "not found" not in play_page.lower():
        title = extract_meta(play_page, "title") or extract_title(play_page)
        desc = extract_meta(play_page, "description")
        if title:
            resolved_name = re.sub(r"\s*[-\u2013]\s*Apps? on Google Play.*$", "", title).strip()
            resolved_name = re.sub(r"\s*[-\u2013]\s*Aplicacions a Google Play.*$", "", resolved_name).strip()
            info["play"]["title"] = title
        if desc:
            info["play"]["description"] = desc[:300]

    # APKMirror
    if apk_page:
        results = re.findall(r'class="fontBlack[^"]*"[^>]*>\s*([^<]+)</a>', apk_page)
        seen = set()
        for r in results[:5]:
            name = html_mod.unescape(r.strip())
            if name not in seen:
                seen.add(name)
                info["apkmirror"].append(name)
                if not resolved_name:
                    resolved_name = name

    if resolved_name:
        _app_names[pkg] = resolved_name
        info["resolved_name"] = resolved_name

    return jsonify(info)


if __name__ == "__main__":
    print("Android Adware Hunter PRO — Web")
    print("Obre http://0.0.0.0:5000 des de qualsevol navegador de la LAN")
    app.run(host="0.0.0.0", port=5000, debug=False)
