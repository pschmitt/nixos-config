#!/usr/bin/env bash

set -euo pipefail

service="fievel.service"

if systemctl --user is-active --quiet "$service"
then
  systemctl --user stop "$service"
else
  systemctl --user start "$service"
fi

# vim: set ft=sh et ts=2 sw=2 :
