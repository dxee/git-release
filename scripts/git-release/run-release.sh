#!/bin/bash
set -e

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_PATH}/.common-util.sh" ]; then
  # shellcheck source=.common-util.sh
  source "${SCRIPT_PATH}/.common-util.sh"
else
  echo 'Missing file .common-util.sh. Aborting'
  exit 1
fi

CHANGELOG="Y"
RELEASE_VERSION=""
NEXT_VERSION=""

while [ "$1" != "" ]; do
  case $1 in
  --nochglog)
    CHANGELOG="N"
    ;;
  -r | --releaseversion)
    RELEASE_VERSION="$2"
    shift
    ;;
  -n | --nextversion)
    NEXT_VERSION="$2"
    shift
    ;;
  *)
    echo 'Usage: run-release.sh [--nochglog] <-r <version>> <-n <version>>'
    exit 2
    ;;
  esac
  shift
done

RELEASE_BRANCH=$(format_release_branch_name "$RELEASE_VERSION")
RELEASE_TAG=$(format_release_tag "${RELEASE_VERSION}")
NEXT_SNAPSHOT_VERSION=$(format_snapshot_version "${NEXT_VERSION}")

if [ ! "${CURRENT_BRANCH}" = "${DEVELOP_BRANCH}" ]; then
  echo "Please checkout the branch '${DEVELOP_BRANCH}' before processing this release script."
  exit 1
fi

check_local_workspace_state "run-release"

## update local develop branch
git checkout "${DEVELOP_BRANCH}" && git pull "${REMOTE_REPO}"

# check and create master branch if not present
if ! is_branch_existing "${MASTER_BRANCH}" ] && ! is_branch_existing "remotes/${REMOTE_REPO}/${MASTER_BRANCH}"; then
  git checkout -b "${MASTER_BRANCH}" "${DEVELOP_BRANCH}"
  git push --set-upstream "${REMOTE_REPO}" "${MASTER_BRANCH}"
fi

# checkout release branch
git checkout -b "${RELEASE_BRANCH}" "${DEVELOP_BRANCH}"

# commit release versions
if [[ "${CHANGELOG}" = "Y" ]]; then
  RELEASE_COMMIT_MESSAGE=$(get_release_commit_message "${NEXT_VERSION}")

  "${GIT_REPO_DIR}"/scripts/git-changlog/run-changelog.sh -n -t "${RELEASE_TAG}" && cd "${GIT_REPO_DIR}"
  git add .
  git commit -am "${RELEASE_COMMIT_MESSAGE}"
fi

# merge current develop (over release branch) into master
git checkout "${MASTER_BRANCH}" && git pull "${REMOTE_REPO}"
git merge -X theirs --no-edit "${RELEASE_BRANCH}"

# create release tag on master
RELEASE_TAG_MESSAGE=$(get_release_tag_message "${RELEASE_VERSION}")
git tag -a "${RELEASE_TAG}" -m "${RELEASE_TAG_MESSAGE}"

# merge release into develop
git checkout "${DEVELOP_BRANCH}" && git pull "${REMOTE_REPO}"
git merge -X theirs --no-edit "${RELEASE_BRANCH}"

if is_workspace_clean; then
  echo "Nothing to commit..."
else
  # Commit next snapshot versions into develop
  SNAPSHOT_COMMIT_MESSAGE=$(get_next_snapshot_commit_message "${NEXT_SNAPSHOT_VERSION}")
  git commit -am "${SNAPSHOT_COMMIT_MESSAGE}"
fi

if git merge --no-edit "${RELEASE_BRANCH}"; then
  # Nope, doing that automtically is too dangerous. But the command is great!
  git push --atomic ${REMOTE_REPO} ${MASTER_BRANCH} ${DEVELOP_BRANCH} --follow-tags
  if [ $? -eq 0 ]; then
    git branch -D "${RELEASE_BRANCH}"
    echo "# Okay, now you've got a new tag ${RELEASE_VERSION} and commits on ${MASTER_BRANCH} and ${DEVELOP_BRANCH}."
  fi
else
  echo "# Okay, you have got a conflict while merging onto ${DEVELOP_BRANCH}"
  echo "# but don't panic, in most cases you can easily resolve the conflicts (in some cases you even do not need to merge all)."
  echo "# Please do so and finish the release process with the following command:"
  echo "git push --atomic ${REMOTE_REPO} ${MASTER_BRANCH} ${DEVELOP_BRANCH} --follow-tags # all or nothing"
fi
