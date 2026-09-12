"""Home Assistant Walker helper.

Provides state synchronization, cache management, and service calls for the
Elephant Home Assistant Walker plugin.
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
CACHE_DIR = os.path.join(RUNTIME_DIR, "elephant-ha")
CACHE_FILE = os.path.join(CACHE_DIR, "states.json")

DATA_DIR = os.environ.get("XDG_DATA_HOME") or os.path.expanduser(
    "~/.local/share"
)
PINS_FILE = os.path.join(DATA_DIR, "elephant", "ha-pins")

INTERACTIVE_DOMAINS = {
    "light",
    "switch",
    "climate",
    "fan",
    "cover",
    "lock",
    "vacuum",
    "media_player",
    "scene",
    "script",
    "automation",
    "input_boolean",
    "button",
    "input_button",
    "input_select",
}

SENSOR_DEVICE_CLASSES = {
    "temperature",
    "humidity",
    "battery",
    "power",
    "door",
    "window",
    "motion",
    "presence",
    "occupancy",
    "opening",
}

DEFAULT_PINS = [
    "script.all_off",
    "script.feierabend",
    "script.bedtime",
    "cover.desk",
    "light.group_office",
    "light.group_living_room",
    "climate.homekit_tado_living_room",
    "vacuum.cthulhulu",
    "lock.front_door_2",
]


def notify(msg, icon="home"):
    """Send a desktop notification via notify-send."""
    try:
        subprocess.Popen(
            ["notify-send", "-a", "walker-menu", "-i", icon, msg],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def get_credentials():
    """Retrieve Home Assistant server URL and Long-Lived Access Token."""
    server = os.environ.get("HASS_SERVER")
    if not server:
        for path in [
            os.path.expanduser(
                "~/.config/sops-nix/secrets/home-assistant/server"
            ),
            "/run/secrets/home-assistant/server",
        ]:
            if os.path.isfile(path):
                try:
                    with open(path, "r", encoding="utf-8") as f:
                        server = f.read().strip()
                        if server:
                            break
                except Exception:
                    pass
    if not server:
        server = "https://ha.brkn.lol"

    token = os.environ.get("HASS_TOKEN")
    if not token:
        for path in [
            os.path.expanduser(
                "~/.config/sops-nix/secrets/home-assistant/token"
            ),
            "/run/secrets/home-assistant/token",
        ]:
            if os.path.isfile(path):
                try:
                    with open(path, "r", encoding="utf-8") as f:
                        token = f.read().strip()
                        if token:
                            break
                except Exception:
                    pass
    return server, token


def api_request(endpoint, method="GET", data=None, timeout=8):
    """Make an authenticated HTTP request to the Home Assistant REST API."""
    server, token = get_credentials()
    if not token:
        raise RuntimeError("No Home Assistant token found")
    url = f"{server.rstrip('/')}/api/{endpoint.lstrip('/')}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(
        url, data=body, headers=headers, method=method
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def load_pins():
    """Load the set of pinned entity IDs."""
    pins = set()
    if os.path.isfile(PINS_FILE):
        try:
            with open(PINS_FILE, "r", encoding="utf-8") as f:
                for line in f:
                    p = line.strip()
                    if p and not p.startswith("#"):
                        pins.add(p)
        except Exception:
            pass
    if not pins:
        pins = set(DEFAULT_PINS)
    return pins


def save_pins(pins):
    """Save pinned entity IDs to disk."""
    os.makedirs(os.path.dirname(PINS_FILE), exist_ok=True)
    with open(PINS_FILE, "w", encoding="utf-8") as f:
        for p in sorted(pins):
            f.write(f"{p}\n")


def toggle_pin(entity_id):
    """Toggle the pinned state of an entity."""
    pins = load_pins()
    if entity_id in pins:
        pins.remove(entity_id)
        msg = f"📌 Unpinned {entity_id}"
    else:
        pins.add(entity_id)
        msg = f"📌 Pinned {entity_id}"
    save_pins(pins)
    notify(msg)
    cache = load_cache()
    if cache:
        for item in cache:
            if item.get("id") == entity_id:
                item["pinned"] = entity_id in pins
        save_cache(cache)


def infer_area(eid, name):
    """Infer area name from entity ID or friendly name."""
    text = f"{eid} {name or ''}".lower()
    mapping = [
        ("master_bathroom", "Master Bathroom"),
        ("master bathroom", "Master Bathroom"),
        ("bathroom", "Bathroom"),
        ("bedroom_hall", "Bedroom Hall"),
        ("bedroom", "Bedroom"),
        ("kitchen", "Kitchen"),
        ("living_room", "Living Room"),
        ("living room", "Living Room"),
        ("office", "Office"),
        ("utility_room", "Utility Room"),
        ("utility room", "Utility Room"),
        ("balcony", "Balcony"),
        ("hallway", "Hallway"),
        ("entryway", "Entryway"),
        ("front_door", "Entryway"),
        ("rack", "Server Rack"),
    ]
    for key, label in mapping:
        if key in text:
            return label
    return ""


def format_entity(entity, pins):
    """Format an entity into a normalized structure for Walker."""
    eid = entity.get("entity_id", "")
    domain = eid.split(".", 1)[0]
    attrs = entity.get("attributes", {})
    state = entity.get("state", "unknown")
    name = attrs.get("friendly_name") or eid
    area = infer_area(eid, name)
    pinned = eid in pins

    icon = "🏠"
    subtext = (
        f"{domain.capitalize()} • {state} • {area or 'Home'}  "
        "[↵ Select • ^P Pin]"
    )
    keywords = [domain, eid, name.lower()]
    if area:
        keywords.append(area.lower())

    s_lower = (state or "").lower()

    if domain == "light":
        brightness = attrs.get("brightness")
        pct = round(brightness / 255 * 100) if brightness is not None else None
        if s_lower == "on":
            icon = "💡"
            pct_str = f" ({pct}%)" if pct is not None else ""
            subtext = (
                f"💡 ON{pct_str} • {area or 'Light'}  "
                "[↵ Toggle • ^U +15% • ^D -15% • ^P Pin]"
            )
            keywords.extend(["on", "lights"])
        else:
            icon = "🌑"
            subtext = f"🌑 OFF • {area or 'Light'}  [↵ Turn On • ^P Pin]"
            keywords.extend(["off", "lights"])

    elif domain in ("switch", "input_boolean"):
        if s_lower == "on":
            icon = "⚡"
            subtext = f"⚡ ON • {area or 'Switch'}  [↵ Toggle • ^P Pin]"
            keywords.extend(["on", "switch"])
        else:
            icon = "🔌"
            subtext = f"🔌 OFF • {area or 'Switch'}  [↵ Toggle • ^P Pin]"
            keywords.extend(["off", "switch"])

    elif domain == "fan":
        pct = attrs.get("percentage")
        pct_str = f" ({pct}%)" if pct is not None else ""
        if s_lower == "on":
            icon = "🌀"
            subtext = (
                f"🌀 ON{pct_str} • {area or 'Fan'}  "
                "[↵ Toggle • ^U +25% • ^D -25% • ^P Pin]"
            )
            keywords.extend(["on", "fan", "ventilation"])
        else:
            icon = "💨"
            subtext = f"💨 OFF • {area or 'Fan'}  [↵ Turn On • ^P Pin]"
            keywords.extend(["off", "fan", "ventilation"])

    elif domain == "climate":
        cur_temp = attrs.get("current_temperature")
        target_temp = attrs.get("temperature")
        humidity = attrs.get("current_humidity")
        keywords.extend(
            ["climate", "thermostat", "temp", "temperature", "heat", "tado"]
        )
        if s_lower in ("heat", "auto"):
            icon = "🔥"
            target_str = (
                f"Target: {target_temp}°C"
                if target_temp is not None
                else "Heat"
            )
            cur_str = f"{cur_temp}°C" if cur_temp is not None else ""
            hum_str = f" • 💧{humidity}%" if humidity is not None else ""
            subtext = (
                f"🔥 {cur_str} ({target_str}){hum_str} • "
                f"{area or 'Thermostat'}  "
                "[↵ Off • ^U +1°C • ^D -1°C • ^P Pin]"
            )
            keywords.append("heating")
        else:
            icon = "❄️"
            cur_str = (
                f" • Current: {cur_temp}°C" if cur_temp is not None else ""
            )
            hum_str = f" • 💧{humidity}%" if humidity is not None else ""
            subtext = (
                f"❄️ OFF{cur_str}{hum_str} • {area or 'Thermostat'}  "
                "[↵ Heat • ^U +1°C • ^P Pin]"
            )
            keywords.append("off")

    elif domain == "cover":
        is_desk = "desk" in eid.lower() or "desk" in name.lower()
        pos = attrs.get("current_position")
        pos_str = f" ({pos}%)" if pos is not None else ""
        keywords.extend(["cover", "shutter", "blind"])
        if is_desk:
            icon = "🪑"
            subtext = (
                f"🪑 Desk ({state.upper()}) • {area or 'Office'}  "
                "[↵ Toggle • ^U Stand • ^D Sit • ^P Pin]"
            )
            keywords.extend(["desk", "flexispot", "height", "stand", "sit"])
        else:
            icon = "🪟"
            subtext = (
                f"🪟 {state.upper()}{pos_str} • {area or 'Shutter'}  "
                "[↵ Toggle • ^U Open • ^D Close • ^P Pin]"
            )
            keywords.extend(["shutter", "window", "balcony"])

    elif domain == "lock":
        keywords.extend(["lock", "door"])
        if s_lower == "locked":
            icon = "🔒"
            subtext = f"🔒 Locked • {area or 'Door'}  [↵ Unlock • ^P Pin]"
            keywords.append("locked")
        else:
            icon = "🔓"
            subtext = f"🔓 UNLOCKED • {area or 'Door'}  [↵ Lock • ^P Pin]"
            keywords.extend(["unlocked", "open"])

    elif domain == "vacuum":
        battery = attrs.get("battery_level")
        bat_str = f" • 🔋{battery}%" if battery is not None else ""
        keywords.extend(["vacuum", "cleaner", "robot", "roomba", "cthulhulu"])
        if s_lower == "cleaning":
            icon = "🧹"
            subtext = f"🧹 Cleaning{bat_str}  [↵ Dock • ^D Dock • ^P Pin]"
            keywords.append("cleaning")
        else:
            icon = "🏠"
            subtext = (
                f"🏠 {state.capitalize()}{bat_str}  "
                "[↵ Clean • ^U Clean • ^P Pin]"
            )
            keywords.append(s_lower)

    elif domain == "media_player":
        title = attrs.get("media_title")
        artist = attrs.get("media_artist")
        vol = attrs.get("volume_level")
        vol_str = f" • Vol: {round(vol*100)}%" if vol is not None else ""
        track_str = f" • {title}" if title else ""
        if artist and title:
            track_str = f" • {artist} - {title}"
        keywords.extend(["media", "player", "music", "tv", "audio"])
        if s_lower == "playing":
            icon = "▶️"
            subtext = (
                f"▶️ Playing{track_str}{vol_str}  "
                "[↵ Pause • ^U Vol+ • ^D Vol- • ^P Pin]"
            )
            keywords.append("playing")
        elif s_lower == "paused":
            icon = "⏸️"
            subtext = (
                f"⏸️ Paused{track_str}{vol_str}  "
                "[↵ Play • ^U Vol+ • ^D Vol- • ^P Pin]"
            )
            keywords.append("paused")
        else:
            icon = "📺"
            subtext = (
                f"📺 {state.capitalize()} • {area or 'Media'}  "
                "[↵ Power • ^P Pin]"
            )
            keywords.append(s_lower)

    elif domain == "script":
        keywords.extend(["script", "run"])
        n_lower = name.lower()
        if "feierabend" in n_lower:
            icon = "🍻"
        elif "bedtime" in n_lower:
            icon = "💤"
        elif "all_off" in eid or "all off" in n_lower:
            icon = "🌑"
        elif "stand" in n_lower or "sit" in n_lower or "desk" in n_lower:
            icon = "🪑"
        elif "door" in n_lower or "buzz" in n_lower:
            icon = "🚪"
        elif "mute" in n_lower:
            icon = "🔇"
        else:
            icon = "📜"
        subtext = f"{icon} Script • {area or 'Home'}  [↵ Run Script • ^P Pin]"

    elif domain == "scene":
        icon = "🎬"
        subtext = f"🎬 Scene • {area or 'Home'}  [↵ Activate • ^P Pin]"
        keywords.extend(["scene", "activate"])

    elif domain in ("button", "input_button"):
        icon = "🔘"
        subtext = f"🔘 Button • {area or 'Home'}  [↵ Press • ^P Pin]"
        keywords.extend(["button", "press"])

    elif domain == "automation":
        icon = "⚙️"
        subtext = (
            f"⚙️ Automation ({state.upper()}) • {area or 'System'}  "
            "[↵ Toggle • ^P Pin]"
        )
        keywords.extend(["automation", state.lower()])

    elif domain in ("sensor", "binary_sensor"):
        dc = attrs.get("device_class", "")
        unit = attrs.get("unit_of_measurement", "")
        keywords.extend(["sensor", dc, unit])
        if "door" in dc or "window" in dc or "opening" in dc:
            icon = "🚪" if s_lower == "on" else "🔒"
            subtext = (
                f"{icon} {state.upper()} • {area or 'Sensor'}  "
                "[↵ Copy • ^P Pin]"
            )
        elif "motion" in dc or "presence" in dc or "occupancy" in dc:
            icon = "🚶" if s_lower == "on" else "⚪"
            subtext = (
                f"{icon} {state.upper()} • {area or 'Sensor'}  "
                "[↵ Copy • ^P Pin]"
            )
        elif "temperature" in dc or "temperature" in eid:
            icon = "🌡️"
            subtext = (
                f"🌡️ {state} {unit} • {area or 'Sensor'}  [↵ Copy • ^P Pin]"
            )
        elif "humidity" in dc or "humidity" in eid:
            icon = "💧"
            subtext = (
                f"💧 {state} {unit} • {area or 'Sensor'}  [↵ Copy • ^P Pin]"
            )
        elif "battery" in dc:
            icon = "🔋"
            subtext = (
                f"🔋 {state} {unit} • {area or 'Sensor'}  [↵ Copy • ^P Pin]"
            )
        elif "power" in dc or "energy" in dc or "watt" in eid:
            icon = "⚡"
            subtext = (
                f"⚡ {state} {unit} • {area or 'Sensor'}  [↵ Copy • ^P Pin]"
            )
        else:
            icon = "📊"
            subtext = (
                f"📊 {state} {unit} • {area or 'Sensor'}  [↵ Copy • ^P Pin]"
            )

    return {
        "id": eid,
        "name": name,
        "domain": domain,
        "state": state,
        "area": area,
        "icon": icon,
        "subtext": subtext,
        "keywords": " ".join(set(keywords)),
        "brightness": attrs.get("brightness"),
        "temperature": attrs.get("temperature"),
        "current_temperature": attrs.get("current_temperature"),
        "percentage": attrs.get("percentage"),
        "pinned": pinned,
    }


def sync_states():
    """Fetch states from Home Assistant and update local cache atomically."""
    pins = load_pins()
    try:
        raw_states = api_request("states")
    except Exception as e:
        sys.stderr.write(f"Failed to fetch HA states: {e}\n")
        return False

    filtered = []
    for s in raw_states:
        eid = s.get("entity_id", "")
        domain = eid.split(".", 1)[0]
        if domain in INTERACTIVE_DOMAINS:
            filtered.append(format_entity(s, pins))
        elif domain in ("sensor", "binary_sensor"):
            attrs = s.get("attributes", {})
            dc = attrs.get("device_class", "")
            if dc in SENSOR_DEVICE_CLASSES:
                filtered.append(format_entity(s, pins))

    save_cache(filtered)
    return True


def load_cache():
    """Load cached entities from disk."""
    if os.path.isfile(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return None


def save_cache(data):
    """Save cached entities to disk atomically."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = f"{CACHE_FILE}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, CACHE_FILE)


