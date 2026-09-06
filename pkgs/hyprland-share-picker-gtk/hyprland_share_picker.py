#!/usr/bin/env python3
"""A GTK4 screencast source picker for xdg-desktop-portal-hyprland."""

import atexit
import cairo
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path


WINDOW_ENTRY = re.compile(
    r"(?P<id>\d+)\[HC>]"
    r"(?P<class>.*?)\[HT>]"
    r"(?P<title>.*?)\[HE>]"
    r"(?:(?P<address>0x[0-9a-fA-F]+)\[HA>])?"
)
CONFIG_VALUE = re.compile(
    r"^\s*(scale|jpeg_quality|refresh_rate|columns"
    r"|mode|color|fill_opacity|border_size|border|dim_color|dim_factor)\s*=\s*(.+?)\s*$",
    re.MULTILINE,
)
# Keys of the `highlight { ... }` section, mapped onto their setting names.
HIGHLIGHT_KEYS = {
    "mode": "highlight_mode",
    "color": "highlight_color",
    "fill_opacity": "highlight_fill_opacity",
    "border": "highlight_border",
    "border_size": "highlight_border_size",
    "dim_color": "dim_color",
    "dim_factor": "dim_factor",
}
HIGHLIGHT_MODES = ("highlight", "dim")
BOOL_VALUES = {
    "true": True,
    "yes": True,
    "on": True,
    "1": True,
    "false": False,
    "no": False,
    "off": False,
    "0": False,
}
DEFAULT_CONFIG = {
    "scale": 0.35,
    "jpeg_quality": 78,
    "refresh_rate": 4.0,
    "columns": 1,
    "highlight_mode": "highlight",
    "highlight_color": "rgba(59, 130, 246, 1.0)",
    "highlight_fill_opacity": 0.22,
    "highlight_border": True,
    "highlight_border_size": 3,
    "dim_color": "rgba(0, 0, 0, 1.0)",
    "dim_factor": 0.5,
}


def picker_config_path():
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "hypr" / "xdph-picker-gtk.conf"


def parse_picker_config(value):
    """Read the small Hyprlang-style preview and highlight settings file safely."""
    settings = DEFAULT_CONFIG.copy()
    for name, raw_value in CONFIG_VALUE.findall(value):
        name = HIGHLIGHT_KEYS.get(name, name)
        raw_value = raw_value.strip()
        if name in ("scale", "refresh_rate", "highlight_fill_opacity", "dim_factor"):
            try:
                parsed = float(raw_value)
            except ValueError:
                continue
            if name == "scale" and 0.1 <= parsed <= 1.0:
                settings[name] = parsed
            elif name == "refresh_rate" and 0.5 <= parsed <= 30:
                settings[name] = parsed
            elif name in ("highlight_fill_opacity", "dim_factor") and 0.0 <= parsed <= 1.0:
                settings[name] = parsed
        elif name in ("jpeg_quality", "columns", "highlight_border_size"):
            try:
                parsed = int(raw_value)
            except ValueError:
                continue
            if name == "jpeg_quality" and 1 <= parsed <= 100:
                settings[name] = parsed
            elif name == "columns" and 1 <= parsed <= 12:
                settings[name] = parsed
            elif name == "highlight_border_size" and 1 <= parsed <= 30:
                settings[name] = parsed
        elif name == "highlight_border":
            parsed = BOOL_VALUES.get(raw_value.lower())
            if parsed is not None:
                settings[name] = parsed
        elif name == "highlight_mode":
            mode = raw_value.lower()
            if mode in HIGHLIGHT_MODES:
                settings[name] = mode
        elif name in ("highlight_color", "dim_color") and raw_value:
            settings[name] = raw_value
    return settings


def picker_config():
    try:
        return parse_picker_config(picker_config_path().read_text())
    except OSError:
        return DEFAULT_CONFIG.copy()


CONFIG_SETTINGS = picker_config()
PREVIEW_SETTINGS = CONFIG_SETTINGS
PREVIEW_REFRESH_MS = max(33, round(1000 / CONFIG_SETTINGS["refresh_rate"]))
PREVIEW_SCALE = str(CONFIG_SETTINGS["scale"])
PREVIEW_JPEG_QUALITY = str(CONFIG_SETTINGS["jpeg_quality"])
COLUMNS = CONFIG_SETTINGS["columns"]


def portal_selection(selection, allow_token):
    """Return the exact stdout record expected by XDPH."""
    return f"[SELECTION]{'r' if allow_token else ''}/{selection}\n"


def parse_window_list(value):
    """Parse XDPH's sanitized, portal-authorized window list."""
    return [
        {
            "id": match.group("id"),
            "class": match.group("class"),
            "title": match.group("title"),
            "address": match.group("address"),
        }
        for match in WINDOW_ENTRY.finditer(value or "")
    ]


def picker_state_path():
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    return state_home / "hyprland-share-picker-gtk" / "last-tab"


def last_tab():
    try:
        value = picker_state_path().read_text().strip()
        return value if value in {"screens", "regions", "windows"} else "screens"
    except OSError:
        return "screens"


def save_last_tab(name):
    try:
        path = picker_state_path()
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        path.write_text(f"{name}\n")
    except OSError:
        pass


def read_json(command):
    try:
        completed = subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2,
        )
        if completed.returncode == 0:
            return json.loads(completed.stdout)
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    return []


def monitors():
    return read_json(["hyprctl", "monitors", "-j"])


