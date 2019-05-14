DEF_TAG_RECENT="n.n.n"
GIT_LOG_OPTS=""
GIT_LOG_AUTHOR="https://github.com/"
GIT_LOG_COMMITS="https://github.com/dxee/git-release/commit/"
GIT_LOG_PR="https://github.com/dxee/git-release/pull"
GIT_LOG_FORMAT='%an|%h|%s'
GIT_LOG_DATE_FORMAT='%Y-%m-%d %H:%M:%S'
GIT_EDITOR="$(git var GIT_EDITOR)"
PROGNAME="git-changelog"
SUPPORTED_TYPES_LIST=(
    "feat.*:"
    "fix.*:"
    "refactor.*:"
    "perf.*:"
    "test.*:"
    "revert.*:"
    "chore.*:"
    "docs.*:"
    "BREAKING CHANGE:"
)
GROUP_LIST=()
OPTION=(
    "list_all:false"
    "list_style:false"
    "title_tag:$DEF_TAG_RECENT"
    "start_tag:"
    "start_commit:"
    "final_tag:"
    "output_file:"
    "use_stdout:false"
    "pr_only:false"
    "prune_old:false"
    "pro_release:false"
)

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_PATH}/../.common-util.sh" ]; then
    source "${SCRIPT_PATH}/../.common-util.sh"
else
    echo 'Missing file .common-util.sh. Aborting'
    exit 1
fi

map_user() {
    if [ "$1" = "Bing Fan" ]; then
        echo "lovoop"
    else
        echo "$1"
    fi
}

usage() {
    cat <<EOF
usage: $PROGNAME options [file]
usage: $PROGNAME -h|help|?

Generate a Changelog from git(1) tags (annotated or lightweight) and commit
messages. Existing Changelog files with filenames that begin with 'Change' or
'History' will be identified automatically and their content will be appended
to the new output generated (unless the -p|--prune-old option is used). If no
tags exist, then all commits are output; if tags exist, then only the most-
recent commits are output up to the last identified tag.

OPTIONS:
  -a, --all                 Retrieve all commits (ignores --start-tag/commit, --final-tag)
  -l, --list                Display commits as a list, with no titles
  -t, --tag                 Tag label to use for most-recent (untagged) commits
  -f, --final-tag           Newest tag to retrieve commits from in a range
  -s, --start-tag           Oldest tag to retrieve commits from in a range
      --start-commit        Like --start-tag but use commit instead of tag
  -n, --no-merges           Suppress commits from merged branches
  -m, --merges-only         Only uses merge commits (uses both subject and body of commit)
  -o, --pr-only             Only use PR merge request for log                            
  -p, --prune-old           Replace existing Changelog entirely with new content
  -x, --stdout              Write output to stdout instead of to a Changelog file
  -u, --author-t
  -r, --pro-release         Production release
  -h, --help, ?             Show this message
EOF
}

log_error() {
    [ $# -eq 0 ] && usage && exit 0

    echo
    echo "ERROR: " "$@"
    echo
}

get_group_title() {
    case "$1" in
    "fix.*:") echo "Bug Fixes" ;;
    "feat.*:") echo "Improvements" ;;
    "chore.*:") echo "Chores" ;;
    "docs.*:") echo "Documentations" ;;
    "refactor.*:") echo "Refactors" ;;
    "perf.*:") echo "Performance Improvements" ;;
    "test.*:") echo "Tests" ;;
    "revert.*:") echo "Reverts" ;;
    "BREAKING CHANGE:") echo "BREAKING CHANGES" ;;
    *) echo "Others" ;;
    esac
}

# make a temporary file
git_extra_mktemp() {
    mktemp -t "$(basename "$0")".XXXXXXX
}