def call_service(domain, service, payload, optimistic_state=None):
    """Call a Home Assistant service with optimistic cache update."""
    eid = payload.get("entity_id")
    cache = load_cache()
    if cache and eid:
        for item in cache:
            if item.get("id") == eid:
                if optimistic_state:
                    item.update(optimistic_state)
                break
        save_cache(cache)

    try:
        api_request(
            f"services/{domain}/{service}", method="POST", data=payload
        )
        return True
    except Exception as e:
        sys.stderr.write(f"Service call failed: {e}\n")
        return False


def action_toggle(eid):
    """Toggle an entity state."""
    domain = eid.split(".", 1)[0]
    cache = load_cache() or []
    item = next((x for x in cache if x["id"] == eid), None)
    cur_state = item["state"] if item else "unknown"

    if domain == "light":
        new_state = "off" if cur_state == "on" else "on"
        pct = (
            round((item.get("brightness") or 255) / 255 * 100)
            if item
            else 100
        )
        if new_state == "on":
            sub = (
                f"💡 ON ({pct}%) • {item.get('area') or 'Light'}  "
                "[↵ Toggle • ^U +15% • ^D -15% • ^P Pin]"
                if item
                else "💡 ON"
            )
            opt = {"state": "on", "icon": "💡", "subtext": sub}
        else:
            sub = (
                f"🌑 OFF • {item.get('area') or 'Light'}  "
                "[↵ Turn On • ^P Pin]"
                if item
                else "🌑 OFF"
            )
            opt = {"state": "off", "icon": "🌑", "subtext": sub}
        call_service(
            "light", "toggle", {"entity_id": eid}, optimistic_state=opt
        )
        notify(f"💡 {item['name'] if item else eid}: {new_state.upper()}")
    elif domain in ("switch", "input_boolean"):
        new_state = "off" if cur_state == "on" else "on"
        if new_state == "on":
            sub = (
                f"⚡ ON • {item.get('area') or 'Switch'}  "
                "[↵ Toggle • ^P Pin]"
                if item
                else "⚡ ON"
            )
            opt = {"state": "on", "icon": "⚡", "subtext": sub}
        else:
            sub = (
                f"🔌 OFF • {item.get('area') or 'Switch'}  "
                "[↵ Toggle • ^P Pin]"
                if item
                else "🔌 OFF"
            )
            opt = {"state": "off", "icon": "🔌", "subtext": sub}
        call_service(
            domain, "toggle", {"entity_id": eid}, optimistic_state=opt
        )
        notify(f"⚡ {item['name'] if item else eid}: {new_state.upper()}")
    elif domain == "fan":
        new_state = "off" if cur_state == "on" else "on"
        pct = (item.get("percentage") or 50) if item else 50
        if new_state == "on":
            sub = (
                f"🌀 ON ({pct}%) • {item.get('area') or 'Fan'}  "
                "[↵ Toggle • ^U +25% • ^D -25% • ^P Pin]"
                if item
                else "🌀 ON"
            )
            opt = {"state": "on", "icon": "🌀", "subtext": sub}
        else:
            sub = (
                f"💨 OFF • {item.get('area') or 'Fan'}  "
                "[↵ Turn On • ^P Pin]"
                if item
                else "💨 OFF"
            )
            opt = {"state": "off", "icon": "💨", "subtext": sub}
        call_service("fan", "toggle", {"entity_id": eid}, optimistic_state=opt)
        notify(f"🌀 {item['name'] if item else eid}: {new_state.upper()}")
    elif domain == "climate":
        new_mode = "off" if cur_state == "heat" else "heat"
        cur = item.get("current_temperature") if item else None
        cur_str = f"Current: {cur}°C • " if cur is not None else ""
        tgt = (item.get("temperature") or 21.0) if item else 21.0
        if new_mode == "heat":
            ar = item.get("area") or "Thermostat"
            sub = (
                f"🔥 Heat ({tgt}°C) • {cur_str}{ar}  "
                "[↵ Turn Off • ^U +0.5°C • ^D -0.5°C • ^P Pin]"
                if item
                else "🔥 Heat"
            )
            opt = {"state": "heat", "icon": "🔥", "subtext": sub}
        else:
            sub = (
                f"❄️ OFF • {cur_str}{item.get('area') or 'Thermostat'}  "
                "[↵ Heat • ^U +1°C • ^P Pin]"
                if item
                else "❄️ OFF"
            )
            opt = {"state": "off", "icon": "❄️", "subtext": sub}
        call_service(
            "climate",
            "set_hvac_mode",
            {"entity_id": eid, "hvac_mode": new_mode},
            optimistic_state=opt,
        )
        notify(f"🌡️ {item['name'] if item else eid}: {new_mode.upper()}")
    elif domain == "cover":
        if "desk" in eid.lower():
            if cur_state == "open":
                call_service("script", "flexispot_sit", {})
                notify("🪑 Desk: Lowering to Sit height")
            else:
                call_service("script", "flexispot_stand", {})
                notify("🪑 Desk: Raising to Stand height")
        else:
            call_service("cover", "toggle", {"entity_id": eid})
            notify(f"🪟 {item['name'] if item else eid}: Toggled")
    elif domain == "lock":
        svc = "unlock" if cur_state == "locked" else "lock"
        new_st = "unlocked" if svc == "unlock" else "locked"
        ic = "🔓" if new_st == "unlocked" else "🔒"
        action_word = "Lock" if new_st == "unlocked" else "Unlock"
        sub = (
            f"{ic} {new_st.upper()} • {item.get('area') or 'Lock'}  "
            f"[↵ {action_word} • ^P Pin]"
            if item
            else f"{ic} {new_st.upper()}"
        )
        opt = {"state": new_st, "icon": ic, "subtext": sub}
        call_service("lock", svc, {"entity_id": eid}, optimistic_state=opt)
        notify(f"🔒 {item['name'] if item else eid}: {svc.upper()}ED")
    elif domain == "vacuum":
        if cur_state == "cleaning":
            call_service("vacuum", "return_to_base", {"entity_id": eid})
            notify(f"🧹 {item['name'] if item else eid}: Returning to base")
        else:
            call_service("vacuum", "start", {"entity_id": eid})
            notify(f"🧹 {item['name'] if item else eid}: Started cleaning")
    elif domain == "media_player":
        call_service("media_player", "media_play_pause", {"entity_id": eid})
        notify(f"▶️ {item['name'] if item else eid}: Play/Pause")
    elif domain == "script":
        script_name = eid.split(".", 1)[1]
        call_service("script", script_name, {})
        notify(f"📜 Ran script: {item['name'] if item else eid}")
    elif domain == "scene":
        call_service("scene", "turn_on", {"entity_id": eid})
        notify(f"🎬 Activated: {item['name'] if item else eid}")
    elif domain in ("button", "input_button"):
        call_service(domain, "press", {"entity_id": eid})
        notify(f"🔘 Pressed: {item['name'] if item else eid}")
    elif domain == "automation":
        call_service("automation", "toggle", {"entity_id": eid})
        notify(f"⚙️ Automation toggled: {item['name'] if item else eid}")
    elif domain in ("sensor", "binary_sensor"):
        action_copy(eid)


