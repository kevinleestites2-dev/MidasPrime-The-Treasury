#!/usr/bin/env python3
"""
ZEROTAP BRAIN — Qwen2.5:1.5B via Ollama
Fast command interpreter for ZeroTap phone control.

Usage:
    python3 zerotap_brain.py "open whatsapp"
    python3 zerotap_brain.py "call Joe"
    python3 zerotap_brain.py "text Healy I'm on my way"
    python3 zerotap_brain.py "scroll down"
    python3 zerotap_brain.py "go back"

Response is always JSON — fast, structured, executable.
"""

import sys
import json
import urllib.request
import ssl
import os

# ─── CONFIG ──────────────────────────────────────────────────
OLLAMA_URL = os.environ.get("OLLAMA_URL", "https://PASTE-CODESPACE-URL-HERE")
MODEL = "qwen2.5:1.5b"

SYSTEM_PROMPT = """You are NEXUS Command — the ZeroTap brain.
Your ONLY job: parse a voice/text command into a structured JSON action.

Respond ONLY with raw JSON. No explanation. No markdown. No preamble.

ACTION TYPES:
- open_app       : {action: "open_app", app: "<name>"}
- tap            : {action: "tap", x: <int>, y: <int>}
- swipe          : {action: "swipe", direction: "up|down|left|right"}
- type_text      : {action: "type_text", text: "<text>"}
- call           : {action: "call", contact: "<name>"}
- send_message   : {action: "send_message", app: "whatsapp|sms", contact: "<name>", message: "<text>"}
- go_back        : {action: "go_back"}
- go_home        : {action: "go_home"}
- screenshot     : {action: "screenshot"}
- scroll         : {action: "scroll", direction: "up|down"}
- volume         : {action: "volume", direction: "up|down", steps: <int>}
- search         : {action: "search", query: "<text>"}
- unknown        : {action: "unknown", raw: "<original command>"}

Examples:
"open whatsapp" → {"action": "open_app", "app": "whatsapp"}
"call Joe" → {"action": "call", "contact": "Joe"}
"text Healy I'm on my way" → {"action": "send_message", "app": "whatsapp", "contact": "Healy", "message": "I'm on my way"}
"go back" → {"action": "go_back"}
"scroll down" → {"action": "scroll", "direction": "down"}
"take a screenshot" → {"action": "screenshot"}
"turn volume up 3" → {"action": "volume", "direction": "up", "steps": 3}
"search for pizza near me" → {"action": "search", "query": "pizza near me"}
"""

# ─── OLLAMA CALL ─────────────────────────────────────────────
def parse_command(user_command: str) -> dict:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_command}
        ],
        "stream": False,
        "options": {
            "temperature": 0.0,   # deterministic — commands need precision
            "num_predict": 64,    # short output only
        }
    }

    try:
        req = urllib.request.Request(
            f"{OLLAMA_URL}/api/chat",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib.request.urlopen(req, context=ctx, timeout=8) as resp:
            data = json.loads(resp.read())
            raw = data["message"]["content"].strip()

            # Strip markdown code fences if present
            if raw.startswith("```"):
                raw = raw.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

            result = json.loads(raw)
            return result

    except Exception as e:
        return {"action": "error", "message": str(e), "raw": user_command}


# ─── ADB EXECUTOR ────────────────────────────────────────────
ADB_PACKAGES = {
    "whatsapp": "com.whatsapp",
    "chrome": "com.android.chrome",
    "youtube": "com.google.android.youtube",
    "maps": "com.google.android.apps.maps",
    "gmail": "com.google.android.gm",
    "settings": "com.android.settings",
    "camera": "com.android.camera",
    "calculator": "com.android.calculator2",
    "calendar": "com.google.android.calendar",
    "termux": "com.termux",
    "play store": "com.android.vending",
    "contacts": "com.android.contacts",
    "phone": "com.android.dialer",
    "messages": "com.android.mms",
}

def execute_action(action: dict, adb_host: str = "localhost", adb_port: int = 5555) -> str:
    """
    Translate parsed action into ADB shell commands.
    Returns the adb command string (ready to run).
    """
    a = action.get("action", "unknown")

    if a == "open_app":
        app = action.get("app", "").lower()
        pkg = ADB_PACKAGES.get(app, None)
        if pkg:
            return f"adb shell monkey -p {pkg} -c android.intent.category.LAUNCHER 1"
        else:
            return f"adb shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER --es app_name \"{app}\""

    elif a == "tap":
        x, y = action.get("x", 540), action.get("y", 960)
        return f"adb shell input tap {x} {y}"

    elif a == "swipe":
        d = action.get("direction", "up")
        directions = {
            "up":    "adb shell input swipe 540 1400 540 400 300",
            "down":  "adb shell input swipe 540 400 540 1400 300",
            "left":  "adb shell input swipe 900 960 100 960 300",
            "right": "adb shell input swipe 100 960 900 960 300",
        }
        return directions.get(d, "adb shell input swipe 540 1400 540 400 300")

    elif a == "type_text":
        text = action.get("text", "").replace(" ", "%s").replace("'", "")
        return f"adb shell input text '{text}'"

    elif a == "call":
        contact = action.get("contact", "")
        return f"adb shell am start -a android.intent.action.CALL -d tel:{contact}"

    elif a == "send_message":
        contact = action.get("contact", "")
        message = action.get("message", "")
        app = action.get("app", "whatsapp")
        if app == "whatsapp":
            return f"adb shell am start -a android.intent.action.VIEW -d \"https://api.whatsapp.com/send?phone={contact}&text={message.replace(' ', '%20')}\""
        else:
            return f"adb shell am start -a android.intent.action.SENDTO -d sms: --es sms_body \"{message}\""

    elif a == "go_back":
        return "adb shell input keyevent KEYCODE_BACK"

    elif a == "go_home":
        return "adb shell input keyevent KEYCODE_HOME"

    elif a == "screenshot":
        return "adb shell screencap -p /sdcard/zerotap_screen.png && adb pull /sdcard/zerotap_screen.png ."

    elif a == "scroll":
        d = action.get("direction", "down")
        if d == "down":
            return "adb shell input swipe 540 1200 540 400 200"
        else:
            return "adb shell input swipe 540 400 540 1200 200"

    elif a == "volume":
        direction = action.get("direction", "up")
        steps = int(action.get("steps", 1))
        key = "KEYCODE_VOLUME_UP" if direction == "up" else "KEYCODE_VOLUME_DOWN"
        return " && ".join([f"adb shell input keyevent {key}"] * steps)

    elif a == "search":
        query = action.get("query", "").replace(" ", "+")
        return f"adb shell am start -a android.intent.action.WEB_SEARCH --es query \"{query}\""

    else:
        return f"# UNKNOWN ACTION: {action.get('raw', str(action))}"


# ─── MAIN ─────────────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 zerotap_brain.py \"your command here\"")
        sys.exit(1)

    command = " ".join(sys.argv[1:])
    print(f"\n🎙️  Command: {command}")
    print("🧠  Parsing...\n")

    action = parse_command(command)
    print(f"📦  Action:  {json.dumps(action, indent=2)}")

    adb_cmd = execute_action(action)
    print(f"\n⚡  ADB:     {adb_cmd}")
    print()