filter_by_group() {
    local expGrep=""
    if [ $# -eq 0 ]; then
        echo "Nothing to filter on filter_by_group!"
        return 1 #failure
    fi
    local comment="${1#*|}"
    comment="${comment#*|}"
    comment="$(echo "$comment" | sed 's/^[ \t]*//g' | grep "^$2" | head -1)"
    [ -n "$comment" ] && echo "$1"
}

is_grouped_comment() {
    local supported_types_list_length="${#SUPPORTED_TYPES_LIST[@]}"
    for ((i = 0; i < "${supported_types_list_length}"; i++)); do
        local tmp_content="$(filter_by_group "$1" "${SUPPORTED_TYPES_LIST[$i]}")"
        [[ -n "$tmp_content" ]] && echo 1 && return
    done

    echo 0
}

contains() {
    for i in ${array[@]}; do
        [ "$i" == "$var" ] && echo 1 return
    done
}

create_content_changelog() {
    local group_list_length="${#GROUP_LIST[@]}"
    local group_others=()

    local supported_types_list_length="${#SUPPORTED_TYPES_LIST[@]}"
    for ((i = 0; i < "${supported_types_list_length}"; i++)); do
        local group="${SUPPORTED_TYPES_LIST[$i]}"
        local show_group=0
        for ((_i = 0; _i < "${group_list_length}"; _i++)); do
            local tmp_comment="${GROUP_LIST[$_i]}"
            local is_grouped_comment="$(is_grouped_comment "$tmp_comment")"

            if [ $is_grouped_comment -eq 0 ]; then
                local others_contains=0
                for ((__i = 0; __i < "${#group_others[@]}"; __i++)); do
                    [[ "${group_others[$__i]}" == "$tmp_comment" ]] && others_contains=1 && break
                done
                [[ $others_contains -eq 0 ]] && group_others+=("$tmp_comment")
                continue
            fi

            local tmp_content="$(filter_by_group "$tmp_comment" "$group")"
            if [ -z "$tmp_content" ]; then
                continue
            fi
            if [ $show_group -eq 0 ]; then
                printf "\n## $(get_group_title "$group")\n"
                show_group=1
            fi

            local commit_author="${tmp_content%%|*}"
            commit_author=$(map_user "$commit_author")
            local commit_hash="${tmp_content#*|}"
            local scope="${tmp_content%%:*}"

            # Remove start space of commit message
            local commit_msg="$(echo "${tmp_content#*:}" | sed 's/^[ \t]*//g')"
            commit_hash="${commit_hash%%|*}"
            # If has scop
            if [[ "$scope" =~ \)$ ]]; then
                scope="${scope%%\)*}"
                scope="${scope#*\(}"

                printf "* **%s** %s ([@%s]($GIT_LOG_AUTHOR%s) in [%s]($GIT_LOG_COMMITS%s))\n" \
                    "${scope#*\: }" \
                    "${commit_msg}" \
                    "$commit_author" "$commit_author" \
                    "$commit_hash" "$commit_hash"
            else
                printf "* %s ([@%s]($GIT_LOG_AUTHOR%s) in [%s]($GIT_LOG_COMMITS%s))\n" \
                    "${commit_msg}" \
                    "$commit_author" "$commit_author" \
                    "$commit_hash" "$commit_hash"
            fi
        done
    done

    local group_others_length="${#group_others[@]}"
    local show_other_group=0

    for ((i = 0; i < "${group_others_length}"; i++)); do
        local tmp_other_comment="${group_others[$i]}"
        [[ -z "$tmp_other_comment" ]] && continue
        if [ $show_other_group -eq 0 ]; then
            printf "\n## $(get_group_title)\n"
            show_other_group=1
        fi
        tmp_content="${tmp_other_comment#*|}"
        tmp_content="${tmp_content#*|}"
        commit_author="${tmp_other_comment%%|*}"
        commit_author=$(map_user "$commit_author")
        commit_hash="${tmp_other_comment#*|}"
        commit_hash="${commit_hash%%|*}"

        printf "* %s ([@%s]($GIT_LOG_AUTHOR%s) in [%s]($GIT_LOG_COMMITS%s))\n" \
            "${tmp_content#*|}" \
            "$commit_author" "$commit_author" \
            "$commit_hash" "$commit_hash"
    done
}

fetch_commit_range() {
    local list_all="${1:-false}"
    local start_tag="$2"
    local final_tag="$3"

    while read commit_list; do
        local commit_message="${commit_list#*|}"
        commit_message="${commit_message#*|}"
        # PR NO, eg: Merge pull request #1 in KKK/project from emp/feature1-dev to feature/feature1
        local pr_no
        pr_no="${pr_no%% *}"
        if [[ ! "$commit_message" =~ ^"Merge pull request #".* ]]; then
            if [[ "$(value_for_key_fake_assoc_array "pr_only" "${OPTION[*]}")" == true ]]; then
                if [[ "$commit_message" =~ ^"Merge branch '".* ]]; then
                    continue
                fi
            fi
            GROUP_LIST+=("$commit_list")
        else
            # PR NO, eg: Merge pull request #1 in KKK/project from emp/feature1-dev to feature/feature1
            pr_no="${commit_message#*#}"
            pr_no="${pr_no%% *}"
        fi

        # Resolve body
        local commit_author="${commit_list%%|*}"
        commit_author=$(map_user "$commit_author")
        local commit_hash="${commit_list#*|}"
        commit_hash="${commit_hash%%|*}"
        local commit_comment_body_row=0
        while read commit_comment_body; do
            if [ -z "$commit_comment_body" ]; then
                continue
            fi

            # Merge PR commit
            if [[ "$commit_message" =~ ^"Merge pull request #".* ]]; then
                # PR message, eg: feat: Add some feature
                local pr_commit_msg="[[PR#$pr_no]]($GIT_LOG_PR$pr_no)"
                if [[ "$commit_comment_body" =~ ^"* commit '".* ]] || [[ "$commit_comment_body" =~ ^"Squashed commit of the following:".* ]]; then
                    # show PR#* only
                    if [ $commit_comment_body_row -eq 0 ]; then
                        GROUP_LIST+=("$commit_author|$commit_hash|$pr_commit_msg")
                    fi
                    break
                fi
                commit_comment_body="$commit_comment_body $pr_commit_msg"
                commit_comment_body_row=$(($commit_comment_body_row+1))
            fi

            # None merge pr
            local is_grouped_comment="$(is_grouped_comment "$commit_comment_body")"
            if [ $is_grouped_comment -eq 1 ]; then
                GROUP_LIST+=("$commit_author|$commit_hash|$commit_comment_body")
            fi
        done <<<"$(
            git log -1 --pretty=format:%b $commit_hash
        )"
    done <<<"$(
        if [[ "$list_all" == true ]]; then
            git log $GIT_LOG_OPTS --date=format-local:"${GIT_LOG_DATE_FORMAT}" --pretty=format:"${GIT_LOG_FORMAT}"
        elif [[ -n "$final_tag" && "$start_tag" == "null" ]]; then
            git log $GIT_LOG_OPTS --date=format-local:"${GIT_LOG_DATE_FORMAT}" --pretty=format:"${GIT_LOG_FORMAT}" "${final_tag}"
        elif [[ -n "$final_tag" ]]; then
            git log $GIT_LOG_OPTS --date=format-local:"${GIT_LOG_DATE_FORMAT}" --pretty=format:"${GIT_LOG_FORMAT}" "${start_tag}"'..'"${final_tag}"
        elif [[ -n "$start_tag" ]]; then
            git log $GIT_LOG_OPTS --date=format-local:"${GIT_LOG_DATE_FORMAT}" --pretty=format:"${GIT_LOG_FORMAT}" "${start_tag}"'..'
        fi
    )"
    create_content_changelog
}