def client_for_entry(entry, client_list):
    """Find XDPH's portal entry in Hyprland's current client list."""
    if entry["address"]:
        by_address = next((client for client in client_list if client.get("address") == entry["address"]), None)
        if by_address is not None:
            return by_address

    by_title = [
        client
        for client in client_list
        if client.get("class") == entry["class"] and client.get("title") == entry["title"]
    ]
    if by_title:
        return by_title[0]

    by_class = [client for client in client_list if client.get("class") == entry["class"]]
    return by_class[0] if len(by_class) == 1 else None


def window_preview_command(client):
    stable_id = client.get("stableId") if client else None
    if stable_id is None:
        return None
    return ["grim", "-T", str(stable_id), "-s", PREVIEW_SCALE, "-t", "jpeg", "-q", PREVIEW_JPEG_QUALITY, "-"]


def workspace_details(client):
    workspace = client.get("workspace") or {}
    return workspace.get("id"), workspace.get("name") or "Unknown workspace"


def parse_region(value, monitor_list):
    """Convert slurp's global coordinates to the output-relative XDPH form."""
    fields = value.strip().split()
    if len(fields) != 5:
        return None

    output, x, y, width, height = fields
    try:
        x, y, width, height = (int(number) for number in (x, y, width, height))
    except ValueError:
        return None

    monitor = next((item for item in monitor_list if item.get("name") == output), None)
    if monitor is None or width <= 0 or height <= 0:
        return None

    return f"region:{output}@{x - monitor.get('x', 0)},{y - monitor.get('y', 0)},{width},{height}"


def hyprland_instance_signature():
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if his:
        return his
    hypr_dir = Path(f"/run/user/{os.getuid()}/hypr")
    if hypr_dir.is_dir():
        for entry in hypr_dir.iterdir():
            if (entry / ".socket.sock").exists():
                return entry.name
    return None


def hyprland_ipc_query(req_str):
    his = hyprland_instance_signature()
    if not his:
        return None
    sock_path = f"/run/user/{os.getuid()}/hypr/{his}/.socket.sock"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.2)
            s.connect(sock_path)
            s.sendall(req_str.encode("utf-8"))
            buf = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                buf += chunk
            return json.loads(buf.decode("utf-8"))
    except (OSError, socket.timeout, json.JSONDecodeError):
        return None


DEFAULT_HIGHLIGHT_RGBA = (0.2314, 0.5098, 0.9647, 1.0)


def parse_rgba_color(value, default=DEFAULT_HIGHLIGHT_RGBA):
    """Parse hex (#rgb, #rrggbb, #rrggbbaa) or rgb/rgba(...) into (r, g, b, a) float tuple."""
    if not value or not isinstance(value, str):
        return default
    value = value.strip().lower()

    if value.startswith("#"):
        hex_str = value.lstrip("#")
        try:
            if len(hex_str) == 3:
                r = int(hex_str[0] * 2, 16) / 255.0
                g = int(hex_str[1] * 2, 16) / 255.0
                b = int(hex_str[2] * 2, 16) / 255.0
                return (r, g, b, 1.0)
            elif len(hex_str) == 6:
                r = int(hex_str[0:2], 16) / 255.0
                g = int(hex_str[2:4], 16) / 255.0
                b = int(hex_str[4:6], 16) / 255.0
                return (r, g, b, 1.0)
            elif len(hex_str) == 8:
                r = int(hex_str[0:2], 16) / 255.0
                g = int(hex_str[2:4], 16) / 255.0
                b = int(hex_str[4:6], 16) / 255.0
                a = int(hex_str[6:8], 16) / 255.0
                return (r, g, b, a)
        except ValueError:
            return default

    m = re.match(
        r"^rgba?\s*\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*([\d.]+))?\s*\)$",
        value,
    )
    if m:
        try:
            r_val = float(m.group(1))
            g_val = float(m.group(2))
            b_val = float(m.group(3))
            r = (r_val / 255.0) if r_val > 1.0 else r_val
            g = (g_val / 255.0) if g_val > 1.0 else g_val
            b = (b_val / 255.0) if b_val > 1.0 else b_val
            a = float(m.group(4)) if m.group(4) is not None else 1.0
            return (r, g, b, a)
        except ValueError:
            return default

    return default


