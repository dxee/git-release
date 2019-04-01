#!/bin/bash
set -e

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -ne 1 ]; then
  echo 'Usage: hotfix_start.sh <hotfix-version>'
  echo 'For example:'
  echo 'hotfix_start.sh 0.2.1'
  exit 2
fi

HOTFIX_VERSION=$1

# Necessary to calculate develop/master branch name
RELEASE_VERSION=${HOTFIX_VERSION}

if [ -f "${SCRIPT_PATH}/.common-util.sh" ]; then
  # shellcheck source=.common-util.sh
  source "${SCRIPT_PATH}/.common-util.sh"
else
  echo 'Missing file .common-util.sh. Aborting'
  exit 1
fi

unset RELEASE_VERSION

HOTFIX_BRANCH=$(format_hotfix_branch_name "${HOTFIX_VERSION}")

check_local_workspace_state "run-hotfix-start"

# delete hotfix branch
if git rev-parse --verify "${HOTFIX_BRANCH}"; then
  git branch -d "${HOTFIX_BRANCH}"
  git push "${REMOTE_REPO}" -d "${HOTFIX_BRANCH}"
  if [ $? -eq 0 ]; then
    echo "# Okay, now you've delete a hotfix branch called ${HOTFIX_BRANCH}"
  fi
fi
