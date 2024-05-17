#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

docker build -t oracle-cloud-agent-urls .

docker run -it --rm oracle-cloud-agent-urls