class OverlayHighlighter:
    """Renders slurp-like translucent box and crisp border overlays across monitors."""

    def __init__(self, layer_shell, gdk_module, gtk_module, config):
        self.layer_shell = layer_shell
        self.Gdk = gdk_module
        self.Gtk = gtk_module

        color_str = config.get("highlight_color")
        color_tuple = parse_rgba_color(color_str, DEFAULT_HIGHLIGHT_RGBA)
        self.r, self.g, self.b, _ = color_tuple
        self.fill_alpha = float(config.get("highlight_fill_opacity", 0.22))
        self.border_alpha = 0.95
        self.draw_border = bool(config.get("highlight_border", True))
        self.border_width = float(config.get("highlight_border_size", 3))

        self.mode = config.get("highlight_mode", "highlight")
        dim_tuple = parse_rgba_color(config.get("dim_color"), (0.0, 0.0, 0.0, 1.0))
        self.dim_r, self.dim_g, self.dim_b, _ = dim_tuple
        self.dim_alpha = float(config.get("dim_factor", 0.5))

        self.overlays = {}
        self.active_target = None

        if not self.layer_shell:
            return

        display = self.Gdk.Display.get_default()
        if display is None:
            return

        css = """
        window.overlay-highlighter {
            background-color: transparent;
            background: none;
            border: none;
            box-shadow: none;
        }
        """
        provider = self.Gtk.CssProvider()
        provider.load_from_data(css.encode("utf-8"))
        self.Gtk.StyleContext.add_provider_for_display(
            display,
            provider,
            self.Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        monitors = display.get_monitors()
        for i in range(monitors.get_n_items()):
            m = monitors.get_item(i)
            connector = m.get_connector()
            if not connector:
                continue
            geom = m.get_geometry()
            self._create_monitor_overlay(connector, m, geom)

    def _create_monitor_overlay(self, connector, gdk_mon, geom):
        win = self.Gtk.Window()
        win.add_css_class("overlay-highlighter")
        self.layer_shell.init_for_window(win)
        self.layer_shell.set_layer(win, self.layer_shell.Layer.OVERLAY)
        self.layer_shell.set_keyboard_mode(win, self.layer_shell.KeyboardMode.NONE)
        self.layer_shell.set_exclusive_zone(win, -1)
        self.layer_shell.set_namespace(win, "hyprland-share-picker-highlight")
        for edge in (
            self.layer_shell.Edge.TOP,
            self.layer_shell.Edge.BOTTOM,
            self.layer_shell.Edge.LEFT,
            self.layer_shell.Edge.RIGHT,
        ):
            self.layer_shell.set_anchor(win, edge, True)
        self.layer_shell.set_monitor(win, gdk_mon)

        area = self.Gtk.DrawingArea()
        entry = {
            "win": win,
            "area": area,
            "geom": geom,
            "active_rect": None,
            "exclude_rect": None,
            "dim_all": False,
        }

        def draw_func(_area, cr, width, height):
            cr.save()
            cr.set_operator(cairo.OPERATOR_CLEAR)
            cr.paint()
            cr.restore()

            rect = entry["active_rect"]
            if not rect and not entry.get("dim_all"):
                return

            exclude = entry.get("exclude_rect")

            # The picker dialog sits below this overlay layer, so clip it out of
            # everything we paint - fill, dim and border alike. Otherwise the
            # target's edges are stroked straight across the dialog.
            cr.save()
            if exclude:
                ex, ey, ew, eh = exclude
                cr.rectangle(0, 0, width, height)
                cr.rectangle(ex, ey, ew, eh)
                cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
                cr.clip()

            if self.mode == "dim":
                # Dim everything except the target.
                cr.save()
                cr.rectangle(0, 0, width, height)
                if rect:
                    rx, ry, rw, rh = rect
                    cr.rectangle(rx, ry, rw, rh)
                    cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
                cr.set_source_rgba(self.dim_r, self.dim_g, self.dim_b, self.dim_alpha)
                cr.fill()
                cr.restore()
            elif rect:
                # Translucent fill over the target (slurp style).
                rx, ry, rw, rh = rect
                cr.save()
                cr.rectangle(rx, ry, rw, rh)
                cr.set_source_rgba(self.r, self.g, self.b, self.fill_alpha)
                cr.fill()
                cr.restore()

            # Crisp solid border around the target (slurp style).
            if rect and self.draw_border:
                rx, ry, rw, rh = rect
                cr.save()
                cr.rectangle(rx, ry, rw, rh)
                cr.set_source_rgba(self.r, self.g, self.b, self.border_alpha)
                cr.set_line_width(self.border_width)
                cr.stroke()
                cr.restore()

            cr.restore()

        area.set_draw_func(draw_func)
        win.set_child(area)

        def set_empty_input(w):
            surf = w.get_surface()
            if surf is not None:
                surf.set_input_region(cairo.Region())

        win.connect("realize", set_empty_input)
        win.connect("map", set_empty_input)
        self.overlays[connector] = entry

    def highlight_screen(self, monitor_name):
        self.active_target = ("screen", monitor_name)
        picker_rect = self._get_picker_rect()

        for connector, entry in self.overlays.items():
            geom = entry["geom"]
            if connector == monitor_name:
                self._show(entry, (0, 0, geom.width, geom.height), picker_rect)
            else:
                self._hide(entry, picker_rect)

    def highlight_window(self, target_data):
        if not target_data:
            self.clear()
            return

        address = None
        entry_meta = None
        if isinstance(target_data, dict):
            address = target_data.get("address")
            entry_meta = target_data.get("entry")
        else:
            address = target_data

        self.active_target = ("window", address or (entry_meta.get("id") if entry_meta else None))

        clients = hyprland_ipc_query("j/clients") or []
        client = None
        if address:
            client = next((c for c in clients if c.get("address") == address), None)
        if not client and entry_meta:
            client = client_for_entry(entry_meta, clients)

        if not client or client.get("hidden") or not client.get("mapped", True):
            self.clear()
            return

        win_x, win_y = client.get("at", [0, 0])
        win_w, win_h = client.get("size", [0, 0])
        if win_w <= 0 or win_h <= 0:
            self.clear()
            return

        client_ws = client.get("workspace", {}).get("id")
        is_pinned = client.get("pinned", False)

        monitors_info = hyprland_ipc_query("j/monitors") or []
        mon_active_ws = {
            m.get("name"): m.get("activeWorkspace", {}).get("id")
            for m in monitors_info
        }

        picker_rect = self._get_picker_rect(clients)

        for connector, entry in self.overlays.items():
            geom = entry["geom"]
            rel_x = win_x - geom.x
            rel_y = win_y - geom.y

            active_ws = mon_active_ws.get(connector)
            ws_visible = is_pinned or (client_ws is not None and client_ws == active_ws)

            if (
                ws_visible
                and rel_x < geom.width
                and rel_x + win_w > 0
                and rel_y < geom.height
                and rel_y + win_h > 0
            ):
                self._show(entry, (rel_x, rel_y, win_w, win_h), picker_rect)
            else:
                self._hide(entry, picker_rect)

    def _show(self, entry, rect, picker_rect):
        """Paint `rect` (monitor-relative) as the target on this monitor."""
        geom = entry["geom"]
        entry["active_rect"] = rect
        entry["dim_all"] = False
        if picker_rect:
            px, py, pw, ph = picker_rect
            entry["exclude_rect"] = (px - geom.x, py - geom.y, pw, ph)
        else:
            entry["exclude_rect"] = None
        entry["win"].set_visible(True)
        entry["area"].queue_draw()

    def _hide(self, entry, picker_rect):
        """Drop the target on this monitor - in dim mode it stays fully dimmed."""
        geom = entry["geom"]
        dim_all = self.mode == "dim"
        if entry["active_rect"] is None and entry["dim_all"] == dim_all:
            return
        entry["active_rect"] = None
        entry["dim_all"] = dim_all
        if dim_all and picker_rect:
            px, py, pw, ph = picker_rect
            entry["exclude_rect"] = (px - geom.x, py - geom.y, pw, ph)
        else:
            entry["exclude_rect"] = None
        entry["win"].set_visible(dim_all)
        entry["area"].queue_draw()

    def _get_picker_rect(self, clients=None):
        if clients is None:
            clients = hyprland_ipc_query("j/clients") or []
        for c in clients:
            c_class = c.get("class", "")
            c_init = c.get("initialClass", "")
            if (
                "HyprlandSharePicker" in c_class
                or "hyprland-share-picker" in c_class
                or "HyprlandSharePicker" in c_init
            ):
                at = c.get("at")
                size = c.get("size")
                if at and size:
                    return (at[0], at[1], size[0], size[1])
        return None

    def clear(self):
        self.active_target = None
        for entry in self.overlays.values():
            if entry["active_rect"] is None and not entry["dim_all"]:
                continue
            entry["active_rect"] = None
            entry["dim_all"] = False
            entry["exclude_rect"] = None
            entry["win"].set_visible(False)
            entry["area"].queue_draw()

    def destroy_all(self):
        self.clear()
        for entry in self.overlays.values():
            entry["win"].close()
        self.overlays.clear()


def self_test():
    entries = parse_window_list("42[HC>]firefox[HT>]A tab[HE>]43[HC>]kitty[HT>]shell[HE>]0xabc[HA>]")
    assert entries == [
        {"id": "42", "class": "firefox", "title": "A tab", "address": None},
        {"id": "43", "class": "kitty", "title": "shell", "address": "0xabc"},
    ]
    assert client_for_entry(entries[0], [{"address": "0xdef", "class": "firefox", "title": "A tab"}]) == {
        "address": "0xdef",
        "class": "firefox",
        "title": "A tab",
    }
    assert window_preview_command({"stableId": "18000004"})[:3] == ["grim", "-T", "18000004"]
    assert parse_picker_config("preview {\n  scale = 0.5\n  jpeg_quality = 90\n  refresh_rate = 8\n}") == {
        "scale": 0.5,
        "jpeg_quality": 90,
        "refresh_rate": 8.0,
        "columns": 1,
        "highlight_mode": "highlight",
        "highlight_color": "rgba(59, 130, 246, 1.0)",
        "highlight_fill_opacity": 0.22,
        "highlight_border": True,
        "highlight_border_size": 3,
        "dim_color": "rgba(0, 0, 0, 1.0)",
        "dim_factor": 0.5,
    }
    assert parse_picker_config("columns = 3")["columns"] == 3
    assert parse_picker_config("columns = 0")["columns"] == 1
    highlight_section = parse_picker_config(
        "highlight {\n"
        "  mode = dim\n"
        "  color = #a855f7\n"
        "  fill_opacity = 0.4\n"
        "  border = false\n"
        "  border_size = 8\n"
        "  dim_color = #101010\n"
        "  dim_factor = 0.7\n"
        "}"
    )
    assert highlight_section["highlight_mode"] == "dim"
    assert highlight_section["highlight_color"] == "#a855f7"
    assert highlight_section["highlight_fill_opacity"] == 0.4
    assert highlight_section["highlight_border"] is False
    assert highlight_section["highlight_border_size"] == 8
    assert highlight_section["dim_color"] == "#101010"
    assert highlight_section["dim_factor"] == 0.7
    assert parse_picker_config("mode = nope")["highlight_mode"] == "highlight"
    assert parse_picker_config("dim_factor = 5")["dim_factor"] == 0.5
    assert parse_picker_config("border = no")["highlight_border"] is False
    assert parse_picker_config("border = maybe")["highlight_border"] is True
    assert parse_picker_config("border_size = 8")["highlight_border"] is True
    assert parse_picker_config("scale = 2\nrefresh_rate = nope") == DEFAULT_CONFIG
    assert portal_selection("window:42", True) == "[SELECTION]r/window:42\n"
    assert parse_region("DP-1 2048 120 640 480", [{"name": "DP-1", "x": 1920, "y": 0}]) == "region:DP-1@128,120,640,480"
    parsed_rgb = parse_rgba_color("#a855f7")
    assert abs(parsed_rgb[0] - 0.6588) < 0.01
    assert abs(parsed_rgb[1] - 0.3333) < 0.01
    assert abs(parsed_rgb[2] - 0.9686) < 0.01
    assert parsed_rgb[3] == 1.0


def load_gtk():
    import gi

    gi.require_version("Gdk", "4.0")
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gdk, Gio, GLib, Gtk

    try:
        gi.require_version("Gtk4LayerShell", "1.0")
        from gi.repository import Gtk4LayerShell
    except (ValueError, ImportError):
        Gtk4LayerShell = None

    return Gdk, Gio, GLib, Gtk, Gtk4LayerShell


def main():
    if "--self-test" in sys.argv:
        self_test()
        return

    Gdk, Gio, GLib, Gtk, Gtk4LayerShell = load_gtk()
    if "--runtime-check" in sys.argv:
        assert Gtk.ContentFit.COVER is not None
        assert Gdk.Texture.new_from_bytes is not None
        assert Gtk4LayerShell is not None
        if os.environ.get("WAYLAND_DISPLAY"):
            assert Gtk4LayerShell.is_supported(), "Gtk4LayerShell is not supported (check LD_PRELOAD)"
        return

    class SharePicker(Gtk.Application):
        def __init__(self):
            super().__init__(
                application_id="lol.brkn.HyprlandSharePicker",
                flags=Gio.ApplicationFlags.NON_UNIQUE,
            )
            self.add_main_option(
                "allow-token",
                0,
                GLib.OptionFlags.NONE,
                GLib.OptionArg.NONE,
                "Allow the portal to create a restore token",
                None,
            )
            self.selection = None
            self.monitor_list = monitors()
            self.allow_token = "--allow-token" in sys.argv
            self.config = CONFIG_SETTINGS
            self.has_submitted = False
            self.last_click_selection = None
            self.last_click_time = 0.0
            self.first_card = None
            self.share_button = None
            self.window = None
            self.stack = None
            self.tab_buttons = {}
            self.pick_button = None
            self.pick_button_icon = None
            self.pick_button_label = None
            self.window_flow = None
            self.window_card_states = []
            self.window_refreshing = threading.Event()
            self.highlighter = (
                OverlayHighlighter(
                    Gtk4LayerShell,
                    Gdk,
                    Gtk,
                    self.config,
                )
                if Gtk4LayerShell
                else None
            )
            self.hovered_target = None
            self.selected_target = None
            self.current_highlight = None
            atexit.register(self.clear_all_highlights)

        def do_shutdown(self):
            self.clear_all_highlights()
            if getattr(self, "highlighter", None):
                self.highlighter.destroy_all()
            super().do_shutdown()

        def target_for_card(self, selection, state, tab):
            if tab == "windows":
                return ("window", state) if state else None
            elif tab == "screens":
                monitor_name = selection.removeprefix("screen:") if selection else None
                return ("screen", monitor_name) if monitor_name else None
            return None

        def on_card_hover_enter(self, _controller, _x, _y, selection, state, tab):
            target = self.target_for_card(selection, state, tab)
            if target is not None:
                self.hovered_target = target
                self.update_highlight()

        def on_card_hover_leave(self, _controller, selection, state, tab):
            target = self.target_for_card(selection, state, tab)
            if self.hovered_target == target:
                self.hovered_target = None
                self.update_highlight()

        def update_highlight(self):
            active_tab = self.stack.get_visible_child_name() if self.stack else "windows"
            target = self.hovered_target
            if target is None and self.selected_target is not None:
                sel_type = self.selected_target[0]
                if (sel_type == "window" and active_tab == "windows") or (sel_type == "screen" and active_tab == "screens"):
                    target = self.selected_target

            if target == self.current_highlight:
                return

            if target is None:
                if getattr(self, "highlighter", None):
                    self.highlighter.clear()
                self.current_highlight = None
                return

            new_type, new_val = target
            if new_type == "window":
                if getattr(self, "highlighter", None):
                    self.highlighter.highlight_window(new_val)
                self.current_highlight = target
            elif new_type == "screen":
                if getattr(self, "highlighter", None):
                    self.highlighter.highlight_screen(new_val)
                self.current_highlight = target

        def clear_all_highlights(self):
            self.hovered_target = None
            if getattr(self, "highlighter", None):
                self.highlighter.clear()
            self.current_highlight = None

        def do_activate(self):
            if self.window is not None:
                self.window.present()
                return

            self.window = Gtk.ApplicationWindow(application=self, title="Share your screen")
            self.window.set_default_size(1180, 800)
            self.window.set_size_request(640, 460)
            self.window.add_css_class("share-picker")
            self.window.connect("close-request", self.on_close_request)

            key_controller = Gtk.EventControllerKey.new()
            key_controller.connect("key-pressed", self.on_key_pressed)
            self.window.add_controller(key_controller)

            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            header.set_margin_top(24)
            header.set_margin_bottom(18)
            header.set_margin_start(28)
            header.set_margin_end(28)
            title = Gtk.Label(label="Choose what to share", xalign=0)
            title.add_css_class("title-1")
            subtitle = Gtk.Label(
                label="Select an entire screen, a window, or a specific region. Previews update automatically.",
                xalign=0,
                wrap=True,
            )
            subtitle.add_css_class("dim-label")
            header.append(title)
            header.append(subtitle)
            content.append(header)

            stack = Gtk.Stack()
            stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
            stack.set_vexpand(True)
            stack.add_titled(self.make_window_page(), "windows", "Window")
            stack.add_titled(self.make_source_page(self.screen_cards()), "screens", "Screen")
            stack.add_titled(self.make_region_page(), "regions", "Region")
            self.stack = stack
            stack.set_visible_child_name(last_tab())
            stack.connect("notify::visible-child-name", self.on_tab_changed)

            switcher = self.make_tab_switcher()
            pick_button = self.make_pick_button()

            nav_bar = Gtk.CenterBox()
            nav_bar.set_margin_bottom(12)
            nav_bar.set_margin_start(28)
            nav_bar.set_margin_end(28)
            nav_bar.set_center_widget(switcher)
            nav_bar.set_end_widget(pick_button)
            content.append(nav_bar)
            content.append(stack)

            footer = Gtk.Box(spacing=12)
            footer.set_margin_top(16)
            footer.set_margin_bottom(20)
            footer.set_margin_start(28)
            footer.set_margin_end(28)

            token = Gtk.CheckButton(label="Remember this choice")
            token.set_active(self.allow_token)
            token.set_tooltip_text("Allow this application to reuse the chosen source later")
            token.connect("toggled", lambda button: setattr(self, "allow_token", button.get_active()))
            footer.append(token)

            footer.append(Gtk.Box(hexpand=True))
            cancel = Gtk.Button(label="Cancel")
            cancel.connect("clicked", lambda *_: self.quit())
            footer.append(cancel)
            self.share_button = Gtk.Button(label="Share")
            self.share_button.add_css_class("suggested-action")
            self.share_button.set_sensitive(False)
            self.share_button.connect("clicked", self.share)
            footer.append(self.share_button)
            content.append(footer)

            self.window.set_child(content)
            self.install_css()
            self.window.present()

        def make_tab_switcher(self):
            switcher = Gtk.Box(spacing=4)
            first_button = None
            for name, label, icon_name in [
                ("windows", "Window", "view-grid-symbolic"),
                ("screens", "Screen", "video-display-symbolic"),
                ("regions", "Region", "selection-rectangular-symbolic"),
            ]:
                button = Gtk.ToggleButton()
                if first_button is None:
                    first_button = button
                else:
                    button.set_group(first_button)
                button.set_active(self.stack.get_visible_child_name() == name)
                button.connect("toggled", self.on_tab_toggled, name)

                content = Gtk.Box(spacing=6)
                content.set_margin_top(5)
                content.set_margin_bottom(5)
                content.set_margin_start(10)
                content.set_margin_end(10)
                icon = Gtk.Image.new_from_icon_name(icon_name)
                icon.set_pixel_size(16)
                content.append(icon)
                content.append(Gtk.Label(label=label))
                button.set_child(content)
                switcher.append(button)
                self.tab_buttons[name] = button
            return switcher

        def make_pick_button(self):
            button = Gtk.Button()
            button.add_css_class("flat")
            button.connect("clicked", self.pick_active_source)
            content = Gtk.Box(spacing=6)
            content.set_margin_top(5)
            content.set_margin_bottom(5)
            content.set_margin_start(10)
            content.set_margin_end(10)
            self.pick_button_icon = Gtk.Image.new_from_icon_name("edit-select-symbolic")
            self.pick_button_icon.set_pixel_size(16)
            self.pick_button_label = Gtk.Label(label="Pick")
            content.append(self.pick_button_icon)
            content.append(self.pick_button_label)
            button.set_child(content)
            self.pick_button = button
            self.update_pick_button()
            return button

        def make_source_page(self, cards):
            flow = Gtk.FlowBox()
            flow.set_selection_mode(Gtk.SelectionMode.NONE)
            cols = self.config.get("columns", 1)
            flow.set_max_children_per_line(cols)
            flow.set_min_children_per_line(cols)
            flow.set_homogeneous(True)
            flow.set_column_spacing(14)
            flow.set_row_spacing(14)
            flow.set_margin_top(4)
            flow.set_margin_bottom(16)
            flow.set_margin_start(28)
            flow.set_margin_end(28)
            for card in cards:
                flow.append(card)
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            scroll.set_child(flow)
            return scroll

        def make_region_page(self):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
            box.set_halign(Gtk.Align.CENTER)
            box.set_valign(Gtk.Align.CENTER)
            box.set_vexpand(True)
            box.set_hexpand(True)
            box.set_margin_top(40)
            box.set_margin_bottom(40)

            icon = Gtk.Image.new_from_icon_name("selection-rectangular-symbolic")
            icon.set_pixel_size(48)
            box.append(icon)

            heading = Gtk.Label(label="Select a region")
            heading.add_css_class("title-2")
            box.append(heading)

            desc = Gtk.Label(
                label="Click and drag on any screen to select a specific rectangular area to share.",
                wrap=True,
            )
            desc.add_css_class("dim-label")
            box.append(desc)

            button = Gtk.Button(label="Draw region…")
            button.add_css_class("suggested-action")
            button.set_margin_top(8)
            button.connect("clicked", self.select_region)
            box.append(button)
            return box

        def make_window_page(self):
            allowed = parse_window_list(os.environ.get("XDPH_WINDOW_SHARING_LIST"))
            self.window_flow = Gtk.FlowBox()
            self.window_flow.set_selection_mode(Gtk.SelectionMode.NONE)
            cols = self.config.get("columns", 1)
            self.window_flow.set_max_children_per_line(cols)
            self.window_flow.set_min_children_per_line(cols)
            self.window_flow.set_homogeneous(True)
            self.window_flow.set_column_spacing(14)
            self.window_flow.set_row_spacing(14)
            self.window_flow.set_margin_top(4)
            self.window_flow.set_margin_bottom(16)
            self.window_flow.set_margin_start(28)
            self.window_flow.set_margin_end(28)

            if not allowed:
                self.window_flow.append(self.empty_state("No shareable windows are available."))
            else:
                client_list = read_json(["hyprctl", "clients", "-j"])
                for entry in allowed:
                    state = {"entry": entry, "address": entry["address"], "client": None}
                    self.update_window_state(state, client_list)
                    title = entry["title"] or entry["class"] or "Untitled window"
                    card = self.source_card(
                        f"window:{entry['id']}",
                        title,
                        entry["class"] or "Window",
                        lambda state=state: window_preview_command(state["client"]),
                        state,
                        "windows",
                    )
                    state["card"] = card
                    self.window_card_states.append(state)
                    self.window_flow.append(card)
                self.apply_window_metadata(client_list, read_json(["hyprctl", "activeworkspace", "-j"]))
                GLib.timeout_add(PREVIEW_REFRESH_MS, self.refresh_window_metadata)

            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            scroll.set_child(self.window_flow)
            return scroll

        def screen_cards(self):
            cards = []
            for monitor in self.monitor_list:
                name = monitor.get("name", "Unknown output")
                resolution = f"{monitor.get('width', '?')} × {monitor.get('height', '?')}"
                description = monitor.get("description") or resolution
                cards.append(
                    self.source_card(
                        f"screen:{name}",
                        name,
                        f"{description} · {resolution}",
                        ["grim", "-o", name, "-s", PREVIEW_SCALE, "-t", "jpeg", "-q", PREVIEW_JPEG_QUALITY, "-"],
                        tab="screens",
                    )
                )
            return cards

        def empty_state(self, label):
            card = Gtk.Box()
            card.set_size_request(360, 180)
            card.set_halign(Gtk.Align.CENTER)
            card.set_valign(Gtk.Align.CENTER)
            card.append(Gtk.Label(label=label, wrap=True))
            return card

        def source_card(self, selection, title, subtitle, preview_command, state=None, tab=None):
            card = Gtk.ToggleButton()
            card.add_css_class("source-card")
            card.set_hexpand(True)
            card.set_size_request(240, -1)
            if self.first_card is None:
                self.first_card = card
            else:
                card.set_group(self.first_card)
            card.connect("toggled", self.on_card_toggled, selection, state, tab)
            click = Gtk.GestureClick()
            click.set_button(1)
            click.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
            click.connect("pressed", self.on_card_pressed, selection)
            card.add_controller(click)

            motion = Gtk.EventControllerMotion.new()
            motion.connect("enter", self.on_card_hover_enter, selection, state, tab)
            motion.connect("leave", self.on_card_hover_leave, selection, state, tab)
            card.add_controller(motion)

            body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
            preview = Gtk.Picture()
            preview.add_css_class("preview")
            preview.set_can_shrink(True)
            preview.set_size_request(-1, 180)
            preview.set_content_fit(Gtk.ContentFit.COVER)
            preview.set_halign(Gtk.Align.FILL)
            body.append(preview)

            labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            labels.set_margin_bottom(12)
            labels.set_margin_start(14)
            labels.set_margin_end(14)
            name_label = Gtk.Label(label=title, xalign=0, ellipsize=3)
            name_label.add_css_class("heading")
            detail_label = Gtk.Label(label=subtitle, xalign=0, ellipsize=3)
            detail_label.add_css_class("dim-label")
            labels.append(name_label)
            labels.append(detail_label)
            body.append(labels)
            card.set_child(body)

            if state is not None:
                state["title_label"] = name_label
                state["detail_label"] = detail_label

            if preview_command is not None:
                self.load_preview(preview, preview_command, tab)
            return card

        def load_preview(self, picture, command, tab):
            is_capturing = threading.Event()

            def capture():
                if is_capturing.is_set():
                    return
                is_capturing.set()
                try:
                    preview_command = command() if callable(command) else command
                    if preview_command is None:
                        return
                    completed = subprocess.run(
                        preview_command,
                        check=False,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                        timeout=4,
                    )
                    data = completed.stdout if completed.returncode == 0 else b""
                except (OSError, subprocess.TimeoutExpired):
                    data = b""
                finally:
                    is_capturing.clear()
                GLib.idle_add(self.set_preview, picture, data)

            def refresh():
                if self.stack is not None and tab is not None and self.stack.get_visible_child_name() != tab:
                    return True
                threading.Thread(target=capture, daemon=True).start()
                return True

            refresh()
            GLib.timeout_add(PREVIEW_REFRESH_MS, refresh)

        @staticmethod
        def set_preview(picture, data):
            if data:
                try:
                    picture.set_paintable(Gdk.Texture.new_from_bytes(GLib.Bytes.new(data)))
                except GLib.Error:
                    pass
            return False

        def on_card_toggled(self, card, selection, state=None, tab=None):
            if card.get_active():
                self.selection = selection
                self.share_button.set_sensitive(True)
                self.selected_target = self.target_for_card(selection, state, tab)
                self.update_highlight()

        def on_card_pressed(self, _gesture, presses, _x, _y, selection):
            now = time.monotonic()
            is_double = (
                presses == 2
                or (self.last_click_selection == selection and (now - self.last_click_time) < 0.5)
            )
            self.last_click_selection = selection
            self.last_click_time = now

            if is_double:
                self.selection = selection
                self.emit_selection(selection)

        def on_tab_changed(self, stack, _property):
            name = stack.get_visible_child_name()
            if name is not None:
                save_last_tab(name)
                button = self.tab_buttons.get(name)
                if button is not None and not button.get_active():
                    button.set_active(True)
                self.update_pick_button()
            self.hovered_target = None
            self.update_highlight()

        def on_tab_toggled(self, button, name):
            if button.get_active():
                self.stack.set_visible_child_name(name)

        def update_pick_button(self):
            if self.pick_button is None:
                return
            tooltips = {
                "windows": "Click a visible window to share it",
                "screens": "Click an output to share it",
                "regions": "Draw an area on any screen to share",
            }
            tab = self.stack.get_visible_child_name() if self.stack else "windows"
            self.pick_button.set_tooltip_text(tooltips.get(tab, "Pick directly"))

        def pick_active_source(self, *_args):
            pickers = {
                "windows": self.select_window,
                "screens": self.select_screen,
                "regions": self.select_region,
            }
            pickers[self.stack.get_visible_child_name()]()

        def update_window_state(self, state, client_list):
            client = next((item for item in client_list if item.get("address") == state["address"]), None)
            if client is None:
                client = client_for_entry(state["entry"], client_list)
            if client is not None:
                state["address"] = client.get("address")
            state["client"] = client

        def refresh_window_metadata(self):
            if self.window_refreshing.is_set():
                return True
            self.window_refreshing.set()

            def query():
                client_list = read_json(["hyprctl", "clients", "-j"])
                active_workspace = read_json(["hyprctl", "activeworkspace", "-j"])
                GLib.idle_add(self.apply_window_metadata, client_list, active_workspace)
                self.window_refreshing.clear()

            threading.Thread(target=query, daemon=True).start()
            return True

        def apply_window_metadata(self, client_list, active_workspace):
            current_workspace_id = active_workspace.get("id") if isinstance(active_workspace, dict) else None
            for state in self.window_card_states:
                self.update_window_state(state, client_list)
                client = state["client"]
                entry = state["entry"]
                if client is None:
                    state["title_label"].set_label(entry["title"] or entry["class"] or "Unavailable window")
                    state["detail_label"].set_label(f"{entry['class'] or 'Window'} · unavailable")
                    state["workspace_id"] = None
                    continue
                workspace_id, workspace_name = workspace_details(client)
                state["title_label"].set_label(client.get("title") or entry["title"] or entry["class"] or "Untitled window")
                state["detail_label"].set_label(f"{client.get('class') or entry['class'] or 'Window'} · Workspace {workspace_name}")
                state["workspace_id"] = workspace_id

            ordered_states = sorted(
                self.window_card_states,
                key=lambda state: (
                    state.get("workspace_id") != current_workspace_id,
                    str(state.get("workspace_id") or ""),
                    state["entry"]["title"].casefold(),
                ),
            )
            if ordered_states != self.window_card_states:
                for state in self.window_card_states:
                    self.window_flow.remove(state["card"])
                for state in ordered_states:
                    self.window_flow.append(state["card"])
                self.window_card_states = ordered_states
            return False

        def on_key_pressed(self, _controller, keyval, _keycode, _state):
            if keyval == Gdk.KEY_Escape:
                self.quit()
                return True
            if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and self.selection is not None:
                self.share()
                return True
            return False

        def share(self, *_args):
            if self.selection is not None:
                self.emit_selection(self.selection)

        def select_screen(self, *_args):
            self.clear_all_highlights()
            self.window.set_visible(False)

            def choose():
                try:
                    completed = subprocess.run(
                        ["slurp", "-o", "-f", "%o"],
                        check=False,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                        text=True,
                    )
                    if completed.returncode == 0 and completed.stdout.strip():
                        selection = f"screen:{completed.stdout.strip()}"
                    else:
                        selection = None
                except OSError:
                    selection = None
                GLib.idle_add(self.finish_pick, selection)

            threading.Thread(target=choose, daemon=True).start()

        def select_region(self, *_args):
            self.clear_all_highlights()
            self.window.set_visible(False)

            def choose():
                try:
                    completed = subprocess.run(
                        ["slurp", "-f", "%o %x %y %w %h"],
                        check=False,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                        text=True,
                    )
                    selection = parse_region(completed.stdout, self.monitor_list) if completed.returncode == 0 else None
                except OSError:
                    selection = None
                GLib.idle_add(self.finish_pick, selection)

            threading.Thread(target=choose, daemon=True).start()

        def select_window(self, *_args):
            self.clear_all_highlights()
            self.window.set_visible(False)

            def choose():
                try:
                    completed = subprocess.run(
                        ["slurp", "-p", "-f", "%x %y"],
                        check=False,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL,
                        text=True,
                    )
                    selection = self.window_at_point(completed.stdout) if completed.returncode == 0 else None
                except OSError:
                    selection = None
                GLib.idle_add(self.finish_pick, selection)

            threading.Thread(target=choose, daemon=True).start()

        def window_at_point(self, value):
            try:
                x, y = (int(number) for number in value.strip().split())
            except ValueError:
                return None
            candidates = []
            for client in read_json(["hyprctl", "clients", "-j"]):
                at = client.get("at", [])
                size = client.get("size", [])
                if len(at) == 2 and len(size) == 2 and at[0] <= x < at[0] + size[0] and at[1] <= y < at[1] + size[1]:
                    candidates.append(client)
            if not candidates:
                return None
            chosen = min(candidates, key=lambda client: client.get("focusHistoryID", sys.maxsize))
            for state in self.window_card_states:
                if state.get("address") == chosen.get("address"):
                    return f"window:{state['entry']['id']}"
            return None

        def finish_pick(self, selection):
            if selection is None:
                self.window.set_visible(True)
                self.window.present()
                self.update_highlight()
            else:
                self.emit_selection(selection)
            return False

        def emit_selection(self, selection):
            if self.has_submitted:
                return
            self.has_submitted = True
            self.clear_all_highlights()
            sys.stdout.write(portal_selection(selection, self.allow_token))
            sys.stdout.flush()
            if self.window is not None:
                self.window.close()
            self.quit()

        def on_close_request(self, *_args):
            self.clear_all_highlights()
            self.quit()
            return False

        def install_css(self):
            css_data = b"""
                .share-picker { background: @window_bg_color; }
                .source-card {
                  background: alpha(@window_fg_color, 0.045);
                  border: 2px solid transparent;
                  border-radius: 14px;
                  padding: 0;
                }
                .source-card:hover { background: alpha(@accent_bg_color, 0.12); }
                .source-card:checked {
                  background: alpha(@accent_bg_color, 0.16);
                  border-color: @accent_bg_color;
                  box-shadow: 0 4px 16px alpha(@accent_bg_color, 0.18);
                }
                .source-card > box { min-width: 220px; }
                .action-card {
                  background: alpha(@accent_bg_color, 0.08);
                  border-style: dashed;
                }
                .preview {
                  background: alpha(@window_fg_color, 0.09);
                  border-radius: 12px 12px 0 0;
                }
            """
            provider = Gtk.CssProvider()
            provider.load_from_data(css_data)
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )

    SharePicker().run(sys.argv)


if __name__ == "__main__":
    main()
