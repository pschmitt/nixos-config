def ansi_esc: "\u001b";
def reset: "\(ansi_esc)[0m";
def bold: "\(ansi_esc)[1m";
def dim: "\(ansi_esc)[2m";
def green: "\(ansi_esc)[32m";
def yellow: "\(ansi_esc)[33m";
def red: "\(ansi_esc)[31m";

def badge:
  (if $account == "PERSONAL" then 208 else 141 end) as $bg |
  "\(ansi_esc)[1;30;48;5;\($bg)m \($account) \(reset)";

def branch_color:
  "\(ansi_esc)[38;5;141m";

def format_relative(diff):
  if diff <= 0 then "<1m"
  elif diff < 3600 then
    ((diff / 60) | floor) as $m | if $m == 0 then "<1m" else "\($m)m" end
  elif diff < 7200 then
    ((diff / 3600) | floor) as $h |
    (((diff % 3600) / 60) | floor) as $m |
    if $m > 0 then "\($h)h\($m)m" else "\($h)h" end
  elif diff < 86400 then
    "\((diff + 1800) / 3600 | floor)h"
  else
    "\((diff + 43200) / 86400 | floor)d"
  end;

def format_usd(amt):
  (amt * 100 | round) as $cents |
  "\($cents / 100 | floor).\($cents % 100 | if . < 10 then "0\(.)" else tostring end)";

. as $in |
[
  "\(badge) \(bold)\($in.model.display_name // $in.model.id // "Claude")\(reset)",

  (
    if ($branch // "") != "" and $branch != $default_branch then
      "\(branch_color) \($branch)\(reset)"
    else empty end
  ),

  (
    ($in.workspace.current_dir // "") | split("/") | last | select(. != null and . != "")
  ),

  (
    $in.context_window.used_percentage | select(. != null) | round |
    (if . >= 80 then red elif . >= 50 then yellow else green end) as $c |
    "\($c)\(.)%\(reset) ctx"
  ),

  (
    $in.cost.total_cost_usd | select(. != null and . > 0.005) |
    "\(green)$\(format_usd(.))\(reset)"
  ),

  (
    $in.rate_limits // {} | to_entries[] |
    select(.value != null and (.value.used_percentage // 0) > 50) |
    (if .key == "five_hour" then "5h"
     elif .key == "seven_day" then "7d"
     elif .key == "seven_day_opus" then "7d-opus"
     elif .key == "seven_day_sonnet" then "7d-sonnet"
     elif .key == "spend_limit" then "spend"
     else .key end) as $name |
    (.value.used_percentage | round) as $pct |
    (if $pct >= 80 then red else yellow end) as $c |
    (if .value.resets_at != null and .value.resets_at > 0 then
      format_relative(.value.resets_at - now)
    else "" end) as $rel |
    if $rel != "" then
      "\($name) \($c)\($pct)%\(reset) \(dim)\($rel)\(reset)"
    else
      "\($name) \($c)\($pct)%\(reset)"
    end
  )
] | join("  ")
