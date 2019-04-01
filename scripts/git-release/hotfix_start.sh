#!/bin/bash
set -e

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_PATH}/.version.sh" ]; then
  # shellcheck source=.version.sh
  source "${SCRIPT_PATH}/.version.sh"
else
  VERSION="UNKNOWN VERSION"
fi

echo "Release scripts (hotfix-start, version: ${VERSION})"

if [ $# -ne 1 ]; then
  echo 'Usage: hotfix_start.sh <hotfix-version>'
  echo 'For example:'
  echo 'hotfix_start.sh 0.2.1'
  exit 2
fi

HOTFIX_VERSION=$1
HOTFIX_SNAPSHOT_VERSION="${HOTFIX_VERSION}-SNAPSHOT"

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

check_local_workspace_state "hotfix_start"

git checkout "${MASTER_BRANCH}" && git pull "${REMOTE_REPO}"
git checkout -b "${HOTFIX_BRANCH}"

set_modules_version "${HOTFIX_SNAPSHOT_VERSION}"
cd "${GIT_REPO_DIR}"

if ! is_workspace_clean; then
  # commit hotfix versions
  START_HOTFOX_COMMIT_MESSAGE=$(get_start_hotfix_commit_message "${HOTFIX_SNAPSHOT_VERSION}")
  git commit -am "${START_HOTFOX_COMMIT_MESSAGE}"
else
  echo "Nothing to commit..."
fi

git push --set-upstream ${REMOTE_REPO} ${HOTFIX_BRANCH}
if [ $? -eq 0 ]; then
  echo "# Okay, now you've got a new hotfix branch called ${HOTFIX_BRANCH}"
fi
