#!/usr/bin/env bash

mmonit_version() {
  {
    # NixOS
    if command -v mmonit.wrapped &>/dev/null
    then
      mmonit.wrapped --version
    else
      mmonit --version
    fi
  } | grep -P -m 1 -o "([0-9]{1,}\.)+[0-9]{1,}"
}

mmonit_latest_version() {
	curl -fsSL https://mmonit.com/releases.json |
		jq -r '.mmonit.version'

	# Alternative method, less elegant:
	# curl -fsSL https://mmonit.com/dist/ | \
	#   grep -P -o "(?<=mmonit-)([0-9]{1,}\.)+[0-9]{1,}" | \
	#   sort -Vu | \
	#   tail -n 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
	MMONIT_VERSION="$(mmonit_version)"

	if [[ -z "$MMONIT_VERSION" ]]
  then
		echo "Failed to determine the currently installed version of mmonit" >&2
		exit 1
	fi

	LATEST_MMONIT_VERSION="$(mmonit_latest_version)"

	if [[ -z "${LATEST_MMONIT_VERSION}" ]]
  then
		echo "Failed to determine the latest version of mmonit" >&2
		exit 1
	fi

	if [[ "${MMONIT_VERSION}" == "${LATEST_MMONIT_VERSION}" ]]
  then
		echo "mmonit is up to date ($MMONIT_VERSION)"
		exit 0
	else
		{
			echo "A new version of mmonit is available: $LATEST_MMONIT_VERSION"
			echo "Currently installed: ${MMONIT_VERSION}"
		} >&2
		exit 1
	fi
fi
