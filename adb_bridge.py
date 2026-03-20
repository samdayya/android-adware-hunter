"""
ADB Local Bridge

Execucio al PC client (on hi ha Android + adb local).
Expose endpoints HTTP locals per ser consumits per la web remota.

  pip install flask
  python3 adb_bridge.py

Per defecte escolta a http://127.0.0.1:5038
"""

import subprocess
import re
from flask import Flask, jsonify, request

app = Flask(__name__)


def _is_safe_package(pkg: str) -> bool:
    return bool(re.fullmatch(r"[a-zA-Z0-9_.]+", pkg))


def run_cmd(cmd: str) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, shell=True)
    return result.stdout.strip()


@app.after_request
def add_cors_headers(resp):
    # Allow web UI hosted on another LAN machine to call this local bridge.
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return resp


@app.route("/api/check-device", methods=["GET", "OPTIONS"])
def api_check_device():
    if request.method == "OPTIONS":
        return ("", 204)
    output = run_cmd("adb devices")
    found = any("\tdevice" in line for line in output.splitlines())
    return jsonify({"connected": found})


@app.route("/api/list-apps", methods=["GET", "OPTIONS"])
def api_list_apps():
    if request.method == "OPTIONS":
        return ("", 204)
    output = run_cmd("adb shell pm list packages -3")
    apps = []
    for line in output.splitlines():
        pkg = line.replace("package:", "").strip()
        if pkg:
            apps.append({"pkg": pkg, "name": None})
    apps.sort(key=lambda x: x["pkg"].lower())
    return jsonify(apps)


@app.route("/api/device-info", methods=["GET", "OPTIONS"])
def api_device_info():
    if request.method == "OPTIONS":
        return ("", 204)

    def prop(key):
        return run_cmd(f"adb shell getprop {key}").strip()

    model      = prop("ro.product.model")
    brand      = prop("ro.product.brand")
    android    = prop("ro.build.version.release")
    sdk        = prop("ro.build.version.sdk")
    build      = prop("ro.build.display.id")
    cpu        = prop("ro.product.cpu.abi")
    serial     = run_cmd("adb get-serialno").strip()

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

    res_raw = run_cmd("adb shell wm size")
    resolution = res_raw.replace("Physical size:", "").strip() if res_raw else ""

    return jsonify({
        "model": model, "brand": brand, "android": android,
        "sdk": sdk, "build": build, "cpu": cpu,
        "ram": ram, "resolution": resolution, "serial": serial,
    })


@app.route("/api/foreground", methods=["GET", "OPTIONS"])
def api_foreground():
    if request.method == "OPTIONS":
        return ("", 204)
    output = run_cmd("adb shell dumpsys window")
    for line in output.splitlines():
        if "mCurrentFocus" in line:
            parts = line.split()
            for p in parts:
                if "/" in p:
                    return jsonify({"package": p.split("/")[0]})
    return jsonify({"package": None})


@app.route("/api/kill", methods=["POST", "OPTIONS"])
def api_kill():
    if request.method == "OPTIONS":
        return ("", 204)
    pkg = (request.json or {}).get("package", "")
    if not _is_safe_package(pkg):
        return jsonify({"error": "Package invalid"}), 400
    run_cmd(f"adb shell am force-stop {pkg}")
    return jsonify({"ok": True, "message": f"{pkg} aturat"})


@app.route("/api/start", methods=["POST", "OPTIONS"])
def api_start():
    if request.method == "OPTIONS":
        return ("", 204)
    pkg = (request.json or {}).get("package", "")
    if not _is_safe_package(pkg):
        return jsonify({"error": "Package invalid"}), 400
    run_cmd(f"adb shell monkey -p {pkg} -c android.intent.category.LAUNCHER 1")
    return jsonify({"ok": True, "message": f"{pkg} iniciat"})


@app.route("/api/uninstall", methods=["POST", "OPTIONS"])
def api_uninstall():
    if request.method == "OPTIONS":
        return ("", 204)
    pkg = (request.json or {}).get("package", "")
    if not _is_safe_package(pkg):
        return jsonify({"error": "Package invalid"}), 400
    run_cmd(f"adb shell pm uninstall --user 0 {pkg}")
    return jsonify({"ok": True, "message": f"{pkg} desinstallat"})


if __name__ == "__main__":
    print("ADB Local Bridge on http://127.0.0.1:5038")
    app.run(host="127.0.0.1", port=5038, debug=False)