def action_up(eid):
    """Increase value / speed / temp / brightness or open device."""
    domain = eid.split(".", 1)[0]
    cache = load_cache() or []
    item = next((x for x in cache if x["id"] == eid), None)

    if domain == "climate":
        cur = (item.get("temperature") or 21.0) if item else 21.0
        new_temp = round(cur + 0.5, 1)
        cur_t = item.get("current_temperature") if item else None
        cur_str = f"Current: {cur_t}°C • " if cur_t is not None else ""
        ar = item.get("area") or "Thermostat"
        sub = (
            f"🔥 Heat ({new_temp}°C) • {cur_str}{ar}  "
            "[↵ Turn Off • ^U +0.5°C • ^D -0.5°C • ^P Pin]"
            if item
            else f"🔥 Heat ({new_temp}°C)"
        )
        opt = {
            "state": "heat",
            "icon": "🔥",
            "temperature": new_temp,
            "subtext": sub,
        }
        call_service(
            "climate",
            "set_temperature",
            {"entity_id": eid, "temperature": new_temp},
            optimistic_state=opt,
        )
        notify(f"🌡️ {item['name'] if item else eid}: Target {new_temp}°C")
    elif domain == "light":
        cur_pct = (
            round((item.get("brightness") or 0) / 255 * 100) if item else 0
        )
        new_pct = min(100, cur_pct + 15)
        new_b = round(new_pct / 100 * 255)
        sub = (
            f"💡 ON ({new_pct}%) • {item.get('area') or 'Light'}  "
            "[↵ Toggle • ^U +15% • ^D -15% • ^P Pin]"
            if item
            else f"💡 ON ({new_pct}%)"
        )
        opt = {"state": "on", "icon": "💡", "brightness": new_b, "subtext": sub}
        call_service(
            "light",
            "turn_on",
            {"entity_id": eid, "brightness_step_pct": 15},
            optimistic_state=opt,
        )
        notify(f"💡 {item['name'] if item else eid}: Brightness +15%")
    elif domain == "fan":
        cur_pct = (item.get("percentage") or 0) if item else 0
        new_pct = min(100, cur_pct + 25)
        sub = (
            f"🌀 ON ({new_pct}%) • {item.get('area') or 'Fan'}  "
            "[↵ Toggle • ^U +25% • ^D -25% • ^P Pin]"
            if item
            else f"🌀 ON ({new_pct}%)"
        )
        opt = {
            "state": "on",
            "icon": "🌀",
            "percentage": new_pct,
            "subtext": sub,
        }
        call_service(
            "fan",
            "set_percentage",
            {"entity_id": eid, "percentage": new_pct},
            optimistic_state=opt,
        )
        notify(f"🌀 {item['name'] if item else eid}: Fan speed {new_pct}%")
    elif domain == "cover":
        if "desk" in eid.lower():
            call_service("script", "flexispot_stand", {})
            notify("🪑 Desk: Stand preset activated")
        else:
            call_service("cover", "open_cover", {"entity_id": eid})
            notify(f"🪟 {item['name'] if item else eid}: Opening")
    elif domain == "vacuum":
        call_service("vacuum", "start", {"entity_id": eid})
        notify(f"🧹 {item['name'] if item else eid}: Clean")
    elif domain == "media_player":
        call_service("media_player", "volume_up", {"entity_id": eid})
        notify(f"🔊 {item['name'] if item else eid}: Volume Up")


