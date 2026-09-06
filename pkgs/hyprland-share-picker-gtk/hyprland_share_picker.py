#!/usr/bin/env python3
"""A GTK4 screencast source picker for xdg-desktop-portal-hyprland."""

import json
import os
import re
import subprocess
import sys
import threading
from pathlib import Path


WINDOW_ENTRY = re.compile(
    r"(?P<id>\d+)\[HC>]"
    r"(?P<class>.*?)\[HT>]"
    r"(?P<title>.*?)\[HE>]"
    r"(?:(?P<address>0x[0-9a-fA-F]+)\[HA>])?"
)
PREVIEW_REFRESH_MS = 250


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
    return ["grim", "-T", str(stable_id), "-s", "0.18", "-t", "jpeg", "-q", "65", "-"]


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
    assert portal_selection("window:42", True) == "[SELECTION]r/window:42\n"
    assert parse_region("DP-1 2048 120 640 480", [{"name": "DP-1", "x": 1920, "y": 0}]) == "region:DP-1@128,120,640,480"


def load_gtk():
    import gi

    gi.require_version("Gdk", "4.0")
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gdk, Gio, GLib, Gtk

    return Gdk, Gio, GLib, Gtk


def main():
    if "--self-test" in sys.argv:
        self_test()
        return

    Gdk, Gio, GLib, Gtk = load_gtk()
    if "--runtime-check" in sys.argv:
        assert Gtk.ContentFit.COVER is not None
        assert Gdk.Texture.new_from_bytes is not None
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
            self.first_card = None
            self.share_button = None
            self.window = None
            self.stack = None
            self.tab_buttons = {}
            self.window_flow = None
            self.window_card_states = []
            self.window_refreshing = threading.Event()

        def do_activate(self):
            if self.window is not None:
                self.window.present()
                return

            self.window = Gtk.ApplicationWindow(application=self, title="Share your screen")
            self.window.set_default_size(980, 700)
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
            stack.add_titled(self.make_source_page([self.region_card()]), "regions", "Region")
            self.stack = stack
            stack.set_visible_child_name(last_tab())
            stack.connect("notify::visible-child-name", self.on_tab_changed)

            switcher = self.make_tab_switcher()
            switcher.set_halign(Gtk.Align.CENTER)
            switcher.set_margin_bottom(12)
            content.append(switcher)
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

        def make_source_page(self, cards):
            flow = Gtk.FlowBox()
            flow.set_selection_mode(Gtk.SelectionMode.NONE)
            flow.set_max_children_per_line(2)
            flow.set_min_children_per_line(1)
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

        def make_window_page(self):
            allowed = parse_window_list(os.environ.get("XDPH_WINDOW_SHARING_LIST"))
            self.window_flow = Gtk.FlowBox()
            self.window_flow.set_selection_mode(Gtk.SelectionMode.NONE)
            self.window_flow.set_max_children_per_line(2)
            self.window_flow.set_min_children_per_line(1)
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
                self.window_flow.append(self.window_pick_card())
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
                        ["grim", "-o", name, "-s", "0.18", "-t", "jpeg", "-q", "65", "-"],
                        tab="screens",
                    )
                )
            return cards

        def region_card(self):
            return self.action_card(
                "selection-rectangular-symbolic",
                "Select a region",
                "Draw an area on any screen",
                "Draw a specific area to share",
                self.select_region,
            )

        def window_pick_card(self):
            return self.action_card(
                "crosshair-symbolic",
                "Pick a window",
                "Click a visible window to share it",
                "Choose a visible window directly",
                self.select_window,
            )

        def action_card(self, icon_name, title_text, subtitle_text, tooltip, handler):
            card = Gtk.Button()
            card.add_css_class("source-card")
            card.add_css_class("action-card")
            card.set_size_request(360, 250)
            card.set_tooltip_text(tooltip)
            card.connect("clicked", handler)

            body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
            body.set_halign(Gtk.Align.CENTER)
            body.set_valign(Gtk.Align.CENTER)
            icon = Gtk.Image.new_from_icon_name(icon_name)
            icon.set_pixel_size(48)
            body.append(icon)
            title = Gtk.Label(label=title_text)
            title.add_css_class("heading")
            body.append(title)
            subtitle = Gtk.Label(label=subtitle_text, wrap=True)
            subtitle.add_css_class("dim-label")
            body.append(subtitle)
            card.set_child(body)
            return card

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
            card.set_size_request(360, -1)
            if self.first_card is None:
                self.first_card = card
            else:
                card.set_group(self.first_card)
            card.connect("toggled", self.on_card_toggled, selection)

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

        def on_card_toggled(self, card, selection):
            if card.get_active():
                self.selection = selection
                self.share_button.set_sensitive(True)

        def on_tab_changed(self, stack, _property):
            name = stack.get_visible_child_name()
            if name is not None:
                save_last_tab(name)
                button = self.tab_buttons.get(name)
                if button is not None and not button.get_active():
                    button.set_active(True)

        def on_tab_toggled(self, button, name):
            if button.get_active():
                self.stack.set_visible_child_name(name)

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

        def select_region(self, *_args):
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
                GLib.idle_add(self.finish_region, selection)

            threading.Thread(target=choose, daemon=True).start()

        def select_window(self, *_args):
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
                GLib.idle_add(self.finish_window_pick, selection)

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

        def finish_region(self, selection):
            if selection is None:
                self.quit()
            else:
                self.emit_selection(selection)
            return False

        def finish_window_pick(self, selection):
            if selection is None:
                self.window.set_visible(True)
                self.window.present()
            else:
                self.emit_selection(selection)
            return False

        def emit_selection(self, selection):
            sys.stdout.write(portal_selection(selection, self.allow_token))
            sys.stdout.flush()
            self.quit()

        def on_close_request(self, *_args):
            self.quit()
            return False

        @staticmethod
        def install_css():
            provider = Gtk.CssProvider()
            provider.load_from_data(
                b"""
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
                .source-card > box { min-width: 360px; }
                .action-card {
                  background: alpha(@accent_bg_color, 0.08);
                  border-style: dashed;
                }
                .preview {
                  background: alpha(@window_fg_color, 0.09);
                  border-radius: 12px 12px 0 0;
                }
                """
            )
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )

    SharePicker().run(sys.argv)


if __name__ == "__main__":
    main()
