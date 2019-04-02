#!/bin/bash
set -e

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -ne 2 ]; then
  echo 'Usage: hotfix_finish.sh <hotfix-version> <next-snapshot-version>'
  echo 'For example:'
  echo 'hotfix_finish.sh 0.2.1 0.3.0'
  exit 2
fi

HOTFIX_VERSION=$1
NEXT_VERSION=$2

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

if [ ! "${HOTFIX_BRANCH}" = "${CURRENT_BRANCH}" ]; then
  echo "Please checkout the branch '$HOTFIX_BRANCH' before processing this hotfix release."
  exit 1
fi

check_local_workspace_state "hotfix_finish"

git checkout "${HOTFIX_BRANCH}" && git pull "${REMOTE_REPO}"

cd "${GIT_REPO_DIR}"
git reset --hard

cd "${GIT_REPO_DIR}"

if ! is_workspace_clean; then
  # commit hotfix versions
  HOTFIX_RELEASE_COMMIT_MESSAGE=$(get_release_hotfix_commit_message "${HOTFIX_VERSION}")
  git commit -am "${HOTFIX_RELEASE_COMMIT_MESSAGE}"
else
  echo "Nothing to commit..."
fi

cd "${GIT_REPO_DIR}"
git reset --hard

# merge current hotfix into master
git checkout "${MASTER_BRANCH}" && git pull "${REMOTE_REPO}"
git merge --no-edit "${HOTFIX_BRANCH}"

# create release tag
HOTFIX_TAG=$(format_release_tag "${HOTFIX_VERSION}")
HOTFIX_TAG_MESSAGE=$(get_hotfix_relesae_tag_message "${HOTFIX_VERSION}")

# add changelog
"${GIT_REPO_DIR}"/scripts/git-changlog/run.sh -n -t "${HOTFIX_TAG}"
git add .
git commit -m 'docs(release): Add CHANGELOG.md'
git push --set-upstream "${REMOTE_REPO}" "${HOTFIX_BRANCH}"

git tag -a "${HOTFIX_TAG}" -m "${HOTFIX_TAG_MESSAGE}"

git checkout "${HOTFIX_BRANCH}"

# prepare next snapshot version
NEXT_SNAPSHOT_VERSION=$(format_snapshot_version "${NEXT_VERSION}")
cd "${GIT_REPO_DIR}"

if ! is_workspace_clean; then
  # commit next snapshot versions
  SNAPSHOT_AFTER_HOTFIX_COMMIT_MESSAGE=$(get_next_snapshot_commit_message_after_hotfix "${NEXT_SNAPSHOT_VERSION}" "${HOTFIX_VERSION}")
  git commit -am "${SNAPSHOT_AFTER_HOTFIX_COMMIT_MESSAGE}"
else
  echo "Nothing to commit..."
fi

# merge next snapshot version into develop
git checkout "${DEVELOP_BRANCH}"

if git merge --no-edit "${HOTFIX_BRANCH}"; then
  git push --atomic ${REMOTE_REPO} ${MASTER_BRANCH} ${DEVELOP_BRANCH} ${HOTFIX_BRANCH} --follow-tags
  if [ $? -eq 0 ]; then
    git push "${REMOTE_REPO}" -d "${HOTFIX_BRANCH}"
    echo "# Okay, now you've got a new tag ${HOTFIX_VERSION} and commits on ${MASTER_BRANCH} and ${DEVELOP_BRANCH}"
  fi
else
  echo "# Okay, you have got a conflict while merging onto ${DEVELOP_BRANCH}"
  echo "# but don't panic, in most cases you can easily resolve the conflicts (in some cases you even do not need to merge all)."
  echo "# Please do so and continue the hotfix finishing with the following command:"
  echo "git push --atomic ${REMOTE_REPO} ${MASTER_BRANCH} ${DEVELOP_BRANCH} ${HOTFIX_BRANCH} --follow-tags # all or nothing"
fi
