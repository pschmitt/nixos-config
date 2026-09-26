{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = config.domains.main;
  glanceHost = "home.${domain}";
  # home.<host>.<mesh domain>. Reaching one of these actually routes over the
  # mesh, so Authelia's mesh bypass applies and no login is asked for;
  # ${glanceHost} resolves to the WAN address and hairpins, so it never looks
  # like mesh traffic (and is two-factor on purpose, see below).
  meshHosts = config.domains.meshHosts "home";
  glancePort = 9832;
  autheliaConfig = import ./authelia-nginx-config.nix { inherit config; };

  # custom-api widgets have no native header icon slot (unlike e.g. bookmarks
  # or monitor, which accept a per-item `icon`), so the default header is
  # hidden and an equivalent one -- icon + title, optionally link-wrapped --
  # is rendered as the first thing in the widget's own template instead. Icon
  # SVGs are fetched verbatim from api.iconify.design (fill="currentColor",
  # so they follow the page's own text color/theme) and inlined rather than
  # referenced by <img src>, since <img> can't inherit currentColor.
  iconHomeAssistant = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M21.8 13H20v8h-7v-3.33l2.79-2.79l.71.12a2.1 2.1 0 1 0 0-4.2a2.1 2.1 0 0 0-2.1 2.1l.1.71l-1.5 1.52V9.65c.66-.36 1.1-1.05 1.1-1.85A2.1 2.1 0 0 0 12 5.7a2.1 2.1 0 0 0-2.1 2.1c0 .8.44 1.49 1.1 1.85v5.48l-1.5-1.52l.1-.71a2.1 2.1 0 0 0-2.1-2.1a2.1 2.1 0 0 0-2.1 2.1A2.1 2.1 0 0 0 7.5 15l.71-.12L11 17.67V21H4v-8H2.25c-.42 0-.83 0-.83-.21c.01-.22.43-.64.86-1.07L11 3c.33-.33.67-.67 1-.67s.67.34 1 .67l4 4V6h2v3l2.78 2.78c.4.4.81.81.82 1.02c0 .2-.4.2-.8.2M7.5 12a.9.9 0 0 1 .9.9a.9.9 0 0 1-.9.9a.9.9 0 0 1-.9-.9a.9.9 0 0 1 .9-.9m9 0c.5 0 .9.4.9.9s-.4.9-.9.9a.9.9 0 0 1-.9-.9a.9.9 0 0 1 .9-.9M12 6.9c.5 0 .9.4.9.9s-.4.9-.9.9s-.9-.4-.9-.9s.4-.9.9-.9"/></svg>'';
  iconJellyfin = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M12 .002C8.826.002-1.398 18.537.16 21.666c1.56 3.129 22.14 3.094 23.682 0S15.177 0 12 0zm7.76 18.949c-1.008 2.028-14.493 2.05-15.514 0C3.224 16.9 9.92 4.755 12.003 4.755c2.081 0 8.77 12.166 7.759 14.196zM12 9.198c-1.054 0-4.446 6.15-3.93 7.189c.518 1.04 7.348 1.027 7.86 0c.511-1.027-2.874-7.19-3.93-7.19z"/></svg>'';
  iconOpsgenie = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M12.002 0a5.988 5.988 0 1 1 0 11.975a5.988 5.988 0 0 1 0-11.975m9.723 13.026h-.03l-4.527-2.242a.67.67 0 0 0-.876.268a22.4 22.4 0 0 1-4.306 5.217a22.4 22.4 0 0 1-4.286-5.2a.67.67 0 0 0-.876-.269l-4.535 2.226h-.03a.67.67 0 0 0-.248.902a29 29 0 0 0 4.55 5.933l-.002.001q.037.037.075.072q.502.504 1.027.981q.123.11.247.217c.315.278.632.555.96.82c.144.117.295.227.441.341c.277.216.552.434.837.639q.66.478 1.346.917a.96.96 0 0 0 1.007.017a29 29 0 0 0 1.428-.98l.2-.153q.538-.397 1.06-.82c.234-.19.46-.39.688-.588c.17-.147.34-.291.506-.442c.295-.268.58-.545.864-.825c.061-.06.127-.118.188-.179l-.004-.002a29 29 0 0 0 4.565-5.949a.67.67 0 0 0-.269-.902"/></svg>'';
  iconNixOS = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="m7.352 1.592l-1.364.002L5.32 2.75l1.557 2.713l-3.137-.008l-1.32 2.34h11.69l-1.353-2.332l-3.192-.006l-2.214-3.865zm6.175 0l-2.687.025l5.846 10.127l1.341-2.34l-1.59-2.765l2.24-3.85l-.683-1.182h-1.336l-1.57 2.705l-1.56-2.72zm6.887 4.195l-5.846 10.125l2.696-.008l1.601-2.76l4.453.016l.682-1.183l-.666-1.157l-3.13-.008L21.778 8.1l-1.365-2.313zM9.432 8.086l-2.696.008l-1.601 2.76l-4.453-.016L0 12.02l.666 1.157l3.13.008l-1.575 2.71l1.365 2.315zM7.33 12.25l-.006.01l-.002-.004l-1.342 2.34l1.59 2.765l-2.24 3.85l.684 1.182H7.35l.004-.006h.001l1.567-2.698l1.558 2.72l2.688-.026l-.004-.006h.01zm2.55 3.93l1.354 2.332l3.192.006l2.215 3.865l1.363-.002l.668-1.156l-1.557-2.713l3.137.008l1.32-2.34z"/></svg>'';
  iconClock = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M12,20A8,8 0 0,0 20,12A8,8 0 0,0 12,4A8,8 0 0,0 4,12A8,8 0 0,0 12,20M12,2A10,10 0 0,1 22,12A10,10 0 0,1 12,22C6.47,22 2,17.5 2,12A10,10 0 0,1 12,2M12.5,7V12.25L17,14.92L16.25,16.15L11,13V7H12.5Z"/></svg>'';
  iconWeather = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M12.74,5.47C15.1,6.5 16.35,9.03 15.92,11.46C17.19,12.56 18,14.19 18,16V16.17C18.31,16.06 18.65,16 19,16A3,3 0 0,1 22,19A3,3 0 0,1 19,22H6A4,4 0 0,1 2,18A4,4 0 0,1 6,14H6.27C5,12.45 4.6,10.24 5.5,8.26C6.72,5.5 9.97,4.24 12.74,5.47M11.93,7.3C10.16,6.5 8.09,7.31 7.31,9.07C6.85,10.09 6.93,11.22 7.41,12.13C8.5,10.83 10.16,10 12,10C12.7,10 13.38,10.12 14,10.34C13.94,9.06 13.18,7.86 11.93,7.3M13.55,3.64C13,3.4 12.45,3.23 11.88,3.12L14.37,1.82L15.27,4.71C14.76,4.29 14.19,3.93 13.55,3.64M6.09,4.44C5.6,4.79 5.17,5.19 4.8,5.63L4.91,2.82L7.87,3.5C7.25,3.71 6.65,4.03 6.09,4.44M18,9.71C17.91,9.12 17.78,8.55 17.59,8L19.97,9.5L17.92,11.73C18.03,11.08 18.05,10.4 18,9.71M3.04,11.3C3.11,11.9 3.24,12.47 3.43,13L1.06,11.5L3.1,9.28C3,9.93 2.97,10.61 3.04,11.3M19,18H16V16A4,4 0 0,0 12,12A4,4 0 0,0 8,16H6A2,2 0 0,0 4,18A2,2 0 0,0 6,20H19A1,1 0 0,0 20,19A1,1 0 0,0 19,18Z"/></svg>'';
  iconBookmark = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M17,18L12,15.82L7,18V5H17M17,3H7A2,2 0 0,0 5,5V21L12,18L19,21V5C19,3.89 18.1,3 17,3Z"/></svg>'';
  iconMovie = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="m20.84 2.18l-3.93.78l2.74 3.54l1.97-.4zm-6.87 1.36L12 3.93l2.75 3.53l1.96-.39zm-4.9.96l-1.97.41l2.75 3.53l1.96-.39zm-4.91 1l-.98.19a1.995 1.995 0 0 0-1.57 2.35L2 10l4.9-.97zM20 12v8H4v-8zm2-2H2v10a2 2 0 0 0 2 2h16c1.11 0 2-.89 2-2z"/></svg>'';
  iconCalendar = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M9 10v2H7v-2zm4 0v2h-2v-2zm4 0v2h-2v-2zm2-7a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h1V1h2v2h8V1h2v2zm0 16V8H5v11zM9 14v2H7v-2zm4 0v2h-2v-2zm4 0v2h-2v-2z"/></svg>'';
  iconGitHub = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M12 2A10 10 0 0 0 2 12c0 4.42 2.87 8.17 6.84 9.5c.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34c-.46-1.16-1.11-1.47-1.11-1.47c-.91-.62.07-.6.07-.6c1 .07 1.53 1.03 1.53 1.03c.87 1.52 2.34 1.07 2.91.83c.09-.65.35-1.09.63-1.34c-2.22-.25-4.55-1.11-4.55-4.92c0-1.11.38-2 1.03-2.71c-.1-.25-.45-1.29.1-2.64c0 0 .84-.27 2.75 1.02c.79-.22 1.65-.33 2.5-.33s1.71.11 2.5.33c1.91-1.29 2.75-1.02 2.75-1.02c.55 1.35.2 2.39.1 2.64c.65.71 1.03 1.6 1.03 2.71c0 3.82-2.34 4.66-4.57 4.91c.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0 0 12 2"/></svg>'';

  iconHackerNews = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M12 2a10 10 0 1 0 0 20a10 10 0 0 0 0-20m4.6 5.1l-3.7 6.2V17h-1.8v-3.7L7.4 7.1h2l2.6 4.5l2.6-4.5z"/></svg>'';
  iconReddit = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M12 2a10 10 0 1 0 0 20a10 10 0 0 0 0-20m5.9 10.7c.1.3.1.6.1.9c0 2.7-2.7 4.9-6 4.9s-6-2.2-6-4.9c0-.3 0-.6.1-.9a1.8 1.8 0 1 1 2.4-2.7c1-.6 2.1-.9 3.3-1l.8-3.6a.5.5 0 0 1 .6-.4l2.5.5a1.3 1.3 0 1 1-.2 1l-2-.4l-.6 2.9c1.2.1 2.4.4 3.3 1a1.8 1.8 0 1 1 1.7 2.7m-8.5 2.5c.4 0 .7-.3.7-.7s-.3-.7-.7-.7s-.7.3-.7.7s.3.7.7.7m5.2 0c.4 0 .7-.3.7-.7s-.3-.7-.7-.7s-.7.3-.7.7s.3.7.7.7m-.1 2.1a.5.5 0 0 0-.7-.7c-.5.5-1.2.8-2.1.8s-1.6-.3-2.1-.8a.5.5 0 0 0-.7.7c.7.7 1.7 1.1 2.8 1.1s2.1-.4 2.8-1.1"/></svg>'';

  # dashboard-icons (di:) ships per-background variants for some logos:
  # "-light" is the near-white one meant for dark backgrounds, "-dark" the
  # near-black one meant for light backgrounds. A bookmark can only declare
  # one icon, so the config carries the variant that fits Glance's dark
  # default and this CSS swaps in the other one when the theme picker flips
  # :root[data-scheme] -- Glance sets that attribute client-side from the
  # X-Scheme response header, so the swap follows a theme switch with no
  # reload, and if the stylesheet ever fails to load the icons still look
  # right for the dark default. `content: url(...)` on an <img> replaces the
  # rendered image, which is the only way to substitute a src from CSS.
  diIconUrl = name: "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/${name}.svg";
  # dark-scheme icon -> light-scheme icon
  schemeIconVariants = {
    "vaultwarden-light" = "vaultwarden";
    "netbox" = "netbox-dark";
  };
  glanceAssets = pkgs.writeTextDir "user.css" (
    lib.concatStrings (
      lib.mapAttrsToList (dark: light: ''
        :root[data-scheme="light"] img.bookmarks-icon[src="${diIconUrl dark}"] {
          content: url("${diIconUrl light}");
        }
      '') schemeIconVariants
    )
    + confirmDialogCss
    + builtinWidgetIconsCss
    + newsWidgetIconsCss
  );

  # A deploy stops glance.service while the rest of the activation runs -- on
  # the order of a minute -- and nginx has nothing to proxy to in that window,
  # which surfaced as a bare 502. This placeholder is served for the three
  # upstream-down codes instead and refreshes itself, so a dashboard left open
  # comes back on its own once glance is listening again. No single quotes: it
  # is embedded in an nginx single-quoted string below.
  glanceRestartingPage = ''<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="5"><title>Dashboard restarting</title><body style="margin:0;height:100vh;display:grid;place-items:center;background:#151519;color:#b8b8c0;font:14px system-ui,-apple-system,sans-serif">Dashboard restarting, retrying every 5s...</body>'';

  # Both the public and the mesh hostnames proxy the same way; they differ
  # only in how they get their certificate, and in whether Authelia lets the
  # request through (see the access_control rule below).
  glanceVirtualHost = {
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;
    extraConfig = autheliaConfig.server;
    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:${toString glancePort}";
        proxyWebsockets = true;
        # Only these three codes are intercepted, so glance's own 404s and
        # friends still pass through untouched.
        extraConfig = autheliaConfig.location + ''
          proxy_intercept_errors on;
          error_page 502 503 504 = @restarting;
        '';
      };
      ${opsgenieAckPath}.extraConfig = opsgenieAckConfig;
      ${githubMergePath}.extraConfig = githubMergeConfig;
      "@restarting".extraConfig = ''
        default_type text/html;
        add_header Retry-After 5 always;
        return 503 '${glanceRestartingPage}';
      '';
    };
  };

  mkWidgetHeader =
    {
      title,
      url ? null,
      icon,
      action ? "",
    }:
    let
      inner = ''
        <span class="flex items-center gap-5">
          <span style="display:inline-flex;flex-shrink:0">${icon}</span>
          <span>${title}</span>
        </span>'';
      titleHtml =
        if url != null then
          ''<a href="${url}" target="_blank" rel="noreferrer" class="uppercase">${inner}</a>''
        else
          ''<span class="uppercase">${inner}</span>'';
    in
    ''
      <div class="widget-header" style="padding:0;display:flex;align-items:center;justify-content:space-between;gap:10px">
        <h2>${titleHtml}</h2>
        ${action}
      </div>
    '';

  # Glance injects widget HTML with innerHTML, which never executes <script>
  # tags, and its page.js only fetches page content once -- there is no
  # client-side refresh. A tab left open therefore keeps the render it was
  # served forever, with the day labels below frozen at render time ("Today"
  # still meaning yesterday the next morning). An inline event handler on an
  # injected element does run (verified in a browser), so this reloads the
  # page once the content is older than autoReloadMinutes, skipping hidden
  # tabs and catching up as soon as one becomes visible again. It rides along
  # in the calendar template because that is the widget whose correctness
  # depends on the clock, and a reload refreshes every other widget too.
  autoReloadMinutes = 15;
  autoReloadSnippet = ''
    <img src="data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==" alt="" style="display:none" onload="
      if (!window.__glanceAutoReload) {
        window.__glanceAutoReload = true;
        var loadedAt = Date.now();
        var maxAge = ${toString autoReloadMinutes} * 60 * 1000;
        var reloadIfStale = function () {
          if (!document.hidden && Date.now() - loadedAt >= maxAge) location.reload();
        };
        setInterval(reloadIfStale, 60 * 1000);
        document.addEventListener('visibilitychange', reloadIfStale);
      }">
  '';

  # Home Assistant script.glance_calendar_feed (scripts.yaml in the hass
  # repo) is the source: it calls calendar.get_events on the work Outlook
  # calendar, the private Google calendar and the shared bergmann-schmitt
  # one, from today 00:00 over 14 days, then merges, de-duplicates and sorts
  # them into {events: [{calendar, title, start, end, allDay, url}]}.
  #
  # This replaced a n8n workflow that fetched the three ICS feeds itself and
  # expanded RRULEs by hand. Home Assistant owns those calendars anyway and
  # gets the hard parts right: the hand-rolled expansion dated a recurring
  # meeting a day late (matching monthly rules by day-of-month rather than
  # weekday), listed one birthday twice, and its "private" ICS had silently
  # gone empty. It is also local -- ~0.1s versus 4-10s for three sequential
  # external ICS fetches, which is what kept timing out and erroring the
  # widget after every glance.service restart.
  #
  # Timed events arrive with a real offset (+02:00) and all-day ones as bare
  # dates, which the script normalizes to midnight UTC: Glance's formatTime
  # renders an RFC3339 string in whatever offset it carries, so an all-day
  # event formatted in UTC keeps its own date, and timed events keep Berlin
  # wall-clock time.
  #
  # Events are rendered in three states, all derived at render time from now
  # on the rofl-10 clock (Europe/Berlin), so they lag reality by at most one
  # cache cycle: ongoing ("Now · until 21:44", accent + left rule), still to
  # come today ("Today, 15:04", accent) and already over (dimmed). The state
  # comparisons are string compares of "2006-01-02T15:04:05" stamps, since Go
  # templates can only compare basic types, not time.Time -- that layout sorts
  # lexicographically, and both sides are formatted in their own zone, which
  # the feed already emits with a real offset.
  #
  # All-day events are never "now" or "past" (they would be ongoing for their
  # whole day, which reads as noise), so they keep the plain date line.
  #
  # Today and tomorrow are named rather than dated, and the list collapses
  # right after them, so "Show more" is exactly the line between what is
  # imminent and what is not. The events are already sorted, so the collapse
  # point is the index of the first event past tomorrow (floored at 3, so a
  # quiet couple of days still show something rather than a lone button).
  # Tomorrow is now + 24h, which lands on the wrong date in the hour after
  # midnight on a DST switch; the fallback to 25h covers the long day, and
  # the short one is left as is -- it costs half an hour of plain dates once
  # a year and is not worth more machinery than that.
  #
  # Note Go template comments must hug their delimiters ({{/* .. */}}); a
  # spaced-out {{ /* .. */ }} is a config-breaking parse error.
  #
  # The remaining n8n webhook URLs (the notification-action and nixpkgs
  # read-state ones below) are secrets -- this repo is public, and the random
  # path segment is the only thing gating either webhook -- so both are
  # sops-backed and only ever referenced via Glance's own runtime ${VAR} env
  # expansion (glance.env below), never as literal strings here.

  calendarTemplate = ''
    ${autoReloadSnippet}
    {{ $events := .JSON.Array "service_response.events" }}
    {{ if not $events }}
      <p class="color-subdue">Nothing upcoming</p>
    {{ else }}
      {{ $today := now | formatTime "DateOnly" }}
      {{ $tomorrow := offsetNow "24h" | formatTime "DateOnly" }}
      {{ if eq $tomorrow $today }}{{ $tomorrow = offsetNow "25h" | formatTime "DateOnly" }}{{ end }}
      {{ $nowStamp := now | formatTime "2006-01-02T15:04:05" }}
      {{ $visible := len $events }}
      {{ range $i, $ev := $events }}
        {{ if and (lt $i $visible) (gt (formatTime "DateOnly" ($ev.String "start" | parseTime "RFC3339")) $tomorrow) }}{{ $visible = $i }}{{ end }}
      {{ end }}
      {{ if lt $visible 3 }}{{ $visible = 3 }}{{ end }}
      <ul class="list list-gap-10 collapsible-container" data-collapse-after="{{ $visible }}">
      {{ range $events }}
        {{ $t := .String "start" | parseTime "RFC3339" }}
        {{ $e := .String "end" | parseTime "RFC3339" }}
        {{ $startStamp := formatTime "2006-01-02T15:04:05" $t }}
        {{ $endStamp := formatTime "2006-01-02T15:04:05" $e }}
        {{ $isToday := eq (formatTime "DateOnly" $t) $today }}
        {{ $isTomorrow := eq (formatTime "DateOnly" $t) $tomorrow }}
        {{ $timed := not (.Bool "allDay") }}
        {{ $isPast := and $timed (le $endStamp $nowStamp) }}
        {{ $isNow := and (le $startStamp $nowStamp) (gt $endStamp $nowStamp) }}
        <li{{ if $isNow }} style="border-left:2px solid var(--color-primary);padding-left:8px"{{ else if $isPast }} style="opacity:0.45"{{ end }}>
          <div class="flex items-center gap-5">
            <span style="display:inline-block;width:8px;height:8px;border-radius:50%;flex-shrink:0;background:{{ if eq (.String "calendar") "work" }}#8250df{{ else if eq (.String "calendar") "bergmann-schmitt" }}#1a7f37{{ else }}#0969da{{ end }}"></span>
            <a class="size-h5 color-highlight block text-truncate" href="{{ .String "url" }}" target="_blank" rel="noreferrer">{{ .String "title" }}</a>
          </div>
          <div class="size-h6 {{ if or $isNow (and $isToday (not $isPast)) }}color-primary{{ else if $isTomorrow }}color-base{{ else }}color-subdue{{ end }}">
            {{ if .Bool "allDay" }}
              {{ if $isToday }}Today{{ else if $isTomorrow }}Tomorrow{{ else }}{{ formatTime "Jan 2" $t }}{{ end }}{{ if gt (.Int "allDayDays") 1 }}–{{ $allDayEnd := .String "allDayEnd" | parseTime "RFC3339" }}{{ if eq (formatTime "Jan" $t) (formatTime "Jan" $allDayEnd) }}{{ formatTime "2" $allDayEnd }}{{ else }}{{ formatTime "Jan 2" $allDayEnd }}{{ end }} · <span class="color-primary">{{ .Int "allDayDays" }} days</span>{{ else }} · all day{{ end }}
            {{ else if $isNow }}
              Now · until {{ if eq (formatTime "DateOnly" $e) (formatTime "DateOnly" $t) }}{{ formatTime "15:04" $e }}{{ else }}{{ formatTime "Jan 2, 15:04" $e }}{{ end }}
            {{ else if $isToday }}
              Today, {{ formatTime "15:04" $t }}
            {{ else if $isTomorrow }}
              Tomorrow, {{ formatTime "15:04" $t }}
            {{ else }}
              {{ formatTime "Jan 2, 15:04" $t }}
            {{ end }}
          </div>
        </li>
      {{ end }}
      </ul>
    {{ end }}
  '';

  # Same keyword list as the "GitHub nixpkgs PR Digest" n8n workflow
  # (n8n.brkn.lol, workflow Yv1UPh7jKlfO7u9g). GitHub's search API rejects
  # queries with more than 5 boolean operators, so the 8 keywords are split
  # into two 4-keyword groups and fetched as a subrequest, same reason the
  # n8n workflow chunks them.
  nixpkgsGroupA = [
    "immich"
    "mealie"
    "netbird"
    "netbox"
  ];
  nixpkgsGroupB = [
    "paperless-ngx"
    "tailscale"
    "vaultwarden"
  ];
  # GitHub's web PR search (unlike its /search/issues REST API) doesn't
  # enforce the 5-operator cap, so the widget header can link to all 8
  # keywords combined -- verified by fetching this URL directly and
  # checking for real results rather than a validation error.
  nixpkgsSearchUrl =
    "https://github.com/NixOS/nixpkgs/pulls?q=repo%3ANixOS%2Fnixpkgs%20is%3Apr%20in%3Atitle%20%28"
    + builtins.concatStringsSep "%20OR%20" (nixpkgsGroupA ++ nixpkgsGroupB)
    + "%29";
  mkNixpkgsQuery =
    keywords:
    "repo:NixOS/nixpkgs type:pr in:title (${builtins.concatStringsSep " OR " keywords}) created:>2025-01-01";
  mkNixpkgsPrList = keywords: {
    url = "https://api.github.com/search/issues";
    headers.Accept = "application/vnd.github+json";
    parameters = {
      q = mkNixpkgsQuery keywords;
      sort = "updated";
      order = "desc";
      per_page = "20";
    };
  };

  # GitHub's own octicons for PR state, fetched verbatim from
  # primer/octicons (icons/git-pull-request-16.svg, git-merge-16.svg,
  # git-pull-request-closed-16.svg) and colored with GitHub's brand colors
  # for each state, rather than approximating with emoji.
  octiconPrOpen = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="#1a7f37"><path d="M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z"/></svg>'';
  octiconPrMerged = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="#8250df"><path d="M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8.5-4.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM5 3.25a.75.75 0 1 0 0 .005V3.25Z"/></svg>'';
  octiconPrClosed = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="#cf222e"><path d="M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 5.5a.75.75 0 0 1 .75.75v3.378a2.251 2.251 0 1 1-1.5 0V7.25a.75.75 0 0 1 .75-.75Zm-2.03-5.273a.75.75 0 0 1 1.06 0l.97.97.97-.97a.748.748 0 0 1 1.265.332.75.75 0 0 1-.205.729l-.97.97.97.97a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-.97-.97-.97.97a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l.97-.97-.97-.97a.75.75 0 0 1 0-1.06ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z"/></svg>'';

  # Icons for the GitHub notification action buttons -- fill="currentColor"
  # so they follow the button's own text color instead of a fixed brand
  # color (unlike the PR-state/notification-type octicons above).
  # CI state badges for PR notifications (octicons check-circle-fill,
  # x-circle-fill and dot-fill), colored by the span around them in
  # GitHub's own check colors -- the theme's positive color is the tan
  # accent, which does not read as "passed".
  octiconCheckCircleFill = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M8 16A8 8 0 1 1 8 0a8 8 0 0 1 0 16Zm3.78-9.72a.751.751 0 0 0-.018-1.042.751.751 0 0 0-1.042-.018L6.75 9.19 5.28 7.72a.751.751 0 0 0-1.042.018.751.751 0 0 0-.018 1.042l2 2a.75.75 0 0 0 1.06 0Z"/></svg>'';
  octiconXCircleFill = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M2.343 13.657A8 8 0 1 1 13.658 2.343 8 8 0 0 1 2.343 13.657ZM6.03 4.97a.751.751 0 0 0-1.042.018.751.751 0 0 0-.018 1.042L6.94 8 4.97 9.97a.749.749 0 0 0 .326 1.275.749.749 0 0 0 .734-.215L8 9.06l1.97 1.97a.749.749 0 0 0 1.275-.326.749.749 0 0 0-.215-.734L9.06 8l1.97-1.97a.749.749 0 0 0-.326-1.275.749.749 0 0 0-.734.215L8 6.94Z"/></svg>'';
  octiconDotFill = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M8 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8Z"/></svg>'';
  octiconGitMerge = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8.5-4.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM5 3.25a.75.75 0 1 0 0 .005V3.25Z"/></svg>'';
  octiconCheckSmall = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"/></svg>'';
  octiconBellSlashSmall = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path fill-rule="evenodd" d="M8 16a2 2 0 0 0 1.985-1.75c.017-.137-.097-.25-.235-.25h-3.5c-.138 0-.252.113-.235.25A2 2 0 0 0 8 16ZM3 5c0-.463.07-.91.202-1.334l-1.29-1.29a.75.75 0 1 1 1.06-1.06l12 12a.75.75 0 1 1-1.06 1.06l-1.322-1.322c-.34.016-.68.03-1.02.04L11 13H2.518a1.516 1.516 0 0 1-1.263-2.36l1.703-2.554A.255.255 0 0 0 3 7.947V5Zm10 2.947V5A5 5 0 0 0 4.09 2.181l1.098 1.098A3.5 3.5 0 0 1 11.5 5v2.947c0 .346.102.683.294.97l1.703 2.554a.018.018 0 0 1 .002.008l-.001.007-.004.006-.006.004-.007.001-.031.002H8.06l1.5 1.5h3.922a1.516 1.516 0 0 0 1.263-2.36l-1.703-2.554A.255.255 0 0 1 13 7.947Z"/></svg>'';

  # GitHub Octicons for notification subject types. The notifications API
  # exposes a PR's subject type, but not its current open/closed/merged state,
  # so PR notifications use the open-PR glyph instead of the purple merge
  # glyph used by the state-aware PR list below.
  octiconNotificationIssue = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="#1a7f37"><path d="M8 9.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"/><path d="M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0a6.5 6.5 0 0 0-13 0Z"/></svg>'';
  octiconNotificationPullRequest = octiconPrOpen;
  octiconNotificationRelease = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="#D8DDE3"><path d="M1 7.775V2.75C1 1.784 1.784 1 2.75 1h5.025c.464 0 .91.184 1.238.513l6.25 6.25a1.75 1.75 0 0 1 0 2.474l-5.026 5.026a1.75 1.75 0 0 1-2.474 0l-6.25-6.25A1.752 1.752 0 0 1 1 7.775Zm1.5 0c0 .066.026.13.073.177l6.25 6.25a.25.25 0 0 0 .354 0l5.025-5.025a.25.25 0 0 0 0-.354l-6.25-6.25a.25.25 0 0 0-.177-.073H2.75a.25.25 0 0 0-.25.25ZM6 5a1 1 0 1 1 0 2a1 1 0 0 1 0-2Z"/></svg>'';
  octiconNotificationCommit = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="#6e7781"><path d="M11.93 8.5a4.002 4.002 0 0 1-7.86 0H.75a.75.75 0 0 1 0-1.5h3.32a4.002 4.002 0 0 1 7.86 0h3.32a.75.75 0 0 1 0 1.5Zm-1.43-.75a2.5 2.5 0 1 0-5 0a2.5 2.5 0 0 0 5 0Z"/></svg>'';
  octiconNotificationCheckSuite = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="#1a7f37"><path d="M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm1.5 0a6.5 6.5 0 1 0 13 0a6.5 6.5 0 0 0-13 0Zm10.28-1.72l-4.5 4.5a.75.75 0 0 1-1.06 0l-2-2a.751.751 0 0 1 .018-1.042a.751.751 0 0 1 1.042-.018l1.47 1.47l3.97-3.97a.751.751 0 0 1 1.042.018a.751.751 0 0 1 .018 1.042Z"/></svg>'';
  octiconNotificationDiscussion = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="#8250df"><path d="M1.75 1h8.5c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0 1 10.25 10H7.061l-2.574 2.573A1.458 1.458 0 0 1 2 11.543V10h-.25A1.75 1.75 0 0 1 0 8.25v-5.5C0 1.784.784 1 1.75 1ZM1.5 2.75v5.5c0 .138.112.25.25.25h1a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h3.5a.25.25 0 0 0 .25-.25v-5.5a.25.25 0 0 0-.25-.25h-8.5a.25.25 0 0 0-.25.25Zm13 2a.25.25 0 0 0-.25-.25h-.5a.75.75 0 0 1 0-1.5h.5c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0 1 14.25 12H14v1.543a1.458 1.458 0 0 1-2.487 1.03L9.22 12.28a.749.749 0 0 1 .326-1.275a.749.749 0 0 1 .734.215l2.22 2.22v-2.19a.75.75 0 0 1 .75-.75h1a.25.25 0 0 0 .25-.25Z"/></svg>'';
  octiconNotificationDefault = ''<svg viewBox="0 0 16 16" width="14" height="14" fill="#6e7781"><path d="M8 16a2 2 0 0 0 1.985-1.75c.017-.137-.097-.25-.235-.25h-3.5c-.138 0-.252.113-.235.25A2 2 0 0 0 8 16ZM3 5a5 5 0 0 1 10 0v2.947c0 .05.015.098.042.139l1.703 2.555A1.519 1.519 0 0 1 13.482 13H2.518a1.516 1.516 0 0 1-1.263-2.36l1.703-2.554A.255.255 0 0 0 3 7.947ZM8 1.5A3.5 3.5 0 0 0 4.5 5v2.947c0 .346-.102.683-.294.97l-1.703 2.556a.017.017 0 0 0-.003.01l.001.006l.004.006l.006.004h10.964l.007-.001l.006-.004l.004-.006l.001-.007l-.003-.01l-1.703-2.554a1.745 1.745 0 0 1-.294-.97V5A3.5 3.5 0 0 0 8 1.5Z"/></svg>'';

  # GitHub search's "issues" representation of a PR only has two `state`
  # values (open/closed) -- a merged PR is "closed" with `pull_request.
  # merged_at` set, so that's checked first: merged/closed/open octicon.
  #
  # GitHub's search API has no per-user "read" state for arbitrary search
  # results (unlike notifications), so read PRs are tracked in our own n8n
  # Data Table (workflow "📋 Glance Nixpkgs PR Read State", kPWS4aHy5IOIcMjw)
  # and filtered out here against the $readNumbers subrequest -- a read PR
  # is skipped entirely rather than shown crossed-out, so it stays gone
  # across reloads/devices until it gets new activity re-surfacing it.
  # nixpkgs tags backports at the very start of the title, either from the
  # backport bot ("[Backport release-26.05] foo: 1.2 -> 1.3") or hand-written
  # ("[26.05] foo: ...", "[release-26.05] foo: ..."). Same rule as the
  # "GitHub nixpkgs PR Digest" n8n workflow, which drops them from the mail.
  # GitHub's search API can't express this, so it is filtered here instead.
  # Anchored on purpose, so a version bump like "tailscale: 1.98.10 ->
  # 1.102.1" is not mistaken for a release tag.
  # Passed to findMatch as a Go template raw string (backticks): a regular
  # quoted literal would have to escape every backslash, since Go unquotes it
  # before the regexp ever sees it.
  nixpkgsBackportPattern = "(?i)^\\s*\\[\\s*(backport\\b[^\\]]*|(release-)?[0-9]{2}\\.[0-9]{2})\\s*\\]";

  nixpkgsPrListItem = ''
    {{ $prNumber := .Int "number" }}
    {{ $isRead := false }}
    {{ range $readNumbers }}
      {{ if eq (.Int "pr_number") $prNumber }}{{ $isRead = true }}{{ end }}
    {{ end }}
    {{ $isBackport := ne (findMatch `${nixpkgsBackportPattern}` (.String "title")) "" }}
    {{ if and (not $isRead) (not $isBackport) }}
    <li id="nixpkgs-pr-{{ $prNumber }}">
      <div class="flex items-center gap-5">
        <span class="shrink-0">{{ if ne (.String "pull_request.merged_at") "" }}${octiconPrMerged}{{ else if eq (.String "state") "closed" }}${octiconPrClosed}{{ else }}${octiconPrOpen}{{ end }}</span>
        <a class="size-h5 color-highlight block text-truncate" href="{{ .String "html_url" }}">{{ .String "title" }}</a>
        <span class="shrink-0" style="margin-left:auto">
          <button type="button" style="${ghActionButtonStyle}" onmouseover="this.style.background='${ghActionButtonHoverBg}'" onmouseout="this.style.background='${ghActionButtonBg}'" onclick="var el=document.getElementById('nixpkgs-pr-{{ $prNumber }}');this.disabled=true;el.style.opacity='.4';fetch(&quot;''${NIXPKGS_PR_MARK_READ_URL}&quot;,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({number:{{ $prNumber }}})}).then(function(r){if(r.ok){${mkRemoveListItemJs null}}else{el.style.opacity='1'}}).catch(function(){el.style.opacity='1'})">${octiconCheckSmall}<span>Read</span></button>
        </span>
      </div>
      <ul class="list-horizontal-text">
        <li>#{{ $prNumber }}</li>
        <li>{{ printf "%.10s" (.String "updated_at") }}</li>
      </ul>
    </li>
    {{ end }}
  '';

  nixpkgsPrListTemplate = ''
    {{ $groupA := sortByTime "updated_at" "RFC3339" "desc" (.JSON.Array "items") }}
    {{ $groupB := sortByTime "updated_at" "RFC3339" "desc" ((.Subrequest "group-b").JSON.Array "items") }}
    {{ $readNumbers := (.Subrequest "read-prs").JSON.Array "" }}
    <div>
    {{ if $groupA }}
      <div class="size-h6 color-base margin-bottom-10">${builtins.concatStringsSep " · " nixpkgsGroupA}</div>
      <ul class="list list-gap-10 collapsible-container" data-collapse-after="5">
      {{ range $groupA }}
        ${nixpkgsPrListItem}
      {{ end }}
      </ul>
    {{ end }}
    {{ if $groupB }}
      <div class="size-h6 color-base margin-bottom-10 margin-top-15">${builtins.concatStringsSep " · " nixpkgsGroupB}</div>
      <ul class="list list-gap-10 collapsible-container" data-collapse-after="5">
      {{ range $groupB }}
        ${nixpkgsPrListItem}
      {{ end }}
      </ul>
    {{ end }}
    </div>
  '';

  # Renders to a JSON array of {entity_id, name, detail, link, icon, type,
  # last_changed} for every "problem" binary_sensor (matched by name suffix
  # or its device_class attribute, since not all follow the *_issue naming
  # convention -- e.g. binary_sensor.cthulhulu_problem) that is currently
  # "on", every plant.* in "problem" state, plus a handful of known
  # warning sensors (public/weather alerts).
  # binary_sensor.plant_issues is deliberately excluded: it's an aggregate
  # of the same plant.* entities already listed individually below. The
  # offline-devices aggregate is also omitted: integration-specific sensors
  # (such as the ZHA offline sensor) provide the more actionable detail.
  #
  # The alert_entities are excluded from that same loop: they carry
  # device_class "problem" themselves, so without the exclusion each one is
  # emitted twice -- once by the generic loop as a "device" and once by the
  # explicit pass below as an "alert".
  #
  # `detail` prefers, in order: the monit failed_checks list (for the
  # monit_<host>_status sensors, so it says *which* check is failing, not
  # just that the host is unhealthy), or the msg/secondary_info attribute (a
  # display-oriented summary several of these template sensors already
  # carry). `link` is the monit host's own status page when known. `icon` is
  # the sensor's own `icon` attribute (an "mdi:xxx" string, when set) so the
  # Go template can render the sensor's actual icon instead of a generic
  # emoji; monit sensors don't carry one, so `type` "infra" gets a generic
  # fallback there instead. `type` also drives the final sort, so
  # same-kind warnings (infra/device/plant/alert) cluster together instead
  # of appearing in HA's arbitrary entity iteration order.
  #
  # All plant.* problems are clustered into a single entry (count + a
  # per-problem-type breakdown in `detail`), rather than one entry per
  # problem type or per plant -- watering N thirsty plants is one action,
  # not N separate warnings to read. Matches the grouping on the HA
  # dashboard's own plant card.
  # Verified interactively with `hass-cli template`.
  haWarningsJinja = ''
    {%- set alert_entities = ["binary_sensor.public_alerts", "binary_sensor.dwd_warnings_current_future"] -%}
    {%- set ns = namespace(items=[]) -%}
    {%- for e in states.binary_sensor -%}
      {%- if e.entity_id not in alert_entities and e.entity_id != 'binary_sensor.offline_devices_devices_offline' and e.entity_id != 'binary_sensor.plant_issues' and e.entity_id != 'binary_sensor.window_advisor' and not e.entity_id.startswith('binary_sensor.window_advisor_') and (e.entity_id.endswith('_issue') or e.entity_id.endswith('_problem') or state_attr(e.entity_id, 'device_class') == 'problem') and e.state == 'on' -%}
        {%- set failed = state_attr(e.entity_id, 'failed_checks') -%}
        {%- if failed -%}
          {%- set detail = (state_attr(e.entity_id, "host_summary") or "") ~ ": " ~ (failed | join(", ")) -%}
          {%- set itype = "infra" -%}
          {%- set link = "https://ha.${domain}/lovelace-homelab/monit#" ~ (state_attr(e.entity_id, "server_name") or "") -%}
        {%- else -%}
          {%- set detail = state_attr(e.entity_id, "msg") or state_attr(e.entity_id, "secondary_info") or "" -%}
          {%- set itype = "device" -%}
          {%- set link = "" -%}
        {%- endif -%}
        {%- set icon = state_attr(e.entity_id, "icon") or "" -%}
        {%- set ns.items = ns.items + [{"name": e.name, "entity_id": e.entity_id, "detail": detail, "link": link, "icon": icon, "type": itype, "last_changed": e.last_changed.isoformat()}] -%}
      {%- endif -%}
    {%- endfor -%}
    {%- set ns.plant_groups = {} -%}
    {%- for e in states.plant -%}
      {%- if e.state == "problem" -%}
        {%- set problem = e.attributes.get("problem", "unknown") -%}
        {%- if "unavailable" in problem -%}
          {%- set problem = "unavailable" -%}
        {%- endif -%}
        {%- set entry = {"name": e.name, "last_changed": e.last_changed} -%}
        {%- set ns.plant_groups = dict(ns.plant_groups, **{problem: (ns.plant_groups.get(problem, []) + [entry])}) -%}
      {%- endif -%}
    {%- endfor -%}
    {%- if ns.plant_groups -%}
      {%- set ns.plant_all_entries = [] -%}
      {%- set ns.plant_detail_parts = [] -%}
      {%- for problem, entries in ns.plant_groups.items() -%}
        {%- set names = entries | map(attribute="name") | map("replace", "balcony_", "") | list -%}
        {%- set ns.plant_all_entries = ns.plant_all_entries + entries -%}
        {%- set ns.plant_detail_parts = ns.plant_detail_parts + [problem ~ ": " ~ (names | join(", "))] -%}
      {%- endfor -%}
      {%- set count = ns.plant_all_entries | length -%}
      {%- set oldest = ns.plant_all_entries | map(attribute="last_changed") | min -%}
      {%- set ns.items = ns.items + [{"name": count ~ " plant" ~ ("s" if count != 1 else "") ~ (" need " if count != 1 else " needs ") ~ "attention", "entity_id": "plant.problems", "detail": ns.plant_detail_parts | join("\n"), "link": "https://ha.${domain}/dashboard-debug/plants", "icon": "mdi:sprout", "type": "plant", "last_changed": oldest.isoformat()}] -%}
    {%- endif -%}
    {%- set ns.window_entries = [] -%}
    {%- for e in states.binary_sensor -%}
      {%- if e.entity_id.startswith('binary_sensor.window_advisor_') and e.state == 'on' -%}
        {%- set room = e.name | replace("Window advisor: ", "") -%}
        {%- set ns.window_entries = ns.window_entries + [{"room": room, "last_changed": e.last_changed}] -%}
      {%- endif -%}
    {%- endfor -%}
    {%- if ns.window_entries -%}
      {%- set rooms = ns.window_entries | map(attribute="room") | list -%}
      {%- set oldest = ns.window_entries | map(attribute="last_changed") | min -%}
      {%- set ns.items = ns.items + [{"name": "Window Advisor", "entity_id": "binary_sensor.window_advisor", "detail": rooms | join(", "), "link": "https://ha.${domain}/dashboard-debug/window-advisor", "icon": "mdi:window-open-variant", "type": "device", "last_changed": oldest.isoformat()}] -%}
    {%- endif -%}
    {%- for eid in alert_entities -%}
      {%- if states(eid) == "on" -%}
        {%- set detail = state_attr(eid, "msg") or state_attr(eid, "secondary_info") or "" -%}
        {%- set icon = state_attr(eid, "icon") or "" -%}
        {%- set ns.items = ns.items + [{"name": state_attr(eid, "friendly_name") or eid, "entity_id": eid, "detail": detail, "link": "", "icon": icon, "type": "alert", "last_changed": states[eid].last_changed.isoformat()}] -%}
      {%- endif -%}
    {%- endfor -%}
    {{ (ns.items | sort(attribute="type")) | tojson }}
  '';

  haWarningsTemplate = ''
    {{ $items := .JSON.Array "" }}
    {{ if not $items }}
      <p class="color-positive">No active warnings 🎉</p>
    {{ else }}
      <ul class="list list-gap-10">
      {{ range $items }}
        <li>
          <div class="flex justify-between items-center gap-10">
            <div class="flex items-center gap-5">
              {{ $icon := .String "icon" }}
              {{ if eq (printf "%.4s" $icon) "mdi:" }}
                <img src="https://api.iconify.design/mdi/{{ trimPrefix "mdi:" $icon }}.svg?color=%23ef4444" style="width:16px;height:16px;flex-shrink:0" alt="" />
              {{ else }}
                <img src="https://api.iconify.design/mdi/alert-circle.svg?color=%23ef4444" style="width:16px;height:16px;flex-shrink:0" alt="" />
              {{ end }}
              {{ $link := .String "link" }}
              {{ if ne $link "" }}
                <a class="color-highlight" href="{{ $link }}" target="_blank" rel="noreferrer">{{ .String "name" }}</a>
              {{ else }}
                <span class="color-highlight">{{ .String "name" }}</span>
              {{ end }}
            </div>
            <span class="size-h6 color-subdue shrink-0" {{ toRelativeTime (parseTime "RFC3339" (.String "last_changed")) }}></span>
          </div>
          {{ if ne (.String "detail") "" }}
            <div class="size-h6 color-subdue" style="white-space:pre-line">{{ .String "detail" }}</div>
          {{ end }}
        </li>
      {{ end }}
      </ul>
    {{ end }}
  '';

  # Org subdomain taken from the OpsGenie login URI stored on the
  # "Atlassian (WIIT)" rbw entry.
  opsgenieOrgUrl = "https://germanedgecloudgmbh.app.opsgenie.com";

  mkOpsgenieAlertList = apiKeyEnv: {
    url = "https://api.eu.opsgenie.com/v2/alerts";
    headers.Authorization = "GenieKey \${${apiKeyEnv}}";
    parameters = {
      query = "status: open AND acknowledged: false";
      limit = "10";
      sort = "createdAt";
      order = "desc";
    };
  };

  # Ack buttons POST to /opsgenie/<team>/... on this same vhost; nginx
  # (opsgenieAckConfig below) checks Authelia, adds the team's GenieKey and
  # forwards to the OpsGenie API, so the keys never reach the browser. The
  # X-Glance header is a cheap CSRF guard: a cross-site form cannot set it.
  # The list is cached for 5m, so an acked alert may reappear on a reload
  # within that window.
  mkOpsgenieAlertItem = team: label: ''
    {{ $id := .String "id" }}
    <li id="opsgenie-alert-{{ $id }}">
      <div class="flex items-center gap-5">
        <a class="size-h5 color-highlight block text-truncate" href="${opsgenieOrgUrl}/alert/detail/{{ $id }}/details" target="_blank" rel="noreferrer">{{ .String "message" }}</a>
        <span class="shrink-0" style="margin-left:auto;display:flex;gap:6px">
          <button type="button" style="${ghActionButtonStyle}" onmouseover="this.style.background='${ghActionButtonHoverBg}'" onmouseout="this.style.background='${ghActionButtonBg}'" onclick="this.nextElementSibling.showModal()">${octiconCheckSmall}<span>Ack</span></button>
          ${mkConfirmDialog {
            title = "Acknowledge ${label} alert?";
            text = ''{{ .String "message" }}'';
            confirmLabel = "Acknowledge";
            onConfirm = "var el=document.getElementById('opsgenie-alert-{{ $id }}');var btn=this.previousElementSibling;btn.disabled=true;el.style.opacity='.4';fetch('/opsgenie/${team}/alerts/{{ $id }}/acknowledge',{method:'POST',headers:{'Content-Type':'application/json','X-Glance':'1'},body:JSON.stringify({source:'glance',note:'Acknowledged via Glance dashboard'})}).then(function(r){if(r.ok){${mkRemoveListItemJs "No unacked alerts 🎉"}}else{btn.disabled=false;el.style.opacity='1';alert('Ack failed: HTTP '+r.status)}}).catch(function(e){btn.disabled=false;el.style.opacity='1';alert('Ack failed: '+e)})";
          }}
        </span>
      </div>
      <ul class="list-horizontal-text">
        <li>${label}</li>
        <li{{ if or (eq (.String "priority") "P1") (eq (.String "priority") "P2") }} class="color-negative"{{ end }}>{{ .String "priority" }}</li>
        <li>{{ printf "%.10s" (.String "createdAt") }}</li>
      </ul>
    </li>
  '';

  # Built-in widgets (clock, weather, bookmarks) render their own plain
  # <h2> header with no icon slot, unlike the custom-api ones that use
  # mkWidgetHeader. The same icons are painted in front of the title as a CSS
  # mask, so they take the header's text color like the inline SVGs do, with
  # mkWidgetHeader's spacing (gap-5 = .5rem).
  svgDataUri =
    svg:
    "data:image/svg+xml,"
    + builtins.replaceStrings [ "\"" "#" "<" ">" ] [ "'" "%23" "%3C" "%3E" ] (
      builtins.replaceStrings [ "<svg " ] [ "<svg xmlns=\"http://www.w3.org/2000/svg\" " ] svg
    );
  builtinWidgetIconsCss = lib.concatStrings (
    lib.mapAttrsToList
      (type: icon: ''
        .widget-type-${type} > .widget-header h2 {
          display: flex;
          align-items: center;
          gap: .5rem;
        }
        .widget-type-${type} > .widget-header h2::before {
          content: "";
          flex-shrink: 0;
          width: 16px;
          height: 16px;
          background-color: currentColor;
          mask: url("${svgDataUri icon}") center / contain no-repeat;
        }
      '')
      {
        clock = iconClock;
        weather = iconWeather;
        bookmarks = iconBookmark;
      }
  );
  newsWidgetIconsCss = lib.concatStrings (
    lib.mapAttrsToList
      (class: icon: ''
        .${class} > .widget-header h2 {
          display: flex;
          align-items: center;
          gap: .5rem;
        }
        .${class} > .widget-header h2::before {
          content: "";
          flex-shrink: 0;
          width: 16px;
          height: 16px;
          background-color: currentColor;
          mask: url("${svgDataUri icon}") center / contain no-repeat;
        }
      '')
      {
        news-hacker-news = iconHackerNews;
        news-homelab = iconReddit;
        news-github-trending = iconGitHub;
      }
  );

  # Native <dialog> confirmation for destructive action buttons (OpsGenie
  # Ack, GitHub Unsubscribe): the trigger button opens it with
  # onclick="this.nextElementSibling.showModal()", so it must directly follow
  # that button. Themed with Glance's own palette (confirmDialogCss) so it
  # follows the light/dark scheme. closedby="any" lets Escape or a backdrop
  # click cancel; only the confirm button closes it with returnValue
  # "confirm", which is what runs onConfirm (with `this` being the dialog, so
  # the trigger is this.previousElementSibling). returnValue is reset right
  # away, since a later Escape close would otherwise keep the old value.
  mkConfirmDialog =
    {
      title,
      text,
      confirmLabel,
      onConfirm,
    }:
    ''
      <dialog class="confirm-dialog" closedby="any" onclose="var ok=this.returnValue==='confirm';this.returnValue='cancel';if(!ok)return;${onConfirm}">
        <form method="dialog">
          <p class="size-h3 color-highlight">${title}</p>
          <p class="size-h5">${text}</p>
          <div class="confirm-dialog-actions">
            <button value="cancel" autofocus>Cancel</button>
            <button value="confirm" class="confirm-dialog-confirm">${confirmLabel}</button>
          </div>
        </form>
      </dialog>
    '';

  confirmDialogCss = ''
    .confirm-dialog {
      /* Glance's reset zeroes margins, which is what centers a modal. */
      margin: auto;
      max-width: min(40rem, calc(100vw - 2rem));
      padding: 0;
      border: 1px solid var(--color-popover-border);
      border-radius: var(--border-radius, 5px);
      background: var(--color-popover-background);
      color: var(--color-text-base);
    }
    .confirm-dialog::backdrop {
      background: rgba(0, 0, 0, .5);
    }
    .confirm-dialog form {
      display: flex;
      flex-direction: column;
      gap: 1rem;
      padding: 1.5rem;
    }
    .confirm-dialog p {
      overflow-wrap: anywhere;
    }
    .confirm-dialog-actions {
      display: flex;
      justify-content: flex-end;
      gap: .75rem;
    }
    .confirm-dialog-actions button {
      padding: .4rem 1rem;
      border: 1px solid var(--color-widget-content-border);
      border-radius: 6px;
      background: var(--color-widget-background-highlight);
      color: var(--color-text-highlight);
      font: inherit;
      cursor: pointer;
    }
    .confirm-dialog-actions button:hover {
      border-color: var(--color-text-subdue);
    }
    .confirm-dialog-actions .confirm-dialog-confirm {
      border-color: var(--color-primary);
      color: var(--color-primary);
    }
  '';

  opsgenieTemplate = ''
    {{ $edge := .JSON.Array "data" }}
    {{ $cks := (.Subrequest "cks").JSON.Array "data" }}
    {{ if and (not $edge) (not $cks) }}
      <p class="color-positive">No unacked alerts 🎉</p>
    {{ else }}
      <ul class="list list-gap-10 collapsible-container" data-collapse-after="5">
      {{ range $edge }}
        ${mkOpsgenieAlertItem "edge" "EDGE"}
      {{ end }}
      {{ range $cks }}
        ${mkOpsgenieAlertItem "cks" "CKS"}
      {{ end }}
      </ul>
    {{ end }}
  '';

  # The dashboard's write actions (OpsGenie Ack, GitHub Merge) POST/PUT to
  # paths on this same vhost. nginx checks Authelia and a custom X-Glance
  # header (a cheap CSRF guard: a cross-site form cannot set it), injects
  # the credential and forwards to the API, so no key ever reaches the
  # browser. Cookies (the Authelia session) are stripped before anything
  # leaves. Locations use named captures, since the Authelia subrequest and
  # maps can clobber numbered ones, and the upstream goes through a variable
  # so a DNS hiccup at boot cannot stop nginx from starting.
  mkApiProxyConfig =
    {
      method,
      host,
      path,
      auth,
    }:
    autheliaConfig.location
    + ''
      limit_except ${method} { deny all; }
      if ($http_x_glance != "1") { return 403; }
      resolver 127.0.0.53 valid=30s;
      resolver_timeout 5s;
      set $api_upstream https://${host};
      proxy_pass $api_upstream${path};
      proxy_set_header Host ${host};
      ${auth}
      proxy_set_header Cookie "";
      proxy_set_header X-Glance "";
      proxy_ssl_server_name on;
      proxy_ssl_name ${host};
      proxy_ssl_verify on;
      proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
    '';

  # The team segment picks the GenieKey from a sops-rendered map
  # (glance-opsgenie.conf below).
  opsgenieAckPath = "~ ^/opsgenie/(?<opsgenie_team>edge|cks)/alerts/(?<opsgenie_alert>[A-Za-z0-9-]+)/acknowledge$";
  opsgenieAckConfig = mkApiProxyConfig {
    method = "POST";
    host = "api.eu.opsgenie.com";
    path = "/v2/alerts/$opsgenie_alert/acknowledge?identifierType=id";
    auth = "proxy_set_header Authorization $glance_opsgenie_auth;";
  };

  # Merge button on PR notifications. Uses the same token as the widget
  # (glance-github.conf below), which only ever merges where GitHub itself
  # lets that account; the template additionally only offers the button on
  # open, non-draft, non-conflicting PRs in repos the viewer can write to,
  # and pins the head SHA it rendered so a newer push is not merged unseen.
  githubMergePath = "~ ^/github/repos/(?<gh_owner>[A-Za-z0-9_.-]+)/(?<gh_repo>[A-Za-z0-9_.-]+)/pulls/(?<gh_pr>[0-9]+)/merge$";
  githubMergeConfig = mkApiProxyConfig {
    method = "PUT";
    host = "api.github.com";
    path = "/repos/$gh_owner/$gh_repo/pulls/$gh_pr/merge";
    auth = ''
      include ${config.sops.templates."nginx/glance-github.conf".path};
      proxy_set_header Accept application/vnd.github+json;
    '';
  };

  # Dedicated API key minted via /Auth/Keys (app name "glance-dashboard")
  # using the pschmitt account from rbw, since Jellyfin has no way to issue
  # a key without an authenticated session first. userId/serverId are from
  # that same session's AuthenticateByName response.
  jellyfinHost = "https://tv.${domain}";
  jellyfinAuthHeader = "MediaBrowser Client=\"glance\", Device=\"glance-dashboard\", DeviceId=\"glance-dashboard-rofl-10\", Version=\"1.0.0\", Token=\"\${JELLYFIN_API_KEY}\"";

  # The grouped Items/Latest response (used for the top-level list) collapses
  # a series' several new episodes into one Series-typed entry with just a
  # ChildCount -- no season info. To show which season(s) got new episodes,
  # a second, ungrouped request for raw Episode items (subrequest
  # "episodes") is cross-referenced by SeriesId inside the template to find
  # the min/max season number among that series' new episodes.
  # Styled as a horizontally-scrolling poster-card strip (portrait art,
  # rounded corners, a corner badge for new-episode count) to match
  # Jellyfin's own "Recently Added" rows instead of a generic icon+text list.
  jellyfinLatestTemplate = ''
    {{ $items := .JSON.Array "" }}
    {{ $episodes := (.Subrequest "episodes").JSON.Array "" }}
    {{ if not $items }}
      <p class="color-subdue">Nothing new recently</p>
    {{ else }}
      <div style="display:flex;gap:12px;overflow-x:auto;padding-bottom:4px">
      {{ range $items }}
        {{ $type := .String "Type" }}
        {{ $id := .String "Id" }}
        {{ $title := .String "Name" }}
        {{ $subtitle := "" }}
        {{ $badge := 0 }}
        {{ if eq $type "Movie" }}
          {{ $year := .Int "ProductionYear" }}
          {{ if gt $year 0 }}{{ $subtitle = printf "%d" $year }}{{ end }}
        {{ else if eq $type "Series" }}
          {{ $seriesId := $id }}
          {{ $seasonMin := 9999 }}
          {{ $seasonMax := -1 }}
          {{ range $episodes }}
            {{ if eq (.String "SeriesId") $seriesId }}
              {{ $s := .Int "ParentIndexNumber" }}
              {{ if lt $s $seasonMin }}{{ $seasonMin = $s }}{{ end }}
              {{ if gt $s $seasonMax }}{{ $seasonMax = $s }}{{ end }}
            {{ end }}
          {{ end }}
          {{ if ne $seasonMax -1 }}
            {{ if eq $seasonMin $seasonMax }}
              {{ $subtitle = printf "Season %d" $seasonMin }}
            {{ else }}
              {{ $subtitle = printf "Seasons %d-%d" $seasonMin $seasonMax }}
            {{ end }}
          {{ end }}
          {{ $badge = .Int "ChildCount" }}
        {{ else }}
          {{ $title = .String "SeriesName" }}
          {{ $subtitle = printf "S%d:E%d - %s" (.Int "ParentIndexNumber") (.Int "IndexNumber") (.String "Name") }}
        {{ end }}
        <a href="${jellyfinHost}/web/#/details?id={{ $id }}&serverId=''${JELLYFIN_SERVER_ID}" target="_blank" rel="noreferrer" style="flex:0 0 auto;width:130px;text-decoration:none;color:inherit">
          <div style="position:relative">
            <img src="${jellyfinHost}/Items/{{ $id }}/Images/Primary?fillWidth=260&quality=90" style="width:130px;height:195px;object-fit:cover;border-radius:8px;display:block" alt="" onerror="this.style.visibility='hidden'" />
            {{ if gt $badge 0 }}
              <span style="position:absolute;top:6px;right:6px;background:#00A4DC;color:#fff;border-radius:999px;min-width:20px;height:20px;padding:0 5px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">{{ $badge }}</span>
            {{ end }}
          </div>
          <div class="size-h5 color-highlight text-truncate" style="margin-top:6px">{{ $title }}</div>
          {{ if $subtitle }}<div class="size-h6 color-subdue text-truncate">{{ $subtitle }}</div>{{ end }}
        </a>
      {{ end }}
      </div>
    {{ end }}
  '';

  radarrHost = "https://rad.arr.${domain}";
  sonarrHost = "https://son.arr.${domain}";
  # VPN-confinement exposes the Arr API ports on rofl-11's NetBird address.
  # Use that mesh path for server-side widget requests instead of traversing
  # the public Authelia-protected vhosts. Keep the public hosts above for
  # links opened in the browser.
  radarrApiHost = "http://rofl-11.${config.domains.netbird}:7878";
  sonarrApiHost = "http://rofl-11.${config.domains.netbird}:8989";

  # Both start/end dates are computed at render time (now/offsetNow inside
  # the template itself, not baked into a static `parameters` value
  # at Nix build time), so the 14-day window keeps rolling forward on every
  # cache refresh instead of going stale after deploy. This needs the
  # "additional requests from within a template" pattern (newRequest |
  # withHeader | withParameter | getResponse) since Glance's static `url`/
  # `parameters` widget properties can't reference template functions.
  # Poster art uses gjson's `#(coverType=="poster")` array query since
  # images.0 isn't reliably the poster.
  #
  # Releases are badged (top-left of the poster) so imminent drops stand
  # out:
  # - Today: solid accent pill badge ("Today"), 2px primary border ring around poster,
  #   and "Today" in color-primary with font-weight 600 in the subtitle.
  # - Tomorrow: outlined accent pill badge ("Tomorrow") and "Tomorrow" in color-base.
  # - In 2 days: countdown pill badge ("2d") in Jellyfin cyan.
  # - In 3+ days: countdown pill badge ("3d", "4d", ...) in slate gray.
  #
  # Several episodes of one series airing on the same day (a season drop, a
  # double feature) collapse into a single TV card at the first of them,
  # with an episode count badge in the poster's top-right corner (styled
  # like the "Recently added" Jellyfin count badge) and the
  # episode range ("S1:E3-E5") as subtitle. Go templates have no maps or
  # grouping, so each item rescans the list: it is only rendered if no
  # earlier item shares its series and air date. The list covers 14 days, so
  # the quadratic scan stays small.
  upcomingReleasesTemplate = ''
    {{ $today := now | formatTime "DateOnly" }}
    {{ $tomorrow := offsetNow "24h" | formatTime "DateOnly" }}
    {{ if eq $tomorrow $today }}{{ $tomorrow = offsetNow "25h" | formatTime "DateOnly" }}{{ end }}
    {{ $todayStart := startOfDay now }}
    {{ $start := $today }}
    {{ $end := offsetNow "336h" | formatTime "DateOnly" }}
    {{ $sonarr := newRequest "${sonarrApiHost}/api/v3/calendar"
        | withHeader "X-Api-Key" "''${SONARR_API_KEY}"
        | withParameter "start" $start
        | withParameter "end" $end
        | withParameter "unmonitored" "false"
        | withParameter "includeSeries" "true"
        | getResponse }}
    {{ $radarr := newRequest "${radarrApiHost}/api/v3/calendar"
        | withHeader "X-Api-Key" "''${RADARR_API_KEY}"
        | withParameter "start" $start
        | withParameter "end" $end
        | withParameter "unmonitored" "false"
        | getResponse }}
    <div>
    {{ if eq $sonarr.Response.StatusCode 200 }}
      {{ $tvItems := sortByTime "airDateUtc" "RFC3339" "asc" ($sonarr.JSON.Array "") }}
      {{ if $tvItems }}
        <div class="size-h6 color-base margin-bottom-10">TV</div>
        <div style="display:flex;gap:12px;overflow-x:auto;padding-bottom:4px">
        {{ range $i, $item := $tvItems }}
          {{ $airDateStr := printf "%.10s" (.String "airDateUtc") }}
          {{ if not $airDateStr }}{{ $airDateStr = .String "airDate" }}{{ end }}
          {{ $seriesId := .Int "seriesId" }}
          {{ $season := .Int "seasonNumber" }}
          {{/* Episodes of one series airing the same day collapse into one
               card at the first of them (see upcomingReleasesTemplate). */}}
          {{ $isFirst := true }}
          {{ $count := 0 }}
          {{ $sameSeason := true }}
          {{ $epMin := .Int "episodeNumber" }}
          {{ $epMax := $epMin }}
          {{ range $j, $other := $tvItems }}
            {{ $otherDate := printf "%.10s" (.String "airDateUtc") }}
            {{ if not $otherDate }}{{ $otherDate = .String "airDate" }}{{ end }}
            {{ if and (eq (.Int "seriesId") $seriesId) (eq $otherDate $airDateStr) }}
              {{ if lt $j $i }}{{ $isFirst = false }}{{ end }}
              {{ $count = add $count 1 }}
              {{ if ne (.Int "seasonNumber") $season }}{{ $sameSeason = false }}{{ end }}
              {{ if lt (.Int "episodeNumber") $epMin }}{{ $epMin = .Int "episodeNumber" }}{{ end }}
              {{ if gt (.Int "episodeNumber") $epMax }}{{ $epMax = .Int "episodeNumber" }}{{ end }}
            {{ end }}
          {{ end }}
          {{ if $isFirst }}
          {{ $isToday := eq $airDateStr $today }}
          {{ $isTomorrow := eq $airDateStr $tomorrow }}
          {{ $days := -1 }}
          {{ if and (not $isToday) (not $isTomorrow) $airDateStr }}
            {{ $diffHours := ((parseLocalTime "DateOnly" $airDateStr).Sub $todayStart).Hours }}
            {{ if ge $diffHours 0.0 }}
              {{ $days = toInt (div (add $diffHours 12) 24) }}
            {{ end }}
          {{ end }}
          <a href="${sonarrHost}" target="_blank" rel="noreferrer" style="flex:0 0 auto;width:130px;text-decoration:none;color:inherit">
            <div style="position:relative">
              <img src="{{ .String "series.images.#(coverType==\"poster\").remoteUrl" }}" style="width:130px;height:195px;object-fit:cover;border-radius:8px;display:block{{ if $isToday }};box-shadow:0 0 0 2px var(--color-primary){{ end }}" alt="" onerror="this.style.visibility='hidden'" />
              {{ if $isToday }}
                <span style="position:absolute;top:6px;left:6px;background:var(--color-primary);color:var(--color-widget-background);border-radius:999px;min-width:20px;height:20px;padding:0 6px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">Today</span>
              {{ else if $isTomorrow }}
                <span style="position:absolute;top:6px;left:6px;background:var(--color-widget-background);color:var(--color-primary);border:1px solid var(--color-primary);border-radius:999px;min-width:20px;height:20px;padding:0 6px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">Tomorrow</span>
              {{ else if eq $days 2 }}
                <span style="position:absolute;top:6px;left:6px;background:#00A4DC;color:#fff;border-radius:999px;min-width:20px;height:20px;padding:0 5px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">{{ $days }}d</span>
              {{ else if gt $days 2 }}
                <span style="position:absolute;top:6px;left:6px;background:#4b5563;color:#fff;border-radius:999px;min-width:20px;height:20px;padding:0 5px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">{{ $days }}d</span>
              {{ end }}
              {{ if gt $count 1 }}
                <span style="position:absolute;top:6px;right:6px;background:#00A4DC;color:#fff;border-radius:999px;min-width:20px;height:20px;padding:0 5px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">{{ $count }}</span>
              {{ end }}
            </div>
            <div class="size-h5 color-highlight text-truncate" style="margin-top:6px">{{ .String "series.title" }}</div>
            <div class="size-h6 {{ if $isToday }}color-primary{{ else if $isTomorrow }}color-base{{ else }}color-subdue{{ end }} text-truncate"{{ if $isToday }} style="font-weight:600"{{ end }}>{{ if eq $count 1 }}S{{ $season }}:E{{ .Int "episodeNumber" }}{{ else if $sameSeason }}S{{ $season }}:E{{ $epMin }}-E{{ $epMax }}{{ else }}{{ $count }} episodes{{ end }} · {{ if $isToday }}Today{{ else if $isTomorrow }}Tomorrow{{ else }}{{ $airDateStr }}{{ end }}</div>
          </a>
          {{ end }}
        {{ end }}
        </div>
      {{ end }}
    {{ else }}
      <p class="size-h6 color-negative">Sonarr: {{ $sonarr.Response.Status }}</p>
    {{ end }}
    {{ if eq $radarr.Response.StatusCode 200 }}
      {{ $movieItems := sortByTime "inCinemas" "RFC3339" "asc" ($radarr.JSON.Array "") }}
      {{ if $movieItems }}
        <div class="size-h6 color-base margin-bottom-10 margin-top-15">Movies</div>
        <div style="display:flex;gap:12px;overflow-x:auto;padding-bottom:4px">
        {{ range $movieItems }}
          {{ $movieDate := printf "%.10s" (.String "inCinemas") }}
          {{ if or (not $movieDate) (lt $movieDate $start) }}
            {{ if and (.String "digitalRelease") (ge (printf "%.10s" (.String "digitalRelease")) $start) }}
              {{ $movieDate = printf "%.10s" (.String "digitalRelease") }}
            {{ else if and (.String "physicalRelease") (ge (printf "%.10s" (.String "physicalRelease")) $start) }}
              {{ $movieDate = printf "%.10s" (.String "physicalRelease") }}
            {{ end }}
          {{ end }}
          {{ $isMovieToday := eq $movieDate $today }}
          {{ $isMovieTomorrow := eq $movieDate $tomorrow }}
          {{ $movieDays := -1 }}
          {{ if and (not $isMovieToday) (not $isMovieTomorrow) $movieDate }}
            {{ $diffHours := ((parseLocalTime "DateOnly" $movieDate).Sub $todayStart).Hours }}
            {{ if ge $diffHours 0.0 }}
              {{ $movieDays = toInt (div (add $diffHours 12) 24) }}
            {{ end }}
          {{ end }}
          <a href="${radarrHost}" target="_blank" rel="noreferrer" style="flex:0 0 auto;width:130px;text-decoration:none;color:inherit">
            <div style="position:relative">
              <img src="{{ .String "images.#(coverType==\"poster\").remoteUrl" }}" style="width:130px;height:195px;object-fit:cover;border-radius:8px;display:block{{ if $isMovieToday }};box-shadow:0 0 0 2px var(--color-primary){{ end }}" alt="" onerror="this.style.visibility='hidden'" />
              {{ if $isMovieToday }}
                <span style="position:absolute;top:6px;left:6px;background:var(--color-primary);color:var(--color-widget-background);border-radius:999px;min-width:20px;height:20px;padding:0 6px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">Today</span>
              {{ else if $isMovieTomorrow }}
                <span style="position:absolute;top:6px;left:6px;background:var(--color-widget-background);color:var(--color-primary);border:1px solid var(--color-primary);border-radius:999px;min-width:20px;height:20px;padding:0 6px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">Tomorrow</span>
              {{ else if eq $movieDays 2 }}
                <span style="position:absolute;top:6px;left:6px;background:#00A4DC;color:#fff;border-radius:999px;min-width:20px;height:20px;padding:0 5px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">{{ $movieDays }}d</span>
              {{ else if gt $movieDays 2 }}
                <span style="position:absolute;top:6px;left:6px;background:#4b5563;color:#fff;border-radius:999px;min-width:20px;height:20px;padding:0 5px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;line-height:1;box-shadow:0 1px 3px rgba(0,0,0,.4)">{{ $movieDays }}d</span>
              {{ end }}
            </div>
            <div class="size-h5 color-highlight text-truncate" style="margin-top:6px">{{ .String "title" }}</div>
            <div class="size-h6 {{ if $isMovieToday }}color-primary{{ else if $isMovieTomorrow }}color-base{{ else }}color-subdue{{ end }} text-truncate"{{ if $isMovieToday }} style="font-weight:600"{{ end }}>{{ if $isMovieToday }}Today{{ else if $isMovieTomorrow }}Tomorrow{{ else }}{{ if $movieDate }}{{ $movieDate }}{{ else }}{{ printf "%.10s" (.String "inCinemas") }}{{ end }}{{ end }}</div>
          </a>
        {{ end }}
        </div>
      {{ end }}
    {{ else }}
      <p class="size-h6 color-negative">Radarr: {{ $radarr.Response.Status }}</p>
    {{ end }}
    </div>
  '';

  # Glance's page.js collapses a list only once, at load: it hides every item
  # past data-collapse-after (class collapsible-item) and appends a "Show
  # more" button. The action buttons (OpsGenie Ack, GitHub Done/Unsubscribe,
  # nixpkgs Read) drop their row in place, so this redoes that by hand: the
  # next hidden item moves up into view, the toggle goes once nothing is
  # hidden any more, and an emptied list is replaced by emptyText (the same
  # message the template shows for an empty result) or, with null, removed
  # together with its heading. Expects the row in `el`; runs inside a
  # double-quoted HTML attribute, so it must not contain double quotes.
  mkRemoveListItemJs =
    emptyText:
    builtins.replaceStrings [ "\n" ] [ "" ] (
      ''
        var list=el.parentElement;el.remove();
        if(list){var n=parseInt(list.dataset.collapseAfter);for(var i=0;i<list.children.length&&i<n;i++){list.children[i].classList.remove('collapsible-item')}if(list.children.length<=n){var t=list.nextElementSibling;if(t&&t.classList.contains('expand-toggle-button')){t.remove()}list.classList.remove('container-expanded')}
      ''
      + (
        if emptyText == null then
          ''
            if(!list.children.length){var h=list.previousElementSibling;if(h&&h.tagName==='DIV'){h.remove()}list.remove()}}
          ''
        else
          ''
            if(!list.children.length){var p=document.createElement('p');p.className='color-positive';p.textContent='${emptyText}';list.replaceWith(p)}}
          ''
      )
    );

  nixpkgsMarkAllReadJs = builtins.replaceStrings [ "\n" ] [ "" ] ''
    var btn=this,items=Array.from(document.querySelectorAll('li[id^=&quot;nixpkgs-pr-&quot;]'));btn.disabled=true;
    (async function(){try{for(var i=0;i<items.length;i++){var el=items[i],number=Number(el.id.slice(11));var r=await fetch(&quot;''${NIXPKGS_PR_MARK_READ_URL}&quot;,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({number:number})});if(!r.ok)throw new Error('HTTP '+r.status);${mkRemoveListItemJs null}}btn.remove()}catch(e){btn.disabled=false;alert('Could not mark all Nixpkgs PRs read: '+e)}})()
  '';

  # Styled to resemble GitHub's own notification action buttons (icon +
  # label pill, subtle border/background) rather than Glance's UI.
  ghActionButtonBg = "rgba(255,255,255,.06)";
  ghActionButtonHoverBg = "rgba(255,255,255,.14)";
  ghActionButtonStyle = "display:inline-flex;align-items:center;gap:4px;padding:3px 8px;border-radius:6px;border:1px solid rgba(255,255,255,.2);background:${ghActionButtonBg};color:inherit;font-size:11px;font-weight:500;font-family:inherit;cursor:pointer;white-space:nowrap;line-height:1.4";

  # Reuses the hermes-agent pschmitt GitHub token declared in hermes.nix
  # (already has notifications scope, verified live) rather than minting a
  # new PAT -- referencing the placeholder doesn't require redeclaring the
  # secret, since hermes.nix's declaration is already in this host's config.
  #
  # PR notifications also get a CI badge: the combined check state of the
  # PR's head commit (statusCheckRollup, which covers GitHub Actions and any
  # other checks/statuses). All PRs go into one aliased GraphQL query (p<i>,
  # <i> being the item's index in the list) rather than two REST calls per
  # PR. Owner/name are quoted with printf %q, which is valid GraphQL for the
  # ASCII names GitHub allows, and the whole query is %q-quoted again into
  # the JSON body. GraphQL returns what it can on partial errors, so a PR it
  # cannot resolve, or one without checks, just renders no badge.
  #
  # The same query also tells whether a PR can be merged from here (open,
  # not a draft, not conflicting, and the viewer has write access), which
  # adds a Merge button (see githubMergeConfig) and lists those PRs first,
  # whatever their CI state: they are the ones waiting on a decision.
  ghNotificationsTemplate = ''
    {{ $items := .JSON.Array "" }}
    {{ if not $items }}
      <p class="color-positive">No unread notifications 🎉</p>
    {{ else }}
      {{ $ciQuery := "" }}
      {{ range $i, $n := $items }}
        {{ if eq (.String "subject.type") "PullRequest" }}
          {{ $ciQuery = printf "%s p%d: repository(owner:%q,name:%q){viewerPermission squashMergeAllowed mergeCommitAllowed rebaseMergeAllowed pullRequest(number:%s){state isDraft mergeable headRefOid commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}" $ciQuery $i (.String "repository.owner.login") (.String "repository.name") (findSubmatch `/pulls/([0-9]+)$` (.String "subject.url")) }}
        {{ end }}
      {{ end }}
      {{ $ci := false }}
      {{ if $ciQuery }}
        {{ $ci = newRequest "https://api.github.com/graphql"
            | withHeader "Authorization" "Bearer ''${GITHUB_TOKEN}"
            | withStringBody (printf `{"query":%q}` (printf "{%s }" $ciQuery))
            | getResponse }}
      {{ end }}
      <ul class="list list-gap-10 collapsible-container" data-collapse-after="8">
      {{/* Two passes: PRs offering the Merge button first, then the rest. */}}
      {{ range $pass := 2 }}
      {{ range $i, $n := $items }}
        {{ $ciState := "" }}
        {{ $mergeMethod := "" }}
        {{ $headSha := "" }}
        {{ $prNumber := "" }}
        {{ if $ci }}
          {{ $pr := $ci.JSON.Get (printf "data.p%d" $i) }}
          {{ $ciState = $pr.String "pullRequest.commits.nodes.0.commit.statusCheckRollup.state" }}
          {{ $perm := $pr.String "viewerPermission" }}
          {{ if and (eq ($pr.String "pullRequest.state") "OPEN") (not ($pr.Bool "pullRequest.isDraft")) (ne ($pr.String "pullRequest.mergeable") "CONFLICTING") (or (eq $perm "ADMIN") (eq $perm "MAINTAIN") (eq $perm "WRITE")) }}
            {{ if $pr.Bool "squashMergeAllowed" }}{{ $mergeMethod = "squash" }}{{ else if $pr.Bool "mergeCommitAllowed" }}{{ $mergeMethod = "merge" }}{{ else if $pr.Bool "rebaseMergeAllowed" }}{{ $mergeMethod = "rebase" }}{{ end }}
            {{ $headSha = $pr.String "pullRequest.headRefOid" }}
            {{ $prNumber = findSubmatch `/pulls/([0-9]+)$` (.String "subject.url") }}
          {{ end }}
        {{ end }}
        {{ $type := .String "subject.type" }}
        {{ $repo := .String "repository.full_name" }}
        {{ $apiUrl := .String "subject.url" }}
        {{ $id := .String "id" }}
        {{ $webUrl := concat "https://github.com/" $repo }}
        {{ if eq $type "PullRequest" }}
          {{ $webUrl = replaceAll "/pulls/" "/pull/" (replaceAll "api.github.com/repos" "github.com" $apiUrl) }}
        {{ else if eq $type "Issue" }}
          {{ $webUrl = replaceAll "api.github.com/repos" "github.com" $apiUrl }}
        {{ else if eq $type "Release" }}
          {{ $webUrl = concat $webUrl "/releases" }}
        {{ end }}
        {{ if eq (eq $pass 0) (ne $mergeMethod "") }}
        <li id="gh-notif-{{ $id }}">
          <div class="flex items-center gap-5">
            <span class="shrink-0">{{ if eq $type "PullRequest" }}${octiconNotificationPullRequest}{{ else if eq $type "Issue" }}${octiconNotificationIssue}{{ else if eq $type "Release" }}${octiconNotificationRelease}{{ else if eq $type "Commit" }}${octiconNotificationCommit}{{ else if eq $type "CheckSuite" }}${octiconNotificationCheckSuite}{{ else if eq $type "Discussion" }}${octiconNotificationDiscussion}{{ else }}${octiconNotificationDefault}{{ end }}</span>
            <a class="size-h5 color-highlight block text-truncate" href="{{ $webUrl }}" target="_blank" rel="noreferrer">{{ .String "subject.title" }}</a>
            {{ if eq $ciState "SUCCESS" }}
              <span class="shrink-0" style="display:inline-flex;color:#3fb950" title="Checks passed">${octiconCheckCircleFill}</span>
            {{ else if or (eq $ciState "FAILURE") (eq $ciState "ERROR") }}
              <span class="shrink-0" style="display:inline-flex;color:#f85149" title="Checks failed">${octiconXCircleFill}</span>
            {{ else if or (eq $ciState "PENDING") (eq $ciState "EXPECTED") }}
              <span class="shrink-0" style="display:inline-flex;color:#d29922" title="Checks running">${octiconDotFill}</span>
            {{ end }}
            <span class="shrink-0" style="margin-left:auto;display:flex;gap:6px">
              {{ if $mergeMethod }}
                <button type="button" title="Merge" aria-label="Merge" style="${ghActionButtonStyle}" onmouseover="this.style.background='${ghActionButtonHoverBg}'" onmouseout="this.style.background='${ghActionButtonBg}'" onclick="this.nextElementSibling.showModal()">${octiconGitMerge}</button>
                ${mkConfirmDialog {
                  title = "Merge this pull request?";
                  text = ''{{ $repo }}#{{ $prNumber }}: {{ .String "subject.title" }}<br><br>{{ if eq $mergeMethod "squash" }}Squash and merge{{ else if eq $mergeMethod "rebase" }}Rebase and merge{{ else }}Create a merge commit{{ end }}{{ if eq $ciState "SUCCESS" }}, checks passed.{{ else if or (eq $ciState "FAILURE") (eq $ciState "ERROR") }}, <span style="color:#f85149">checks failed</span>.{{ else if $ciState }}, <span style="color:#d29922">checks still running</span>.{{ else }}.{{ end }}'';
                  confirmLabel = "Merge";
                  onConfirm = "var el=document.getElementById('gh-notif-{{ $id }}');var btn=this.previousElementSibling;btn.disabled=true;el.style.opacity='.4';fetch('/github/repos/{{ $repo }}/pulls/{{ $prNumber }}/merge',{method:'PUT',headers:{'Content-Type':'application/json','X-Glance':'1'},body:JSON.stringify({merge_method:'{{ $mergeMethod }}',sha:'{{ $headSha }}'})}).then(function(r){if(r.ok){fetch(&quot;\${GH_NOTIFICATION_ACTION_URL}&quot;,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'{{ $id }}',action:'done'})});${mkRemoveListItemJs "No unread notifications 🎉"}}else{btn.disabled=false;el.style.opacity='1';r.json().then(function(j){alert('Merge failed: '+(j.message||r.status))},function(){alert('Merge failed: HTTP '+r.status)})}}).catch(function(e){btn.disabled=false;el.style.opacity='1';alert('Merge failed: '+e)})";
                }}
              {{ end }}
              <button type="button" title="Done" aria-label="Done" style="${ghActionButtonStyle}" onmouseover="this.style.background='${ghActionButtonHoverBg}'" onmouseout="this.style.background='${ghActionButtonBg}'" onclick="var el=document.getElementById('gh-notif-{{ $id }}');this.disabled=true;el.style.opacity='.4';fetch(&quot;''${GH_NOTIFICATION_ACTION_URL}&quot;,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'{{ $id }}',action:'done'})}).then(function(r){if(r.ok){${mkRemoveListItemJs "No unread notifications 🎉"}}else{el.style.opacity='1'}}).catch(function(){el.style.opacity='1'})">${octiconCheckSmall}</button>
              <button type="button" title="Unsubscribe" aria-label="Unsubscribe" style="${ghActionButtonStyle}" onmouseover="this.style.background='${ghActionButtonHoverBg}'" onmouseout="this.style.background='${ghActionButtonBg}'" onclick="this.nextElementSibling.showModal()">${octiconBellSlashSmall}</button>
              ${mkConfirmDialog {
                title = "Unsubscribe from this thread?";
                text = ''{{ $repo }}: {{ .String "subject.title" }}'';
                confirmLabel = "Unsubscribe";
                onConfirm = "var el=document.getElementById('gh-notif-{{ $id }}');this.previousElementSibling.disabled=true;el.style.opacity='.4';fetch(&quot;\${GH_NOTIFICATION_ACTION_URL}&quot;,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'{{ $id }}',action:'unsubscribe'})}).then(function(r){if(r.ok){${mkRemoveListItemJs "No unread notifications 🎉"}}else{el.style.opacity='1'}}).catch(function(){el.style.opacity='1'})";
              }}
            </span>
          </div>
          <div class="size-h6 color-subdue">{{ $repo }} · {{ .String "reason" }}</div>
        </li>
        {{ end }}
      {{ end }}
      {{ end }}
      </ul>
    {{ end }}
  '';
