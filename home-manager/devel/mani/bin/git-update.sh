#!/usr/bin/env bash

REMOTE=${REMOTE:-origin}

# Check if the current directory is a Git repository
if ! git rev-parse --is-inside-work-tree &>/dev/null
then
  echo "$PWD is not a Git repository" >&2
  exit 2
fi

if ! git fetch --all
then
  echo "Failed to fetch from remote ${REMOTE}." >&2
  exit 1
fi

# Get the name of the current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "$PWD: current branch $CURRENT_BRANCH"

if [[ "$CURRENT_BRANCH" == "HEAD" ]]
then
  echo "Detached HEAD state. Skipping update." >&2
  exit 0
fi

# Determine the default branch from the remote's HEAD, fall back to static list
MAIN_BRANCH=$(git symbolic-ref --short "refs/remotes/${REMOTE}/HEAD" 2>/dev/null)
MAIN_BRANCH="${MAIN_BRANCH##*/}"

if [[ -z "$MAIN_BRANCH" ]]
then
  echo "Could not detect default branch from remote; falling back to main/master/dev." >&2
  case "$CURRENT_BRANCH" in
    main|master|dev)
      MAIN_BRANCH="$CURRENT_BRANCH"
      ;;
    *)
      echo "Not on main/master/dev. Skipping update." >&2
      exit 0
      ;;
  esac
fi

if [[ "$CURRENT_BRANCH" != "$MAIN_BRANCH" ]]
then
  echo "Not on default branch ($MAIN_BRANCH). Skipping update." >&2
  exit 0
fi

# Optional: Check for uncommitted changes
# if ! git diff-index --quiet HEAD --
# then
#   echo "Uncommitted changes in $PWD. Skipping update."
#   exit 0
# fi

# Try to rebase, and if there are conflicts, abort the rebase
if ! git pull --ff-only --rebase --autostash
then
  echo "Rebase conflict in $PWD. Aborting rebase." >&2
  git rebase --abort
  exit 1
fi

echo "$PWD: Rebased successfuly."

git log -5 --pretty=format:"[%ad] %h: %s" --date=iso

exit 0