def action_down(eid):
    """Decrease value / speed / temp / brightness or close device."""
    domain = eid.split(".", 1)[0]
    cache = load_cache() or []
    item = next((x for x in cache if x["id"] == eid), None)

    if domain == "climate":
        cur = (item.get("temperature") or 21.0) if item else 21.0
        new_temp = round(cur - 0.5, 1)
        cur_t = item.get("current_temperature") if item else None
        cur_str = f"Current: {cur_t}°C • " if cur_t is not None else ""
        ar = item.get("area") or "Thermostat"
        sub = (
            f"🔥 Heat ({new_temp}°C) • {cur_str}{ar}  "
            "[↵ Turn Off • ^U +0.5°C • ^D -0.5°C • ^P Pin]"
            if item
            else f"🔥 Heat ({new_temp}°C)"
        )
        opt = {
            "state": "heat",
            "icon": "🔥",
            "temperature": new_temp,
            "subtext": sub,
        }
        call_service(
            "climate",
            "set_temperature",
            {"entity_id": eid, "temperature": new_temp},
            optimistic_state=opt,
        )
        notify(f"🌡️ {item['name'] if item else eid}: Target {new_temp}°C")
    elif domain == "light":
        cur_pct = (
            round((item.get("brightness") or 0) / 255 * 100) if item else 0
        )
        new_pct = max(0, cur_pct - 15)
        new_b = round(new_pct / 100 * 255)
        sub = (
            f"💡 ON ({new_pct}%) • {item.get('area') or 'Light'}  "
            "[↵ Toggle • ^U +15% • ^D -15% • ^P Pin]"
            if item
            else f"💡 ON ({new_pct}%)"
        )
        opt = {"state": "on", "icon": "💡", "brightness": new_b, "subtext": sub}
        call_service(
            "light",
            "turn_on",
            {"entity_id": eid, "brightness_step_pct": -15},
            optimistic_state=opt,
        )
        notify(f"💡 {item['name'] if item else eid}: Brightness -15%")
    elif domain == "fan":
        cur_pct = (item.get("percentage") or 0) if item else 0
        new_pct = max(0, cur_pct - 25)
        sub = (
            f"🌀 ON ({new_pct}%) • {item.get('area') or 'Fan'}  "
            "[↵ Toggle • ^U +25% • ^D -25% • ^P Pin]"
            if item
            else f"🌀 ON ({new_pct}%)"
        )
        opt = {
            "state": "on",
            "icon": "🌀",
            "percentage": new_pct,
            "subtext": sub,
        }
        call_service(
            "fan",
            "set_percentage",
            {"entity_id": eid, "percentage": new_pct},
            optimistic_state=opt,
        )
        notify(f"🌀 {item['name'] if item else eid}: Fan speed {new_pct}%")
    elif domain == "cover":
        if "desk" in eid.lower():
            call_service("script", "flexispot_sit", {})
            notify("🪑 Desk: Sit preset activated")
        else:
            call_service("cover", "close_cover", {"entity_id": eid})
            notify(f"🪟 {item['name'] if item else eid}: Closing")
    elif domain == "vacuum":
        call_service("vacuum", "return_to_base", {"entity_id": eid})
        notify(f"🧹 {item['name'] if item else eid}: Returning to base")
    elif domain == "media_player":
        call_service("media_player", "volume_down", {"entity_id": eid})
        notify(f"🔉 {item['name'] if item else eid}: Volume Down")


