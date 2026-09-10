import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

// Dynamically discovered AI plan quotas from Home Assistant. Ported from
// Noctalia's pschmitt/ha-ai-usage (noctalia-plugins.git/plugins/ha-ai-usage):
// same two-stage discovery (check which of 4 known HA integrations are
// loaded, then POST one Jinja2 template that HA itself evaluates against
// its live sensor state) and the same card/metric shaping logic
// (shared.luau), both carried over close to verbatim since neither is
// Noctalia-specific -- the template runs on the HA side, and the shaping is
// plain data transformation.
//
// Deliberately simplified from the Noctalia version: rings are rendered as
// linear progress bars (Noctalia had to fake a ring by generating PNGs --
// its ui.* tree has no arc primitive -- which doesn't apply here, but a
// QtQuick Shape-based arc was judged too fiddly to get right without being
// able to see it render), and the compact-mode/all-metrics/custom-color
// settings are dropped in favor of always showing headline metrics with
// fixed theme colors.
PluginComponent {
    id: root

    readonly property string serverFile: String(pluginData.server_file || "")
    readonly property string tokenFile: String(pluginData.token_file || "")
    readonly property int refreshIntervalSec: Math.max(10, Number(pluginData.refresh_interval || 60))
    readonly property string cardFilter: String(pluginData.card_filter || "")

    property string server: ""
    property string token: ""
    property var cards: []
    property string errorText: ""
    property bool refreshing: false
    property int generation: 0

    readonly property var supportedIntegrations: [
        { domain: "hass_claude_usage", id: "claude", prefix: "sensor.claude_usage_" },
        { domain: "openai_usage_monitor", id: "codex", prefix: "sensor.codex_usage_" },
        { domain: "github_copilot_usage", id: "copilot", prefix: "sensor.github_copilot_" },
        { domain: "gemini_usage", id: "gemini", prefix: "sensor.google_gemini_" }
    ]

    // image (bundled brand marks, same assets pschmitt/ha-ai-usage ships)
    // wins over glyph when set -- see providerIconSource() below.
    readonly property var providers: ({
        claude: { label: "Claude", image: "assets/claude-code.svg", glyph: "smart_toy", order: 1 },
        codex: { label: "Codex", glyph: "terminal", order: 2 },
        copilot: { label: "GitHub Copilot", glyph: "code", order: 3 },
        gemini: { label: "Gemini", image: "assets/google-antigravity.svg", glyph: "auto_awesome", order: 4 }
    })

    function expandPath(p) {
        const home = Quickshell.env("HOME") || "";
        if (p === "~") return home;
        if (p.indexOf("~/") === 0) return home + p.slice(1);
        return p;
    }

    // Two static Process objects (rather than one dynamically created per
    // call): every other Process-based widget in this plugin set sets
    // `.command` imperatively and toggles `.running`, so this follows the
    // same proven pattern instead of `Component.createObject` + a custom
    // signal, which would need `stdout.onStreamFinished` to reach back out
    // to its own enclosing Process -- `parent` does not reliably resolve to
    // that for a non-Item QtObject property like `stdout`.
    property var serverFileCallback: null
    property var tokenFileCallback: null

    Process {
        id: serverFileProc
        stdout: StdioCollector {
            onStreamFinished: {
                const cb = root.serverFileCallback;
                root.serverFileCallback = null;
                if (cb) cb(text.trim() || null);
            }
        }
    }

    Process {
        id: tokenFileProc
        stdout: StdioCollector {
            onStreamFinished: {
                const cb = root.tokenFileCallback;
                root.tokenFileCallback = null;
                if (cb) cb(text.trim() || null);
            }
        }
    }

    function readSecretFile(which, path, callback) {
        if (!path) { callback(null); return; }
        if (which === "server") {
            root.serverFileCallback = callback;
            serverFileProc.command = ["cat", expandPath(path)];
            serverFileProc.running = true;
        } else {
            root.tokenFileCallback = callback;
            tokenFileProc.command = ["cat", expandPath(path)];
            tokenFileProc.running = true;
        }
    }

    function httpRequest(url, method, headers, body, onSuccess, onError) {
        const xhr = new XMLHttpRequest();
        xhr.open(method, url, true);
        for (const key in headers) xhr.setRequestHeader(key, headers[key]);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return;
            if (xhr.status >= 200 && xhr.status < 300) {
                onSuccess(xhr.responseText);
            } else {
                onError("HTTP " + xhr.status);
            }
        };
        xhr.onerror = function() { onError("Connection failed"); };
        xhr.send(body);
    }

    // The exact Jinja2 template pschmitt/ha-ai-usage's service.luau uses --
    // this runs entirely inside Home Assistant, so it is not Noctalia- or
    // Luau-specific and carries over verbatim.
    function discoveryTemplate(monitors) {
        return "{%- set monitors = " + JSON.stringify(monitors) + " -%}\n" +
            "{%- set ns = namespace(items=[]) -%}\n" +
            "{%- for item in states.sensor -%}\n" +
            "  {%- set id = item.entity_id -%}\n" +
            "  {%- for monitor in monitors -%}\n" +
            "    {%- set claude = monitor.id == 'claude' and (id.endswith('_session_usage') or id.endswith('_week_usage')) -%}\n" +
            "    {%- set codex = monitor.id == 'codex' and (id.endswith('_5h_used') or id.endswith('_weekly_used')) -%}\n" +
            "    {%- set copilot = monitor.id == 'copilot' and id.endswith('_used') -%}\n" +
            "    {%- set gemini = monitor.id == 'gemini' and id.endswith('_usage') and not id.endswith('_usage_pace') -%}\n" +
            "    {%- if id.startswith(monitor.prefix) and (claude or codex or copilot or gemini) and item.state | float(-1) >= 0 -%}\n" +
            "      {%- set attrs = item.attributes -%}\n" +
            "      {%- set reset_id = id | replace('_session_usage', '_session_reset_time') | replace('_week_usage', '_weekly_reset_time') -%}\n" +
            "      {%- set reset = states[reset_id] -%}\n" +
            "      {%- set pace_a = id ~ '_pace' -%}\n" +
            "      {%- set pace_b = (id[:-5] ~ '_usage_pace') if id.endswith('_used') else '' -%}\n" +
            "      {%- set pace_val = states(pace_a) -%}\n" +
            "      {%- if pace_val in ['unknown', 'unavailable', none] and pace_b != '' -%}\n" +
            "        {%- set pace_val = states(pace_b) -%}\n" +
            "      {%- endif -%}\n" +
            "      {%- set banked_ns = namespace(expiry='') -%}\n" +
            "      {%- for credit in (attrs.get('reset_credits') or []) -%}\n" +
            "        {%- set expires_at = credit.get('expires_at') if credit is mapping else none -%}\n" +
            "        {%- if (credit.get('status') if credit is mapping else none) == 'available' and expires_at and (banked_ns.expiry == '' or expires_at < banked_ns.expiry) -%}\n" +
            "          {%- set banked_ns.expiry = expires_at -%}\n" +
            "        {%- endif -%}\n" +
            "      {%- endfor -%}\n" +
            "      {%- set ns.items = ns.items + [{\"integration\": monitor.id, \"entity_id\": id, \"state\": item.state, \"name\": item.name, \"icon\": (attrs.get('icon') or ''), \"reset_time\": reset.state if monitor.id == 'claude' and reset is not none else (attrs.get('reset_time') or ''), \"resets_at\": (attrs.get('resets_at') or ''), \"quota_reset_date_utc\": (attrs.get('quota_reset_date_utc') or ''), \"primary_reset_time\": (attrs.get('primary_reset_time') or ''), \"secondary_reset_time\": (attrs.get('secondary_reset_time') or ''), \"pace\": pace_val if pace_val not in ['unknown', 'unavailable', none] else '', \"reset_credits_available\": (attrs.get('reset_credits_available') or ''), \"reset_credits_next_expiry\": banked_ns.expiry}] -%}\n" +
            "    {%- endif -%}\n" +
            "  {%- endfor -%}\n" +
            "{%- endfor -%}\n" +
            "{{- ns.items | tojson -}}";
    }

    function publishError(message) {
        root.errorText = message;
        root.refreshing = false;
    }

    function requestMetrics(gen, monitors, failures) {
        if (monitors.length === 0) {
            root.refreshing = false;
            root.cards = [];
            publishError(failures.length > 0 ? ("Integration discovery failed: " + failures.join(", ")) : "No supported, enabled AI usage integrations were found");
            return;
        }
        httpRequest(root.server + "/api/template", "POST",
            { "Authorization": "Bearer " + root.token, "Content-Type": "application/json" },
            JSON.stringify({ template: discoveryTemplate(monitors) }),
            function(body) {
                if (gen !== root.generation) return;
                root.refreshing = false;
                let items = [];
                try { items = JSON.parse(body) || []; } catch (e) {
                    publishError("Home Assistant returned invalid usage data");
                    return;
                }
                root.cards = buildCards(items);
                root.errorText = failures.length > 0 ? ("Integration lookup issue: " + failures.join(", ")) : "";
            },
            function(err) {
                if (gen !== root.generation) return;
                root.refreshing = false;
                publishError("Home Assistant usage discovery failed (" + err + ")");
            }
        );
    }

    function discoverIntegrations(gen) {
        let pending = root.supportedIntegrations.length;
        const monitors = [];
        const failures = [];
        function finish() {
            pending--;
            if (pending === 0 && gen === root.generation) requestMetrics(gen, monitors, failures);
        }
        for (const integration of root.supportedIntegrations) {
            httpRequest(root.server + "/api/config/config_entries/entry?domain=" + encodeURIComponent(integration.domain), "GET",
                { "Authorization": "Bearer " + root.token }, null,
                function(body) {
                    if (gen !== root.generation) return;
                    try {
                        const entries = JSON.parse(body) || [];
                        for (const entry of entries) {
                            if (entry.state === "loaded") { monitors.push(integration); break; }
                        }
                    } catch (e) {
                        failures.push(integration.id + " invalid JSON");
                    }
                    finish();
                },
                function(err) {
                    if (gen !== root.generation) return;
                    failures.push(integration.id + " " + err);
                    finish();
                }
            );
        }
    }

    function refresh() {
        if (root.refreshing) return;
        readSecretFile("server", root.serverFile, function(server) {
            readSecretFile("token", root.tokenFile, function(token) {
                if (!server || !token) {
                    publishError("Home Assistant server/token file is unavailable or empty");
                    return;
                }
                root.server = server.replace(/\/+$/, "");
                root.token = token;
                root.refreshing = true;
                root.errorText = "";
                root.generation++;
                discoverIntegrations(root.generation);
            });
        });
    }

    // ── shared.luau's card/metric shaping, ported ──────────────────────
    function validNumber(v) {
        const n = Number(v);
        if (isNaN(n)) return null;
        return Math.max(0, Math.min(100, n));
    }
    function validState(v) {
        const INVALID_STATES = { unknown: true, unavailable: true, none: true, "": true };
        return v !== undefined && v !== null && !INVALID_STATES[String(v).trim().toLowerCase()];
    }
    function cardDetails(item) {
        const integration = String(item.integration || "").trim();
        const provider = root.providers[integration] || { label: integration, glyph: "donut_large", order: 99 };
        let label = provider.label;
        if (integration === "claude") {
            const m = /\((.*?)\)/.exec(String(item.name || ""));
            let account = m ? m[1] : "";
            account = account.replace(/^Philipp\s*-\s*/, "").replace(/^Philipp Schmitt\s*/, "");
            if (account !== "") label += " · " + account;
        }
        return { id: integration + ":" + label, label, glyph: provider.glyph, image: provider.image || "", order: provider.order };
    }
    function metricDetails(item) {
        const entity = String(item.entity_id || "").trim();
        const source = String(item.name || "").trim().toLowerCase();
        let window = "other", label = "Usage";
        if (entity.endsWith("_session_usage") || entity.endsWith("_5h_used")) {
            window = "short"; label = entity.endsWith("_5h_used") ? "5h" : "Session";
        } else if (entity.endsWith("_week_usage") || entity.endsWith("_weekly_used") || entity.endsWith("_weekly_usage")) {
            window = "weekly"; label = "Weekly";
        } else if (source.includes("premium")) { label = "Premium"; }
        else if (source.includes("completion")) { label = "Completions"; }
        else if (source.includes("chat")) { label = "Chat"; }
        const secondary = String(item.integration || "") === "gemini" && source.includes("3p models");
        if (secondary) label = "3P " + label;
        return { window, label, secondary };
    }
    function metricOrder(m) {
        const penalty = m.secondary ? 10 : 0;
        if (m.window === "short") return 1 + penalty;
        if (m.window === "weekly") return 2 + penalty;
        if (m.label === "Premium") return 3 + penalty;
        if (m.label === "Chat") return 4 + penalty;
        if (m.label === "Completions") return 5 + penalty;
        return 99 + penalty;
    }
    function metricReset(item) {
        for (const key of ["reset_time", "resets_at", "quota_reset_date_utc"]) {
            const v = String(item[key] || "").trim();
            if (validState(v)) return v;
        }
        const entity = String(item.entity_id || "");
        if (entity.endsWith("_weekly_used")) return String(item.secondary_reset_time || "").trim();
        if (entity.endsWith("_5h_used")) return String(item.primary_reset_time || "").trim();
        return String(item.primary_reset_time || "").trim();
    }
    function buildCards(items) {
        const byId = {};
        for (const item of items) {
            const entity = String(item.entity_id || "").trim();
            const used = validNumber(item.state);
            if (entity === "" || used === null) continue;
            const details = cardDetails(item);
            let card = byId[details.id];
            if (!card) {
                card = { id: details.id, label: details.label, glyph: details.glyph, image: details.image, order: details.order, metrics: [] };
                byId[details.id] = card;
            }
            const bankedAvailable = Number(item.reset_credits_available);
            if (!isNaN(bankedAvailable) && bankedAvailable > 0) {
                card.bankedAvailable = bankedAvailable;
                const expiry = String(item.reset_credits_next_expiry || "").trim();
                if (validState(expiry)) card.bankedExpiry = expiry;
            }
            const md = metricDetails(item);
            let reset = metricReset(item);
            let window = md.window;
            if (window === "other" && validState(reset)) window = "monthly";
            const pace = Number(item.pace);
            card.metrics.push({
                label: md.label, window, secondary: md.secondary, used, reset,
                pace: isNaN(pace) ? null : pace
            });
        }
        const cards = [];
        for (const id in byId) {
            const card = byId[id];
            card.metrics.sort((a, b) => metricOrder(a) === metricOrder(b) ? a.label.localeCompare(b.label) : metricOrder(a) - metricOrder(b));
            card.primary = card.metrics[0] || null;
            cards.push(card);
        }
        cards.sort((a, b) => a.order === b.order ? a.label.localeCompare(b.label) : a.order - b.order);
        return filterCards(cards, root.cardFilter);
    }
    function filterCards(cards, filter) {
        const terms = String(filter || "").split(",").map(t => t.trim().toLowerCase()).filter(t => t !== "");
        if (terms.length === 0) return cards;
        const filtered = [];
        const seen = {};
        for (const term of terms) {
            for (const card of cards) {
                if (seen[card.id]) continue;
                if ((card.label + " " + card.id).toLowerCase().includes(term)) {
                    filtered.push(card);
                    seen[card.id] = true;
                }
            }
        }
        return filtered;
    }
    function isHeadline(m) {
        return !m.secondary && (m.window === "short" || m.window === "weekly");
    }
    // BatteryService.levelCautionColor/levelCriticalColor are reused here
    // rather than guessing at a Theme "warning" role: they're the same
    // amber/red thresholds this repo already ships for battery level.
    function colorForUsed(used) {
        if (used === null || used === undefined) return Theme.surfaceVariantText;
        if (used >= 90) return BatteryService.levelCriticalColor;
        if (used >= 75) return BatteryService.levelCautionColor;
        return Theme.primary;
    }
    function resetText(value) {
        if (!validState(value)) return "—";
        const epoch = Date.parse(value);
        if (isNaN(epoch)) return value;
        const seconds = Math.floor((epoch - Date.now()) / 1000);
        if (seconds <= 0) return "now";
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        if (days > 0) return "in " + days + "d " + hours + "h";
        if (hours > 0) return "in " + hours + "h " + minutes + "m";
        return "in " + Math.max(1, minutes) + "m";
    }
    function paceText(pace) {
        if (pace === null || pace === undefined) return "";
        return (pace >= 0 ? "+" : "") + Math.round(pace) + "%/day";
    }
    function headlineMetrics(card) {
        const headline = (card.metrics || []).filter(isHeadline);
        return headline.length > 0 ? headline : (card.primary ? [card.primary] : []);
    }

    Timer {
        interval: root.refreshIntervalSec * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    function summaryText() {
        if (root.cards.length === 0) return root.errorText !== "" ? "—" : "…";
        let worst = null;
        for (const card of root.cards) {
            const m = card.primary;
            if (m && m.used !== null && (worst === null || m.used > worst)) worst = m.used;
        }
        return worst === null ? "—" : Math.round(worst) + "%";
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: "donut_large"
                color: Theme.surfaceText
                size: Theme.barIconSize(root.barThickness, -6, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.summaryText()
                color: Theme.surfaceText
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "donut_large"
            color: Theme.surfaceText
            size: Theme.barIconSize(root.barThickness, -6, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
        }
    }

    popoutWidth: 520
    popoutHeight: 560

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "AI usage"
            detailsText: root.refreshing ? "Refreshing…" : (root.errorText !== "" ? root.errorText : "Home Assistant")
            showCloseButton: true

            Component.onCompleted: root.refresh()
            Connections {
                target: parentPopout
                function onOpened() { root.refresh(); }
            }

            DankFlickable {
                width: parent.width
                height: root.popoutHeight - 90
                contentWidth: width
                contentHeight: cardColumn.implicitHeight
                clip: true

                Column {
                    id: cardColumn
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        visible: root.cards.length === 0 && root.errorText === ""
                        text: "No active AI usage metrics were discovered."
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Repeater {
                        model: root.cards

                        StyledRect {
                            required property var modelData
                            width: parent.width
                            height: cardInner.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Column {
                                id: cardInner
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingXS

                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingXS
                                    Image {
                                        visible: modelData.image !== ""
                                        source: modelData.image
                                        width: 16
                                        height: 16
                                        sourceSize.width: 16
                                        sourceSize.height: 16
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                    }
                                    DankIcon { visible: modelData.image === ""; name: modelData.glyph; size: 16; color: Theme.surfaceText }
                                    StyledText {
                                        width: parent.width - 16 - Theme.spacingXS
                                        text: modelData.label
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                        color: Theme.surfaceText
                                    }
                                }

                                StyledText {
                                    visible: modelData.bankedAvailable !== undefined
                                    text: (modelData.bankedAvailable === 1 ? "1 banked reset" : (modelData.bankedAvailable + " banked resets"))
                                        + (modelData.bankedExpiry ? " · expires " + root.resetText(modelData.bankedExpiry) : "")
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                Repeater {
                                    model: root.headlineMetrics(modelData)

                                    Column {
                                        required property var modelData
                                        width: cardInner.width
                                        spacing: 2

                                        Row {
                                            width: parent.width
                                            StyledText {
                                                width: parent.width - 50
                                                text: modelData.label + (modelData.pace !== null && modelData.pace !== undefined ? "  " + root.paceText(modelData.pace) : "")
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeSmall
                                            }
                                            StyledText {
                                                width: 50
                                                horizontalAlignment: Text.AlignRight
                                                text: modelData.used !== null ? Math.round(modelData.used) + "%" : "—"
                                                color: root.colorForUsed(modelData.used)
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.Bold
                                            }
                                        }

                                        Rectangle {
                                            visible: modelData.used !== null
                                            width: parent.width
                                            height: 5
                                            radius: 3
                                            color: Theme.withAlpha(Theme.surfaceVariantText, 0.2)
                                            Rectangle {
                                                width: parent.width * Math.min(1, Math.max(0, (modelData.used || 0) / 100))
                                                height: parent.height
                                                radius: parent.radius
                                                color: root.colorForUsed(modelData.used)
                                            }
                                        }

                                        StyledText {
                                            text: "Reset " + root.resetText(modelData.reset)
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
