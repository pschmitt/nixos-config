#!/usr/bin/env bash

git branch --merged | grep -Ev '(^\*|master|main|dev)' | \
  xargs --verbose --no-run-if-empty git branch --delete --force