def action_copy(eid):
    """Copy entity ID or sensor state to clipboard."""
    cache = load_cache() or []
    item = next((x for x in cache if x["id"] == eid), None)
    val = eid
    if item and item.get("domain") in ("sensor", "binary_sensor"):
        val = f"{item['name']}: {item['state']}"
    try:
        p = subprocess.Popen(["wl-copy"], stdin=subprocess.PIPE)
        p.communicate(input=val.encode("utf-8"))
        notify(f"📋 Copied: {val}")
    except Exception as e:
        sys.stderr.write(f"wl-copy failed: {e}\n")


def action_open(eid):
    """Open entity details/history page in the browser."""
    server, _ = get_credentials()
    url = f"{server.rstrip('/')}/history?entity_id={eid}"
    try:
        subprocess.Popen(
            ["xdg-open", url],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        notify(f"🌐 Opening {eid} in browser")
    except Exception as e:
        sys.stderr.write(f"xdg-open failed: {e}\n")


def action_set_temp(eid, temp_str):
    """Set thermostat target temperature."""
    try:
        temp = float(temp_str)
        cache = load_cache() or []
        item = next((x for x in cache if x["id"] == eid), None)
        name = item["name"] if item else eid
        cur = item.get("current_temperature") if item else None
        cur_str = f"Current: {cur}°C • " if cur is not None else ""
        ar = item.get("area") or "Thermostat"
        sub = (
            f"🔥 Heat ({temp}°C) • {cur_str}{ar}  "
            "[↵ Turn Off • ^U +0.5°C • ^D -0.5°C • ^P Pin]"
            if item
            else f"🔥 Heat ({temp}°C)"
        )
        opt = {
            "state": "heat",
            "icon": "🔥",
            "temperature": temp,
            "subtext": sub,
        }
        call_service(
            "climate",
            "set_temperature",
            {"entity_id": eid, "temperature": temp},
            optimistic_state=opt,
        )
        notify(f"🌡️ Set {name} -> {temp}°C")
    except ValueError:
        pass


def action_set_brightness(eid, pct_str):
    """Set light brightness percentage."""
    try:
        pct = int(pct_str)
        cache = load_cache() or []
        item = next((x for x in cache if x["id"] == eid), None)
        name = item["name"] if item else eid
        if pct <= 0:
            sub = (
                f"🌑 OFF • {item.get('area') or 'Light'}  "
                "[↵ Turn On • ^P Pin]"
                if item
                else "🌑 OFF"
            )
            opt = {
                "state": "off",
                "icon": "🌑",
                "subtext": sub,
                "brightness": 0,
            }
            call_service(
                "light", "turn_off", {"entity_id": eid}, optimistic_state=opt
            )
            notify(f"💡 Turned off {name}")
        else:
            pct = min(100, pct)
            b_val = round(pct / 100 * 255)
            sub = (
                f"💡 ON ({pct}%) • {item.get('area') or 'Light'}  "
                "[↵ Toggle • ^U +15% • ^D -15% • ^P Pin]"
                if item
                else f"💡 ON ({pct}%)"
            )
            opt = {
                "state": "on",
                "icon": "💡",
                "brightness": b_val,
                "subtext": sub,
            }
            call_service(
                "light",
                "turn_on",
                {"entity_id": eid, "brightness_pct": pct},
                optimistic_state=opt,
            )
            notify(f"💡 Set {name} brightness -> {pct}%")
    except ValueError:
        pass


def action_set_fan_speed(eid, pct_str):
    """Set fan speed percentage."""
    try:
        pct = int(pct_str)
        cache = load_cache() or []
        item = next((x for x in cache if x["id"] == eid), None)
        name = item["name"] if item else eid
        if pct <= 0:
            sub = (
                f"💨 OFF • {item.get('area') or 'Fan'}  "
                "[↵ Turn On • ^P Pin]"
                if item
                else "💨 OFF"
            )
            opt = {
                "state": "off",
                "icon": "💨",
                "subtext": sub,
                "percentage": 0,
            }
            call_service(
                "fan", "turn_off", {"entity_id": eid}, optimistic_state=opt
            )
            notify(f"🌀 Turned off {name}")
        else:
            pct = min(100, pct)
            sub = (
                f"🌀 ON ({pct}%) • {item.get('area') or 'Fan'}  "
                "[↵ Toggle • ^U +25% • ^D -25% • ^P Pin]"
                if item
                else f"🌀 ON ({pct}%)"
            )
            opt = {
                "state": "on",
                "icon": "🌀",
                "percentage": pct,
                "subtext": sub,
            }
            call_service(
                "fan",
                "set_percentage",
                {"entity_id": eid, "percentage": pct},
                optimistic_state=opt,
            )
            notify(f"🌀 Set {name} speed -> {pct}%")
    except ValueError:
        pass


def stream_events():
    """Stream state changes from Home Assistant SSE and update cache."""
    server, token = get_credentials()
    if not token:
        sys.stderr.write("No Home Assistant token found\n")
        sys.exit(1)

    url = f"{server.rstrip('/')}/api/stream"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "text/event-stream",
    }

    sys.stdout.write("Initializing Home Assistant states...\n")
    sys.stdout.flush()
    sync_states()

    cache_items = load_cache() or []
    cache_map = {item["id"]: item for item in cache_items}
    pins = load_pins()

    last_flush = time.time()
    last_disk_mtime = (
        os.path.getmtime(CACHE_FILE) if os.path.isfile(CACHE_FILE) else 0
    )
    last_pins_mtime = (
        os.path.getmtime(PINS_FILE) if os.path.isfile(PINS_FILE) else 0
    )
    dirty = False

    def flush_cache(force=False):
        nonlocal dirty, last_flush, last_disk_mtime
        now = time.time()
        if dirty and (force or (now - last_flush) >= 0.25):
            items_list = list(cache_map.values())
            save_cache(items_list)
            try:
                last_disk_mtime = os.path.getmtime(CACHE_FILE)
            except OSError:
                last_disk_mtime = now
            last_flush = now
            dirty = False

    while True:
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=60) as resp:
                sys.stdout.write("Connected to Home Assistant event stream.\n")
                sys.stdout.flush()
                for line in resp:
                    line_str = line.decode("utf-8", errors="replace").strip()
                    if not line_str or line_str == "data: ping":
                        continue
                    if line_str.startswith("data:"):
                        json_str = line_str[5:].strip()
                        if not json_str.startswith("{"):
                            continue
                        try:
                            payload = json.loads(json_str)
                        except Exception:
                            continue
                        if payload.get("event_type") == "state_changed":
                            event_data = payload.get("data", {})
                            eid = event_data.get("entity_id")
                            new_state = event_data.get("new_state")
                            if not eid:
                                continue

                            domain = eid.split(".", 1)[0]
                            if domain not in INTERACTIVE_DOMAINS:
                                if domain in ("sensor", "binary_sensor"):
                                    attrs = (new_state or {}).get(
                                        "attributes", {}
                                    )
                                    dc = attrs.get("device_class", "")
                                    if dc not in SENSOR_DEVICE_CLASSES:
                                        continue
                                else:
                                    continue

                            # Sync pins if changed on disk
                            try:
                                pins_mt = os.path.getmtime(PINS_FILE)
                            except OSError:
                                pins_mt = 0
                            if pins_mt > last_pins_mtime:
                                pins = load_pins()
                                last_pins_mtime = pins_mt

                            # Sync external disk cache updates
                            # (e.g. from action_toggle)
                            try:
                                disk_mt = os.path.getmtime(CACHE_FILE)
                            except OSError:
                                disk_mt = 0
                            if disk_mt > last_disk_mtime:
                                disk_items = load_cache() or []
                                for itm in disk_items:
                                    cache_map[itm["id"]] = itm
                                last_disk_mtime = disk_mt

                            if new_state is None:
                                if eid in cache_map:
                                    del cache_map[eid]
                                    dirty = True
                            else:
                                updated = format_entity(new_state, pins)
                                cache_map[eid] = updated
                                dirty = True

                            flush_cache(force=(domain in INTERACTIVE_DOMAINS))
                    if dirty and (time.time() - last_flush) >= 0.5:
                        flush_cache(force=True)
        except Exception as e:
            sys.stderr.write(f"Stream error: {e}. Reconnecting in 3s...\n")
            sys.stderr.flush()
            time.sleep(3)


