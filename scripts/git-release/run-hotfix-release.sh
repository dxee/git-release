#!/bin/bash
set -e

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Necessary to calculate develop/master branch name
RELEASE_VERSION=${HOTFIX_VERSION}

if [ -f "${SCRIPT_PATH}/.common-util.sh" ]; then
  # shellcheck source=.common-util.sh
  source "${SCRIPT_PATH}/.common-util.sh"
else
  echo 'Missing file .common-util.sh. Aborting'
  exit 1
fi

CHANGELOG=""
HOTFIX_VERSION=""
NEXT_VERSION=""

unset RELEASE_VERSION

while [ "$1" != "" ]; do
  case $1 in
  -c | --chglog)
    CHANGELOG="Y"
    ;;
  -x | --hotfixversion)
    HOTFIX_VERSION="$2"
    shift
    ;;
  -n | --nextversion)
    NEXT_VERSION="$2"
    shift
    ;;
  *)
    echo 'Usage: run-hotfix-release.sh [--chglog] <-x <version>> <-n <version>>'
    exit 2
    ;;
  esac
  shift
done

HOTFIX_BRANCH=$(format_hotfix_branch_name "${HOTFIX_VERSION}")
HOTFIX_TAG=$(format_release_tag "${HOTFIX_VERSION}")

if [ ! "${HOTFIX_BRANCH}" = "${CURRENT_BRANCH}" ]; then
  echo "Please checkout the branch '$HOTFIX_BRANCH' before processing this hotfix release."
  exit 1
fi

check_local_workspace_state "run-hotfix-release"

# use hotfix branch
git checkout "${HOTFIX_BRANCH}" && git pull "${REMOTE_REPO}"

# add changelog
if [[ "${CHANGELOG}"="Y" ]]; then
  HOTFIX_RELEASE_COMMIT_MESSAGE=$(get_release_hotfix_commit_message "${HOTFIX_VERSION}")

  "${GIT_REPO_DIR}"/scripts/git-changlog/run-changelog.sh -n -t "${HOTFIX_TAG}" && cd "${GIT_REPO_DIR}"
  git add .
  git commit -m "${HOTFIX_RELEASE_COMMIT_MESSAGE}"
fi

# merge current hotfix into master
git checkout "${MASTER_BRANCH}" && git pull "${REMOTE_REPO}"
git merge --no-edit "${HOTFIX_BRANCH}"

# create release tag on master
HOTFIX_TAG_MESSAGE=$(get_hotfix_relesae_tag_message "${HOTFIX_VERSION}")
git tag -a "${HOTFIX_TAG}" -m "${HOTFIX_TAG_MESSAGE}"

# merge next snapshot version into develop
git checkout "${DEVELOP_BRANCH}"

if git merge --no-edit "${HOTFIX_BRANCH}"; then
  git push --atomic ${REMOTE_REPO} ${MASTER_BRANCH} ${DEVELOP_BRANCH} ${HOTFIX_BRANCH} --follow-tags
  if [ $? -eq 0 ]; then
    git push "${REMOTE_REPO}" -d "${HOTFIX_BRANCH}"
    git branch -D "${HOTFIX_BRANCH}"
    echo "# Okay, now you've got a new tag ${HOTFIX_VERSION} and commits on ${MASTER_BRANCH} and ${DEVELOP_BRANCH}"
  fi
else
  echo "# Okay, you have got a conflict while merging onto ${DEVELOP_BRANCH}"
  echo "# but don't panic, in most cases you can easily resolve the conflicts (in some cases you even do not need to merge all)."
  echo "# Please do so and continue the hotfix finishing with the following command:"
  echo "git push --atomic ${REMOTE_REPO} ${MASTER_BRANCH} ${DEVELOP_BRANCH} ${HOTFIX_BRANCH} --follow-tags # all or nothing"
fi