in
{
  sops = {
    secrets = {
      "opsgenie/edge-stack/api-key" = config.sops.mkHostSecret { mode = "0400"; };
      "opsgenie/gksv3-on-call/api-key" = config.sops.mkHostSecret { mode = "0400"; };
      "jellyfin/api-key" = config.sops.mkHostSecret { mode = "0400"; };
      "jellyfin/server-id" = config.sops.mkHostSecret { mode = "0400"; };
      "jellyfin/user-id" = config.sops.mkHostSecret { mode = "0400"; };
      "radarr/api-key" = config.sops.mkHostSecret { mode = "0400"; };
      "sonarr/api-key" = config.sops.mkHostSecret { mode = "0400"; };
      # Named "glance/webhook/..." rather than "n8n/webhook/..." because
      # secrets.sops.yaml already has a real nested "n8n:" mapping (from
      # n8n/runners/authToken); sops-install-secrets resolves that as a
      # nested path once the first segment already exists as a mapping,
      # which broke lookup for a flat "n8n/webhook/..." key.
      "glance/webhook/gh-notification-action-url" = config.sops.mkHostSecret { mode = "0400"; };
      "glance/webhook/nixpkgs-pr-mark-read-url" = config.sops.mkHostSecret { mode = "0400"; };
      "glance/webhook/nixpkgs-pr-read-list-url" = config.sops.mkHostSecret { mode = "0400"; };
    };
    templates = {
      # Consumed by opsgenieAckConfig, which picks the key by the team
      # segment of the ack path.
      "nginx/glance-opsgenie.conf" = {
        owner = config.services.nginx.user;
        content = ''
          map $opsgenie_team $glance_opsgenie_auth {
            edge "GenieKey ${config.sops.placeholder."opsgenie/edge-stack/api-key"}";
            cks "GenieKey ${config.sops.placeholder."opsgenie/gksv3-on-call/api-key"}";
            default "";
          }
        '';
        restartUnits = [ "nginx.service" ];
      };
      "nginx/glance-github.conf" = {
        owner = config.services.nginx.user;
        content = ''
          proxy_set_header Authorization "Bearer ${config.sops.placeholder."hermes/github/pschmitt/token"}";
        '';
        restartUnits = [ "nginx.service" ];
      };
      "glance.env" = {
        content = ''
          HASS_TOKEN=${config.sops.placeholder."home-assistant/token"}
          OPSGENIE_EDGE_STACK_API_KEY=${config.sops.placeholder."opsgenie/edge-stack/api-key"}
          OPSGENIE_GKSV3_ONCALL_API_KEY=${config.sops.placeholder."opsgenie/gksv3-on-call/api-key"}
          JELLYFIN_API_KEY=${config.sops.placeholder."jellyfin/api-key"}
          JELLYFIN_SERVER_ID=${config.sops.placeholder."jellyfin/server-id"}
          JELLYFIN_USER_ID=${config.sops.placeholder."jellyfin/user-id"}
          RADARR_API_KEY=${config.sops.placeholder."radarr/api-key"}
          SONARR_API_KEY=${config.sops.placeholder."sonarr/api-key"}
          GITHUB_TOKEN=${config.sops.placeholder."hermes/github/pschmitt/token"}
          GH_NOTIFICATION_ACTION_URL=${config.sops.placeholder."glance/webhook/gh-notification-action-url"}
          NIXPKGS_PR_MARK_READ_URL=${config.sops.placeholder."glance/webhook/nixpkgs-pr-mark-read-url"}
          NIXPKGS_PR_READ_LIST_URL=${config.sops.placeholder."glance/webhook/nixpkgs-pr-read-list-url"}
        '';
        mode = "0400";
        restartUnits = [ "glance.service" ];
      };
    };
  };

  services = {
    glance = {
      enable = true;
      environmentFile = config.sops.templates."glance.env".path;
      settings = {
        server = {
          host = "127.0.0.1";
          port = glancePort;
          assets-path = "${glanceAssets}";
        };
        theme.custom-css-file = "/assets/user.css";
        pages = [
          {
            name = "Home";
            columns = [
              {
                size = "small";
                widgets = [
                  { type = "clock"; }
                  {
                    type = "weather";
                    # Same coordinates as the laptop weather widgets.
                    location = "Berlin, Germany";
                    units = "metric";
                  }
                  {
                    type = "custom-api";
                    title = "Calendar";
                    hide-header = true;
                    # Kept short because the day labels ("Today", "Now",
                    # dimmed past events) are baked in when the template is
                    # rendered, which only happens on a refetch -- a longer
                    # cache means a freshly loaded page can show labels that
                    # old, and across midnight they name the wrong day.
                    cache = "10m";
                    timeout = "10s";
                    method = "POST";
                    # return_response=true makes Home Assistant hand back the
                    # script's own response instead of just the changed states.
                    url = "https://ha.${domain}/api/services/script/glance_calendar_feed?return_response=true";
                    headers.Authorization = "Bearer \${HASS_TOKEN}";
                    body-type = "json";
                    body = { };
                    template =
                      mkWidgetHeader {
                        title = "Calendar";
                        url = "https://calendar.google.com/calendar";
                        icon = iconCalendar;
                      }
                      + calendarTemplate;
                  }
                  {
                    type = "bookmarks";
                    groups = [
                      {
                        # Case-insensitive, so "n8n" sorts between "Home
                        # Assistant" and "NetBox".
                        links = lib.sort (a: b: lib.toLower a.title < lib.toLower b.title) [
                          {
                            title = "n8n";
                            url = "https://n8n.${domain}";
                            icon = "di:n8n";
                          }
                          {
                            title = "Home Assistant";
                            url = "https://ha.${domain}";
                            icon = "di:home-assistant";
                          }
                          {
                            title = "NetBox";
                            url = "https://netbox.${domain}";
                            # Bright teal, made for dark backgrounds;
                            # schemeIconVariants swaps in "di:netbox-dark"
                            # under the light scheme.
                            icon = "di:netbox";
                          }
                          {
                            title = "Vaultwarden";
                            url = "https://vault.${domain}";
                            # Near-white fill for the dark default theme;
                            # schemeIconVariants swaps in plain
                            # "di:vaultwarden" (near-black) under the light
                            # scheme.
                            icon = "di:vaultwarden-light";
                          }
                        ];
                      }
                    ];
                  }
                ];
              }
              {
                size = "full";
                widgets = [
                  {
                    type = "custom-api";
                    title = "Home Assistant Issues";
                    title-url = "https://ha.${domain}";
                    hide-header = true;
                    cache = "5m";
                    method = "POST";
                    url = "https://ha.${domain}/api/template";
                    headers.Authorization = "Bearer \${HASS_TOKEN}";
                    body-type = "json";
                    body.template = haWarningsJinja;
                    template =
                      mkWidgetHeader {
                        title = "Home Assistant Issues";
                        url = "https://ha.${domain}";
                        icon = iconHomeAssistant;
                      }
                      + haWarningsTemplate;
                  }
                  (
                    {
                      type = "custom-api";
                      title = "Unacked OpsGenie Alerts";
                      title-url = "${opsgenieOrgUrl}/alert/list";
                      hide-header = true;
                      cache = "5m";
                      subrequests.cks = mkOpsgenieAlertList "OPSGENIE_GKSV3_ONCALL_API_KEY";
                      template =
                        mkWidgetHeader {
                          title = "Unacked OpsGenie Alerts";
                          url = "${opsgenieOrgUrl}/alert/list";
                          icon = iconOpsgenie;
                        }
                        + opsgenieTemplate;
                    }
                    // mkOpsgenieAlertList "OPSGENIE_EDGE_STACK_API_KEY"
                  )
                  {
                    type = "custom-api";
                    title = "GitHub Notifications";
                    title-url = "https://github.com/notifications";
                    hide-header = true;
                    cache = "5m";
                    url = "https://api.github.com/notifications";
                    headers.Authorization = "Bearer \${GITHUB_TOKEN}";
                    parameters.per_page = "15";
                    template =
                      mkWidgetHeader {
                        title = "GitHub Notifications";
                        url = "https://github.com/notifications";
                        icon = iconGitHub;
                      }
                      + ghNotificationsTemplate;
                  }
                  (
                    {
                      type = "custom-api";
                      title = "Nixpkgs PRs";
                      title-url = nixpkgsSearchUrl;
                      hide-header = true;
                      cache = "2h";
                      subrequests."group-b" = mkNixpkgsPrList nixpkgsGroupB;
                      subrequests."read-prs".url = "\${NIXPKGS_PR_READ_LIST_URL}";
                      template =
                        mkWidgetHeader {
                          title = "Nixpkgs PRs";
                          url = nixpkgsSearchUrl;
                          icon = iconNixOS;
                          action = ''<button type="button" aria-label="Mark all Nixpkgs PRs read" style="${ghActionButtonStyle}" onmouseover="this.style.background='${ghActionButtonHoverBg}'" onmouseout="this.style.background='${ghActionButtonBg}'" onclick="${nixpkgsMarkAllReadJs}">${octiconCheckSmall}<span>Mark all read</span></button>'';
                        }
                        + nixpkgsPrListTemplate;
                    }
                    // mkNixpkgsPrList nixpkgsGroupA
                  )
                  {
                    type = "custom-api";
                    title = "Recently Added to Jellyfin";
                    title-url = jellyfinHost;
                    hide-header = true;
                    cache = "15m";
                    url = "${jellyfinHost}/Items/Latest";
                    headers.Authorization = jellyfinAuthHeader;
                    parameters = {
                      Limit = "20";
                      UserId = "\${JELLYFIN_USER_ID}";
                      IncludeItemTypes = "Movie,Episode";
                      Fields = "DateCreated,SeriesName,ChildCount";
                    };
                    subrequests.episodes = {
                      url = "${jellyfinHost}/Items/Latest";
                      headers.Authorization = jellyfinAuthHeader;
                      parameters = {
                        Limit = "50";
                        UserId = "\${JELLYFIN_USER_ID}";
                        IncludeItemTypes = "Episode";
                        GroupItems = "false";
                      };
                    };
                    template =
                      mkWidgetHeader {
                        title = "Recently Added to Jellyfin";
                        url = jellyfinHost;
                        icon = iconJellyfin;
                      }
                      + jellyfinLatestTemplate;
                  }
                  {
                    type = "custom-api";
                    title = "Upcoming Releases";
                    hide-header = true;
                    cache = "1h";
                    template =
                      mkWidgetHeader {
                        title = "Upcoming Releases";
                        icon = iconMovie;
                      }
                      + upcomingReleasesTemplate;
                  }
                ];
              }
            ];
          }
          {
            name = "News";
            columns = [
              {
                size = "full";
                widgets = [
                  {
                    type = "hacker-news";
                    css-class = "news-hacker-news";
                    title = "Hacker News";
                    title-url = "https://news.ycombinator.com";
                    cache = "5m";
                    limit = 15;
                    collapse-after = 5;
                  }
                  {
                    type = "rss";
                    css-class = "news-homelab";
                    title = "r/homelab";
                    title-url = "https://www.reddit.com/r/homelab/";
                    cache = "15m";
                    limit = 15;
                    collapse-after = 5;
                    feeds = [
                      {
                        url = "https://www.reddit.com/r/homelab/.rss";
                        title = "Homelab";
                      }
                    ];
                  }
                  {
                    type = "rss";
                    css-class = "news-github-trending";
                    title = "GitHub Trending";
                    title-url = "https://github.com/trending";
                    cache = "1h";
                    limit = 16;
                    collapse-after = 6;
                    preserve-order = true;
                    feeds = [
                      {
                        url = "https://mkusaka.github.io/trending/all/daily/index.xml";
                        title = "All languages";
                        limit = 3;
                      }
                      {
                        url = "https://mkusaka.github.io/trending/nix/daily/index.xml";
                        title = "Nix";
                        limit = 3;
                      }
                      {
                        url = "https://raw.githubusercontent.com/cnzhujie/ai-rss-feed/main/rss/github_ranking_ai_rss.xml";
                        title = "AI ranking changes";
                        limit = 10;
                      }
                    ];
                  }
                ];
              }
            ];
          }
        ];
      };
    };

    nginx.appendHttpConfig = ''
      include ${config.sops.templates."nginx/glance-opsgenie.conf".path};
    '';

    nginx.virtualHosts = {
      ${glanceHost} = glanceVirtualHost // {
        enableACME = false;
        useACMEHost = "wildcard.${domain}";
      };
      # The mesh names are not covered by the *.${domain} wildcard cert (it is
      # one label deep), so this vhost gets its own DNS-01 cert with the three
      # names as SANs.
      ${builtins.head meshHosts} = glanceVirtualHost // {
        serverAliases = builtins.tail meshHosts;
        enableACME = true;
      };
    };

    monit.config = ''
      check host "glance" with address "127.0.0.1"
        group container-services
        restart program = "${config.systemd.package}/bin/systemctl restart glance.service"
          with timeout 180 seconds
        if failed
          port ${toString glancePort}
          protocol http
          with timeout 90 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
    '';
  };

  # Require Authelia before proxying, matching the other private dashboards
  # on this host (see services/hermes.nix).
  services.authelia.extraTwoFactorDomains = [ glanceHost ];
}
