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
  meshHosts = config.custom.meshHosts "home";
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
  iconMovie = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="m20.84 2.18l-3.93.78l2.74 3.54l1.97-.4zm-6.87 1.36L12 3.93l2.75 3.53l1.96-.39zm-4.9.96l-1.97.41l2.75 3.53l1.96-.39zm-4.91 1l-.98.19a1.995 1.995 0 0 0-1.57 2.35L2 10l4.9-.97zM20 12v8H4v-8zm2-2H2v10a2 2 0 0 0 2 2h16c1.11 0 2-.89 2-2z"/></svg>'';
  iconCalendar = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M9 10v2H7v-2zm4 0v2h-2v-2zm4 0v2h-2v-2zm2-7a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h1V1h2v2h8V1h2v2zm0 16V8H5v11zM9 14v2H7v-2zm4 0v2h-2v-2zm4 0v2h-2v-2z"/></svg>'';
  iconGitHub = ''<svg viewBox="0 0 24 24" width="16" height="16"><path fill="currentColor" d="M12 2A10 10 0 0 0 2 12c0 4.42 2.87 8.17 6.84 9.5c.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34c-.46-1.16-1.11-1.47-1.11-1.47c-.91-.62.07-.6.07-.6c1 .07 1.53 1.03 1.53 1.03c.87 1.52 2.34 1.07 2.91.83c.09-.65.35-1.09.63-1.34c-2.22-.25-4.55-1.11-4.55-4.92c0-1.11.38-2 1.03-2.71c-.1-.25-.45-1.29.1-2.64c0 0 .84-.27 2.75 1.02c.79-.22 1.65-.33 2.5-.33s1.71.11 2.5.33c1.91-1.29 2.75-1.02 2.75-1.02c.55 1.35.2 2.39.1 2.64c.65.71 1.03 1.6 1.03 2.71c0 3.82-2.34 4.66-4.57 4.91c.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0 0 12 2"/></svg>'';

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
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString glancePort}";
      proxyWebsockets = true;
      # Only these three codes are intercepted, so glance's own 404s and
      # friends still pass through untouched.
      extraConfig = autheliaConfig.location + ''
        proxy_intercept_errors on;
        error_page 502 503 504 = @restarting;
      '';
    };
    locations."@restarting".extraConfig = ''
      default_type text/html;
      add_header Retry-After 5 always;
      return 503 '${glanceRestartingPage}';
    '';
  };

  mkWidgetHeader =
    {
      title,
      url ? null,
      icon,
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
      <div class="widget-header" style="padding:0">
        <h2>${titleHtml}</h2>
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
        {{ $isNow := and $timed (le $startStamp $nowStamp) (gt $endStamp $nowStamp) }}
        <li{{ if $isNow }} style="border-left:2px solid var(--color-primary);padding-left:8px"{{ else if $isPast }} style="opacity:0.45"{{ end }}>
          <div class="flex items-center gap-5">
            <span style="display:inline-block;width:8px;height:8px;border-radius:50%;flex-shrink:0;background:{{ if eq (.String "calendar") "work" }}#8250df{{ else if eq (.String "calendar") "bergmann-schmitt" }}#1a7f37{{ else }}#0969da{{ end }}"></span>
            <a class="size-h5 color-highlight block text-truncate" href="{{ .String "url" }}" target="_blank" rel="noreferrer">{{ .String "title" }}</a>
          </div>
          <div class="size-h6 {{ if or $isNow (and $isToday (not $isPast)) }}color-primary{{ else if $isTomorrow }}color-base{{ else }}color-subdue{{ end }}">
            {{ if .Bool "allDay" }}
              {{ if $isToday }}Today{{ else if $isTomorrow }}Tomorrow{{ else }}{{ formatTime "Jan 2" $t }}{{ end }} · all day
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
          <button type="button" style="${ghActionButtonStyle}" onmouseover="this.style.background='${ghActionButtonHoverBg}'" onmouseout="this.style.background='${ghActionButtonBg}'" onclick="var el=document.getElementById('nixpkgs-pr-{{ $prNumber }}');this.disabled=true;el.style.opacity='.4';fetch(&quot;''${NIXPKGS_PR_MARK_READ_URL}&quot;,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({number:{{ $prNumber }}})}).then(function(r){if(r.ok){el.remove()}else{el.style.opacity='1'}}).catch(function(){el.style.opacity='1'})">${octiconCheckSmall}<span>Read</span></button>
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
  # aggregate/warning sensors (offline devices, public/weather alerts).
  # binary_sensor.plant_issues is deliberately excluded: it's an aggregate
  # of the same plant.* entities already listed individually below.
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
    {%- set alert_entities = ["binary_sensor.offline_devices_devices_offline", "binary_sensor.public_alerts", "binary_sensor.dwd_warnings_current_future"] -%}
    {%- set ns = namespace(items=[]) -%}
    {%- for e in states.binary_sensor -%}
      {%- if e.entity_id not in alert_entities and e.entity_id != 'binary_sensor.plant_issues' and e.entity_id != 'binary_sensor.window_advisor' and not e.entity_id.startswith('binary_sensor.window_advisor_') and (e.entity_id.endswith('_issue') or e.entity_id.endswith('_problem') or state_attr(e.entity_id, 'device_class') == 'problem') and e.state == 'on' -%}
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
        {%- set entry = {"name": e.name, "last_changed": e.last_changed} -%}
        {%- set ns.plant_groups = dict(ns.plant_groups, **{problem: (ns.plant_groups.get(problem, []) + [entry])}) -%}
      {%- endif -%}
    {%- endfor -%}
    {%- if ns.plant_groups -%}
      {%- set ns.plant_all_entries = [] -%}
      {%- set ns.plant_detail_parts = [] -%}
      {%- for problem, entries in ns.plant_groups.items() -%}
        {%- set names = entries | map(attribute="name") | list -%}
        {%- set ns.plant_all_entries = ns.plant_all_entries + entries -%}
        {%- set ns.plant_detail_parts = ns.plant_detail_parts + [problem ~ ": " ~ (names | join(", "))] -%}
      {%- endfor -%}
      {%- set count = ns.plant_all_entries | length -%}
      {%- set oldest = ns.plant_all_entries | map(attribute="last_changed") | min -%}
      {%- set ns.items = ns.items + [{"name": count ~ " plant" ~ ("s" if count != 1 else "") ~ (" need " if count != 1 else " needs ") ~ "attention", "entity_id": "plant.problems", "detail": ns.plant_detail_parts | join("; "), "link": "https://ha.${domain}/dashboard-debug/plants", "icon": "mdi:sprout", "type": "plant", "last_changed": oldest.isoformat()}] -%}
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
            <div class="size-h6 color-subdue">{{ .String "detail" }}</div>
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

  opsgenieTemplate = ''
    {{ $edge := .JSON.Array "data" }}
    {{ $cks := (.Subrequest "cks").JSON.Array "data" }}
    {{ if and (not $edge) (not $cks) }}
      <p class="color-positive">No unacked alerts 🎉</p>
    {{ else }}
      <ul class="list list-gap-10 collapsible-container" data-collapse-after="5">
      {{ range $edge }}
        <li>
          <a class="size-h5 color-highlight block text-truncate" href="${opsgenieOrgUrl}/alert/detail/{{ .String "id" }}/details" target="_blank" rel="noreferrer">{{ .String "message" }}</a>
          <ul class="list-horizontal-text">
            <li>EDGE</li>
            <li{{ if or (eq (.String "priority") "P1") (eq (.String "priority") "P2") }} class="color-negative"{{ end }}>{{ .String "priority" }}</li>
            <li>{{ printf "%.10s" (.String "createdAt") }}</li>
          </ul>
        </li>
      {{ end }}
      {{ range $cks }}
        <li>
          <a class="size-h5 color-highlight block text-truncate" href="${opsgenieOrgUrl}/alert/detail/{{ .String "id" }}/details" target="_blank" rel="noreferrer">{{ .String "message" }}</a>
          <ul class="list-horizontal-text">
            <li>CKS</li>
            <li{{ if or (eq (.String "priority") "P1") (eq (.String "priority") "P2") }} class="color-negative"{{ end }}>{{ .String "priority" }}</li>
            <li>{{ printf "%.10s" (.String "createdAt") }}</li>
          </ul>
        </li>
      {{ end }}
      </ul>
    {{ end }}
  '';

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

  # Both start/end dates are computed at render time (now/offsetNow inside
  # the template itself, not baked into a static `parameters` value
  # at Nix build time), so the 14-day window keeps rolling forward on every
  # cache refresh instead of going stale after deploy. This needs the
  # "additional requests from within a template" pattern (newRequest |
  # withHeader | withParameter | getResponse) since Glance's static `url`/
  # `parameters` widget properties can't reference template functions.
  # Poster art uses gjson's `#(coverType=="poster")` array query since
  # images.0 isn't reliably the poster.
  upcomingReleasesTemplate = ''
    {{ $start := now | formatTime "DateOnly" }}
    {{ $end := offsetNow "336h" | formatTime "DateOnly" }}
    {{ $sonarr := newRequest "${sonarrHost}/api/v3/calendar"
        | withHeader "X-Api-Key" "''${SONARR_API_KEY}"
        | withParameter "start" $start
        | withParameter "end" $end
        | withParameter "unmonitored" "false"
        | withParameter "includeSeries" "true"
        | getResponse }}
    {{ $radarr := newRequest "${radarrHost}/api/v3/calendar"
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
        {{ range $tvItems }}
          <a href="${sonarrHost}" target="_blank" rel="noreferrer" style="flex:0 0 auto;width:130px;text-decoration:none;color:inherit">
            <img src="{{ .String "series.images.#(coverType==\"poster\").remoteUrl" }}" style="width:130px;height:195px;object-fit:cover;border-radius:8px;display:block" alt="" onerror="this.style.visibility='hidden'" />
            <div class="size-h5 color-highlight text-truncate" style="margin-top:6px">{{ .String "series.title" }}</div>
            <div class="size-h6 color-subdue text-truncate">S{{ .Int "seasonNumber" }}:E{{ .Int "episodeNumber" }} · {{ printf "%.10s" (.String "airDateUtc") }}</div>
          </a>
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
          <a href="${radarrHost}" target="_blank" rel="noreferrer" style="flex:0 0 auto;width:130px;text-decoration:none;color:inherit">
            <img src="{{ .String "images.#(coverType==\"poster\").remoteUrl" }}" style="width:130px;height:195px;object-fit:cover;border-radius:8px;display:block" alt="" onerror="this.style.visibility='hidden'" />
            <div class="size-h5 color-highlight text-truncate" style="margin-top:6px">{{ .String "title" }}</div>
            <div class="size-h6 color-subdue text-truncate">{{ printf "%.10s" (.String "inCinemas") }}</div>
          </a>
        {{ end }}
        </div>
      {{ end }}
    {{ else }}
      <p class="size-h6 color-negative">Radarr: {{ $radarr.Response.Status }}</p>
    {{ end }}
    </div>
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
  ghNotificationsTemplate = ''
    {{ $items := .JSON.Array "" }}
    {{ if not $items }}
      <p class="color-positive">No unread notifications 🎉</p>
    {{ else }}
      <ul class="list list-gap-10 collapsible-container" data-collapse-after="8">
      {{ range $items }}
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
        <li id="gh-notif-{{ $id }}">
          <div class="flex items-center gap-5">
            <span class="shrink-0">{{ if eq $type "PullRequest" }}${octiconNotificationPullRequest}{{ else if eq $type "Issue" }}${octiconNotificationIssue}{{ else if eq $type "Release" }}${octiconNotificationRelease}{{ else if eq $type "Commit" }}${octiconNotificationCommit}{{ else if eq $type "CheckSuite" }}${octiconNotificationCheckSuite}{{ else if eq $type "Discussion" }}${octiconNotificationDiscussion}{{ else }}${octiconNotificationDefault}{{ end }}</span>
            <a class="size-h5 color-highlight block text-truncate" href="{{ $webUrl }}" target="_blank" rel="noreferrer">{{ .String "subject.title" }}</a>
            <span class="shrink-0" style="margin-left:auto;display:flex;gap:6px">
              <button type="button" style="${ghActionButtonStyle}" onmouseover="this.style.background='${ghActionButtonHoverBg}'" onmouseout="this.style.background='${ghActionButtonBg}'" onclick="var el=document.getElementById('gh-notif-{{ $id }}');this.disabled=true;el.style.opacity='.4';fetch(&quot;''${GH_NOTIFICATION_ACTION_URL}&quot;,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'{{ $id }}',action:'done'})}).then(function(r){if(r.ok){el.remove()}else{el.style.opacity='1'}}).catch(function(){el.style.opacity='1'})">${octiconCheckSmall}<span>Done</span></button>
              <button type="button" style="${ghActionButtonStyle}" onmouseover="this.style.background='${ghActionButtonHoverBg}'" onmouseout="this.style.background='${ghActionButtonBg}'" onclick="var el=document.getElementById('gh-notif-{{ $id }}');this.disabled=true;el.style.opacity='.4';fetch(&quot;''${GH_NOTIFICATION_ACTION_URL}&quot;,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'{{ $id }}',action:'unsubscribe'})}).then(function(r){if(r.ok){el.remove()}else{el.style.opacity='1'}}).catch(function(){el.style.opacity='1'})">${octiconBellSlashSmall}<span>Unsubscribe</span></button>
            </span>
          </div>
          <div class="size-h6 color-subdue">{{ $repo }} · {{ .String "reason" }}</div>
        </li>
      {{ end }}
      </ul>
    {{ end }}
  '';
in
{
  sops = {
    secrets = {
      "opsgenie/edge-stack/api-key" = config.custom.mkSecret { mode = "0400"; };
      "opsgenie/gksv3-on-call/api-key" = config.custom.mkSecret { mode = "0400"; };
      "jellyfin/api-key" = config.custom.mkSecret { mode = "0400"; };
      "jellyfin/server-id" = config.custom.mkSecret { mode = "0400"; };
      "jellyfin/user-id" = config.custom.mkSecret { mode = "0400"; };
      "radarr/api-key" = config.custom.mkSecret { mode = "0400"; };
      "sonarr/api-key" = config.custom.mkSecret { mode = "0400"; };
      # Named "glance/webhook/..." rather than "n8n/webhook/..." because
      # secrets.sops.yaml already has a real nested "n8n:" mapping (from
      # n8n/runners/authToken); sops-install-secrets resolves that as a
      # nested path once the first segment already exists as a mapping,
      # which broke lookup for a flat "n8n/webhook/..." key.
      "glance/webhook/gh-notification-action-url" = config.custom.mkSecret { mode = "0400"; };
      "glance/webhook/nixpkgs-pr-mark-read-url" = config.custom.mkSecret { mode = "0400"; };
      "glance/webhook/nixpkgs-pr-read-list-url" = config.custom.mkSecret { mode = "0400"; };
    };
    templates."glance.env" = {
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
                        title = "brkn.lol";
                        links = [
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
                    cache = "6h";
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
        ];
      };
    };

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
  custom.authelia.extraTwoFactorDomains = [ glanceHost ];
}
