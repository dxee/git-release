#!/bin/bash
set -e

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 1 && $# -ne 2 ]]; then
  echo 'Usage: run-revert-release.sh <release-version>'
  echo 'For example: run-revert-release.sh 0.1.0'
  exit 2
fi

RELEASE_VERSION=$1

if [ -f "${SCRIPT_PATH}/.common-util.sh" ]; then
  # shellcheck source=.common-util.sh
  source "${SCRIPT_PATH}/.common-util.sh"
else
  echo 'Missing file .common-util.sh. Aborting'
  exit 1
fi

RELEASE_BRANCH=$(format_release_branch_name "${RELEASE_VERSION}")

check_local_workspace_state "run-revert-release"

if [ $# -eq 1 ]; then
  echo "Warning! This script will delete every local commit on branches ${DEVELOP_BRANCH} and ${MASTER_BRANCH} !"
  echo "Only continue if you know what you are doing with following command:"
  echo "$ run-revert-release.sh ${RELEASE_VERSION} --iknowwhatimdoing"
  exit 2
fi

DOES_HE_KNOW_WHAT_HE_IS_DOING=$2
if [ ! "${DOES_HE_KNOW_WHAT_HE_IS_DOING}" = '--iknowwhatimdoing' ]; then
  echo 'Usage: run-revert-release.sh <release-version>'
  echo 'For example: run-revert-release.sh 0.1.0'
  exit 2
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# revert master branch
git checkout "${MASTER_BRANCH}"
git reset "${REMOTE_REPO}/${MASTER_BRANCH}" --hard

# revert develop branch
git checkout "${DEVELOP_BRANCH}"
git reset "${REMOTE_REPO}/${DEVELOP_BRANCH}" --hard

# delete release branch
if git rev-parse --verify "${RELEASE_BRANCH}"; then
  git branch -D "${RELEASE_BRANCH}"
fi

# delete release tag
RELEASE_TAG=$(format_release_tag "${RELEASE_VERSION}")
if git rev-parse --verify "${RELEASE_TAG}"; then
  # delete local tag
  git tag -d "${RELEASE_TAG}"
  # Also delete remote tag
  git push "${REMOTE_REPO}" -d refs/tags/"${RELEASE_TAG}"
fi

# return to previous branch
if [[ ! $(git rev-parse --abbrev-ref HEAD) == "${CURRENT_BRANCH}" ]]; then
  git checkout "${CURRENT_BRANCH}"
fi