def main():
    """Entrypoint for CLI commands."""
    if len(sys.argv) < 2:
        print(
            "Usage: ha-walker "
            "{sync|stream|toggle|up|down|pin|copy|open|call} ..."
        )
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "sync":
        ok = sync_states()
        sys.exit(0 if ok else 1)
    elif cmd in ("stream", "listen", "daemon"):
        stream_events()
    elif cmd in ("toggle", "t") and len(sys.argv) > 2:
        action_toggle(sys.argv[2])
    elif cmd == "up" and len(sys.argv) > 2:
        action_up(sys.argv[2])
    elif cmd == "down" and len(sys.argv) > 2:
        action_down(sys.argv[2])
    elif cmd in ("pin", "toggle-pin") and len(sys.argv) > 2:
        toggle_pin(sys.argv[2])
    elif cmd == "copy" and len(sys.argv) > 2:
        action_copy(sys.argv[2])
    elif cmd == "open" and len(sys.argv) > 2:
        action_open(sys.argv[2])
    elif cmd == "set-temp" and len(sys.argv) > 3:
        action_set_temp(sys.argv[2], sys.argv[3])
    elif cmd == "set-brightness" and len(sys.argv) > 3:
        action_set_brightness(sys.argv[2], sys.argv[3])
    elif cmd in ("set-fan-speed", "set-speed") and len(sys.argv) > 3:
        action_set_fan_speed(sys.argv[2], sys.argv[3])
    elif cmd == "call" and len(sys.argv) > 3:
        domain = sys.argv[2]
        service = sys.argv[3]
        payload = json.loads(sys.argv[4]) if len(sys.argv) > 4 else {}
        call_service(domain, service, payload)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
