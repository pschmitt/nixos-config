#!/usr/bin/env bash

SOPS_AGE_KEY=$(ssh-to-age --private-key <~/.ssh/id_ed25519) sops "$@"