format_commit_plain() {
    local start_tag="$1"
    local final_tag="$2"

    printf "%s\n" "$(fetch_commit_range "false" "$start_tag" "$final_tag")"
}

format_commit_pretty() {
    local title_tag="$1"
    local title_date="$2"
    local start_tag="$3"
    local final_tag="$4"
    local title="$title_tag ($title_date)"
    local title_underline=""

    local i
    for i in $(seq ${#title}); do
        title_underline+="="
    done
    unset i

    printf '\n%s\n%s\n' "$title" "$title_underline"
    printf "\n%s\n" "$(fetch_commit_range "false" "$start_tag" "$final_tag")"
}

commit_list() {
    # parameter list supports empty arguments!
    local list_all="${1:-false}"
    shift
    local title_tag="$1"
    shift
    local start_tag="$1"
    shift
    local final_tag="$1"
    shift
    local list_style="${1:-false}"
    shift # enable/disable list format
    local start_commit="$1"
    shift
    local changelog="$FILE"
    local title_date="$(date +'%Y-%m-%d')"
    local tags_list=()
    local tags_list_keys=()
    local defaultIFS="$IFS"
    local IFS="$defaultIFS"

    if [[ -n "$start_commit" && "$final_tag" == "null" && "$start_tag" == "null" ]]; then
        # if there is not tag after $start_commit,
        # output directly without fetch all tags
        if [[ "$list_style" == true ]]; then
            format_commit_plain "${start_commit}~"
        else
            format_commit_pretty "$title_tag" "$title_date" "$start_commit~"
        fi

        return
    fi

    #
    # Tags look like this:
    #
    # >git log --tags --simplify-by-decoration --date="short" --pretty="format:%h$%x09%ad$%x09%d"
    #
    # ecf1f2b$        2015-03-15$     (HEAD, tag: v1.0.1, origin/master, origin/HEAD, master, hotfix/1.0.2)
    # a473e9c$        2015-03-04$     (tag: v1.0.0)
    # f2cb562$        2015-02-19$     (tag: v0.9.2)
    # 6197c2b$        2015-02-19$     (tag: v0.9.1)
    # 1e5f5e6$        2015-02-16$     (tag: v0.9.0)
    # 3de8ab5$        2015-02-11$     (origin/feature/restore-auto)
    # a15afd1$        2015-02-02$     (origin/feature/versionable)
    # 38a44e0$        2015-02-02$     (origin/feature/save-auto)
    # 3244b80$        2015-01-16$     (origin/feature/silent-history, upstream)
    # 85e45f8$        2014-08-25$
    #
    # The most-recent tag will be preceded by "HEAD, " if there have been zero
    # commits since the tag. Also notice that with gitflow, we see features.
    #

    # fetch our tags
    local ref date tag tab='%x09'
    local tag_regex='tag: *'
    while IFS=$'\t' read ref date tag; do
        [[ -z "${tag}" ]] && continue
        # strip out tags form ()
        # git v2.2.0+ supports '%D', like '%d' without the " (", ")" wrapping. One day we should use it instead.
        tag="${tag# }"
        tag="${tag//[()]/}"
        # trap tag if it points to last commit (HEAD)
        tag="${tag#HEAD*, }"
        # strip out branches
        [[ ! "${tag}" =~ ${tag_regex} ]] && continue
        # strip out any additional tags pointing to same commit, remove tag label
        tag="${tag%%,*}"
        tag="${tag#tag: }"
        if [[ "$(value_for_key_fake_assoc_array "pro_release" "${OPTION[*]}")" == true && "$(grep -E "^v([0-9])+.([0-9])+.([0-9])+$" <<<"${tag}")" != "${tag}" ]]; then
            continue
        fi
        tags_list+=("${tag}:${ref}=>${date}")
        tags_list_keys+=("${tag}")
    done <<<"$(git log --tags --simplify-by-decoration --date="short" --pretty="format:%h${tab}%ad${tab}%d")"
    IFS="$defaultIFS"
    unset tag_regex
    unset ref date tag tab

    local tags_list_keys_length="${#tags_list_keys[@]}"
    if [[ "${tags_list_keys_length}" -eq 0 ]]; then
        unset tags_list_keys_length
        if [[ "$list_style" == true ]]; then
            printf "%s" "$(fetch_commit_range "true")"
        else
            local title="$title_tag ( $title_date )"
            local title_underline=""

            local i
            for i in $(seq ${#title}); do
                title_underline+="="
            done
            unset i

            printf '\n%s\n%s\n' "$title" "$title_underline"
            printf "\n%s\n" "$(fetch_commit_range "true")"
        fi
        return
    fi

    local final_tag_found=false
    local start_tag_found=false
    local i
    for ((i = 0; i < "${tags_list_keys_length}"; i++)); do
        local curr_tag="${tags_list_keys[$i]}"
        local prev_tag="${tags_list_keys[$i + 1]:-null}"
        local curr_date="$(value_for_key_fake_assoc_array "${curr_tag}" "${tags_list[*]}")"
        curr_date="${curr_date##*=>}"

        # output latest commits, up until the most-recent tag, these are all
        # new commits made since the last tagged commit.
        if [[ $i -eq 0 && (-z "$final_tag" || "$final_tag" == "null") ]]; then
            if [[ "$list_style" == true ]]; then
                format_commit_plain "${curr_tag}" >>"$tmpfile"
            else
                format_commit_pretty "$title_tag" "$title_date" "${curr_tag}"
            fi
        fi

        # both final_tag and start_tag are "null", user just wanted recent commits
        [[ "$final_tag" == "null" && "$start_tag" == "null" ]] && break

        # find the specified final tag, continue until found
        if [[ -n "$final_tag" && "$final_tag" != "null" ]]; then
            [[ "$final_tag" == "${curr_tag}" ]] && final_tag_found=true
            [[ "$final_tag" != "${curr_tag}" && "${final_tag_found}" == false ]] && continue
        fi

        # find the specified start tag, break when found
        if [[ -n "$start_tag" ]]; then
            [[ "$start_tag" == "${curr_tag}" ]] && start_tag_found=true
            if [[ "${start_tag_found}" == true ]]; then
                if [[ -n "$start_commit" ]]; then

                    # output commits after start_commit to its closest tag
                    if [[ "$list_style" == true ]]; then
                        format_commit_plain "$start_commit~" "${curr_tag}"
                    else
                        format_commit_pretty "${curr_tag}" "${curr_date}" \
                            "$start_commit~" "${curr_tag}"
                    fi

                    break
                fi

                [[ "$start_tag" != "${curr_tag}" ]] && break

            fi
        fi

        # output commits made between prev_tag and curr_tag, these are all of the
        # commits related to the tag of interest.
        if [[ "$list_style" == true ]]; then
            format_commit_plain "${prev_tag}" "${curr_tag}"
        else
            format_commit_pretty "${curr_tag}" "${curr_date}" "${prev_tag}" "${curr_tag}"
        fi
        unset curr_date
        unset prev_tag
        unset curr_tag
    done
    unset i
    unset start_tag_found
    unset final_tag_found
    unset tags_list_keys_length

    return
}

commit_list_plain() {
    local list_all="${1:-false}"
    local start_tag="$2"
    local final_tag="$3"
    local start_commit="$4"

    commit_list "$list_all" "" "$start_tag" "$final_tag" "true" "$start_commit"
}

commit_list_pretty() {
    local list_all="${1:-false}"
    local title_tag="$2"
    local start_tag="$3"
    local final_tag="$4"
    local start_commit="$5"
    local title_date="$(date +'%Y-%m-%d')"

    commit_list "$list_all" "$title_tag" "$start_tag" "$final_tag" "false" \
        "$start_commit"
}

exit_all() {
    local pid_list=()
    local defaultIFS="$IFS"
    local IFS="$defaultIFS"

    stty sane
    echo
    echo "caught signal, shutting down"

    IFS=$'\n'
    # The format of `ps` is different between Windows and other platforms,
    # so we need to calculate the total column number(COL_NUM) of header first.
    # Why don't we just use the last column?
    # Because the body of CMD column may contain space and be treated as multiple fileds.
    pid_list=($(ps -f |
        awk -v ppid=$$ 'NR == 1 {
      COL_NUM = NF
    }
    $3 == ppid {
      # filter out temp processes created in this subshell
      if ($COL_NUM != "ps" && $COL_NUM != "awk" && $COL_NUM !~ "bash$")
        print $2
    }')
    )
    IFS="$defaultIFS"

    local pid
    for pid in "${pid_list[@]}"; do
        echo "killing: ${pid}"
        kill -TERM ${pid}
    done

    wait
    stty sane
    exit 1
}

trap 'exit_all' SIGINT SIGQUIT SIGTERM

main() {
    # empty string and "null" mean two different things!
    local start_tag="null"
    local final_tag="null"

    #
    # We work chronologically backwards from NOW towards start_tag where NOW also
    # includes the most-recent (un-tagged) commits. If no start_tag has been
    # specified, we work back to the very first commit; if a final_tag has been
    # specified, we begin at the final_tag and work backwards towards start_tag.
    #

    # An existing ChangeLog/History file will be appended to the output unless the
    # prune old (-p | --prune-old) option has been enabled.

    while [ "$1" != "" ]; do
        case $1 in
        -a | --all)
            OPTION=($(set_value_for_key_fake_assoc_array "list_all" true "${OPTION[*]}"))
            ;;
        -l | --list)
            OPTION=($(set_value_for_key_fake_assoc_array "list_style" true "${OPTION[*]}"))
            ;;
        -t | --tag)
            OPTION=($(set_value_for_key_fake_assoc_array "title_tag" "$2" "${OPTION[*]}"))
            shift
            ;;
        -f | --final-tag)
            OPTION=($(set_value_for_key_fake_assoc_array "final_tag" "$2" "${OPTION[*]}"))
            shift
            ;;
        -s | --start-tag)
            OPTION=($(set_value_for_key_fake_assoc_array "start_tag" "$2" "${OPTION[*]}"))
            shift
            ;;
        --start-commit)
            OPTION=($(set_value_for_key_fake_assoc_array "start_commit" "$2" "${OPTION[*]}"))
            shift
            ;;
        -r | --pro-release)
            OPTION=($(set_value_for_key_fake_assoc_array "pro_release" true "${OPTION[*]}"))
            ;;
        -n | --no-merges)
            GIT_LOG_OPTS='--no-merges'
            ;;
        -m | --merges-only)
            GIT_LOG_OPTS='--merges'
            ;;
        -o | --pr-only)
            OPTION=($(set_value_for_key_fake_assoc_array "pr_only" true "${OPTION[*]}"))
            ;;
        -p | --prune-old)
            OPTION=($(set_value_for_key_fake_assoc_array "prune_old" true "${OPTION[*]}"))
            ;;
        -x | --stdout)
            OPTION=($(set_value_for_key_fake_assoc_array "use_stdout" true "${OPTION[*]}"))
            ;;
        -h | ? | help | --help)
            usage
            exit 1
            ;;
        *)
            [[ "${1:0:1}" == '-' ]] && log_error "Invalid OPTION: $1" && usage && exit 1
            OPTION=($(set_value_for_key_fake_assoc_array "output_file" "$1" "${OPTION[*]}"))
            ;;
        esac
        shift
    done

    local tag="$(value_for_key_fake_assoc_array "start_tag" "${OPTION[*]}")"
    local start_commit="$(value_for_key_fake_assoc_array "start_commit" "${OPTION[*]}")"

    if [[ -n "$start_commit" ]]; then
        if [[ -n "${tag}" ]]; then
            log_error "--start-tag could not use with --start-commit!"
            return 1
        fi

        start_commit="$start_commit"
        start_tag="$(git describe --tags --contains "$start_commit" 2>/dev/null || echo 'null')"
        if [[ -z "$start_tag" ]]; then
            log_error "Could find the associative tag for the start-commit!"
            return 1
        fi

        # remove suffix from the $start_tag when no tag matched exactly
        start_tag="${start_tag%%~*}"
        # also remove "^0" added sometimes when tag matched exactly
        start_tag="${start_tag%%^0}"

    elif [[ -n "${tag}" ]]; then
        start_tag="$(git describe --tags --abbrev=0 "${tag}" 2>/dev/null)"
        if [[ -z "$start_tag" ]]; then
            log_error "Specified start-tag does not exist!"
            return 1
        fi
    fi

    if [[ -n "${tag}" ]]; then
        if [[ -n "$start_commit" ]]; then
            log_error "--start-tag could not use with --start-commit!"
            return 1
        fi

    fi
    unset tag

    local tag="$(value_for_key_fake_assoc_array "final_tag" "${OPTION[*]}")"
    if [[ -n "${tag}" ]]; then
        final_tag="$(git describe --tags --abbrev=0 "${tag}" 2>/dev/null)"
        if [[ -z "$final_tag" ]]; then
            log_error "Specified final-tag does not exist!"
            return 1
        fi
    fi
    unset tag

    #
    # generate changelog
    #
    local tmpfile="$(git_extra_mktemp)"
    local changelog="$(value_for_key_fake_assoc_array "output_file" "${OPTION[*]}")"
    local title_tag="$(value_for_key_fake_assoc_array "title_tag" "${OPTION[*]}")"

    if [[ "$(value_for_key_fake_assoc_array "list_style" "${OPTION[*]}")" == true ]]; then
        if [[ "$(value_for_key_fake_assoc_array "list_all" "${OPTION[*]}")" == true ]]; then
            commit_list_plain "true" >>"$tmpfile"
        else
            commit_list_plain "false" "$start_tag" "$final_tag" \
                "$start_commit" >>"$tmpfile"
        fi
    else
        if [[ "$(value_for_key_fake_assoc_array "list_all" "${OPTION[*]}")" == true ]]; then
            commit_list_pretty "true" "$title_tag" >>"$tmpfile"
        else
            commit_list_pretty "false" "$title_tag" "$start_tag" "$final_tag" \
                "$start_commit" >>"$tmpfile"
        fi
    fi

    if [[ -z "$changelog" ]]; then
        changelog="$(ls | egrep 'CHANGELOG.md' -i | head -n1)"
        if [[ -z "$changelog" ]]; then
            changelog="CHANGELOG.md"
        fi
    fi

    # append existing changelog?
    if [[ -f "$changelog" && "$(value_for_key_fake_assoc_array "prune_old" "${OPTION[*]}")" == false ]]; then
        cat "$changelog" >>"$tmpfile"
    fi

    # output file to stdout or move into place
    if [[ "$(value_for_key_fake_assoc_array "use_stdout" "${OPTION[*]}")" == true ]]; then
        cat "$tmpfile"
        rm -f "$tmpfile"
    else
        cp -f "$tmpfile" "$changelog"
        rm -f "$tmpfile"
    fi

    return
}

main "$@"

exit 0
