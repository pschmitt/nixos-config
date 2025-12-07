#!/usr/bin/env bash

set -euo pipefail

: "${YUM_REPO:=yum.eu-frankfurt-1.oci.oraclecloud.com}"
: "${ORACLE_LINUX_VERSION:=9}"
: "${DOCKER_RUN_TIMEOUT:=300}"

cd "$(
  cd "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)" || exit 9

echo "Checking connectivity to ${YUM_REPO}..." >&2
if ! curl --connect-timeout 5 --max-time 10 --silent --head \
  "https://${YUM_REPO}/repo/OracleLinux/OL${ORACLE_LINUX_VERSION}/oci/included/x86_64/" >/dev/null
then
  echo "Unable to reach ${YUM_REPO}; ensure netbird/VPN connectivity is active." >&2
  exit 1
fi

docker build \
  --build-arg "YUM_REPO=${YUM_REPO}" \
  --build-arg "ORACLE_LINUX_VERSION=${ORACLE_LINUX_VERSION}" \
  -t oracle-cloud-agent-urls .

if [[ "${DOCKER_RUN_TIMEOUT}" == "0" ]]
then
  docker run --rm --net=host oracle-cloud-agent-urls
else
  if ! timeout "${DOCKER_RUN_TIMEOUT}s" docker run --rm --net=host oracle-cloud-agent-urls
  then
    echo "docker run timed out; check connectivity to ${YUM_REPO}." >&2
    exit 1
  fi
fi
