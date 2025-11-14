#!/usr/bin/env bash

set -euo pipefail

if pgrep -x wvkbd-mobintl >/dev/null 2>&1; then
  pkill -x wvkbd-mobintl
else
  setsid wvkbd-mobintl >/dev/null 2>&1 &
fi
