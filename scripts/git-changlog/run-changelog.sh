DEF_TAG_RECENT="n.n.n"
GIT_LOG_OPTS=""
GIT_LOG_AUTHOR="https://rdgit.travelsky.com/users/"
GIT_LOG_COMMITS="https://rdgit.travelsky.com/projects/DSS/repos/dss_v1_nrts_etl/commits/"
GIT_LOG_FORMAT='%an|%h|%s'
GIT_LOG_DATE_FORMAT='%Y-%m-%d %H:%M:%S'
GIT_EDITOR="$(git var GIT_EDITOR)"
PROGNAME="git-changelog"
supported_types_list=(
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
group_list=()

_usage() {
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
  -p, --prune-old           Replace existing Changelog entirely with new content
  -x, --stdout              Write output to stdout instead of to a Changelog file
  -u, --author-t
  -p, --pro-release         Production release
  -h, --help, ?             Show this message
EOF
}

_error() {
    [ $# -eq 0 ] && _usage && exit 0

    echo
    echo "ERROR: " "$@"
    echo
}

# _setValueForKeyFakeAssocArray()
# /*!
# @abstract Set value for key from a fake associative array
# @discussion
# Iterates over target_ary (an indexed array), searching for target_key, if the
#   key is found its value is set to new_value otherwise the target_key and
#   new_value are appended to the array.
#
#   The indexed array values must conform to this format:
#     "key:value"
#   Where key and value are separated by a single colon character.
#
#   Specify empty values as an empty, quoted string.
#
#   So-called "fake" associative arrays are useful for environments where the
#   installed version of bash(1) precedes 4.0.
# @param target_key Key to retrieve
# @param new_value New or updated value
# @param target_ary Indexed array to scan
# @return Returns new array with updated key (status 0) or an empty array
#   (status 1) on failure.
# */
_setValueForKeyFakeAssocArray() {
    # parameter list supports empty arguments!
    local target_key="$1"
    shift
    local new_value="$1"
    shift
    local target_ary=()
    local defaultIFS="$IFS"
    local IFS="$defaultIFS"
    local found=false

    IFS=$' ' target_ary=($1) IFS="$defaultIFS"

    [[ -z "${target_key}" || "${#target_ary[@]}" -eq 0 ]] && echo "${value}" && return 1

    local _target_ary_length="${#target_ary[@]}"
    local i
    for ((i = 0; i < "${_target_ary_length}"; i++)); do
        local __val="${target_ary[$i]}"

        if [[ "${__val%%:*}" == "${target_key}" ]]; then
            target_ary[$i]="${__val%%:*}:${new_value}"
            found=true
            break
        fi

        unset __val
    done
    unset i _target_ary_length

    # key not found, append
    [[ "$found" == false ]] && target_ary+=("${target_key}:${new_value}")

    printf "%s" "${target_ary[*]}"
}

# _valueForKeyFakeAssocArray()
# /*!
# @abstract Fetch value for key from a fake associative array
# @discussion
# Iterates over target_ary (an indexed array), searching for target_key, if the
#   key is found its value is returned.
#
#   The indexed array values must conform to this format:
#     "key:value"
#   Where key and value are separated by a single colon character.
#
#   So-called "fake" associative arrays are useful for environments where the
#   installed version of bash(1) precedes 4.0.
# @param target_key Key to retrieve
# @param target_ary Indexed array to scan
# @return Returns string containing value (status 0) or an empty string
#   (status 1) on failure.
# */
_valueForKeyFakeAssocArray() {
    local target_key="$1"
    local target_ary=()
    local defaultIFS="$IFS"
    local IFS="$defaultIFS"
    local value=""

    IFS=$' ' target_ary=($2) IFS="$defaultIFS"

    [[ -z "${target_key}" || "${#target_ary[@]}" -eq 0 ]] && echo "${value}" && return 1

    local t
    for t in "${target_ary[@]}"; do
        if [[ "${t%%:*}" == "${target_key}" ]]; then
            value="${t#*:}"
            break
        fi
    done
    unset t

    echo -e "${value}"
    return 0
}

_get_group_title() {
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
_git_extra_mktemp() {
    mktemp -t "$(basename "$0")".XXXXXXX
}

_filter_by_group() {
    local expGrep=""
    if [ $# -eq 0 ]; then
        echo "Nothing to filter on _filter_by_group!"
        return 1 #failure
    fi
    local comment="${1#*|}"
    comment="${comment#*|}"
    comment="$(echo "$comment" | sed 's/^[ \t]*//g' | grep "^$2" | head -1)"
    [ -n "$comment" ] && echo "$1"
}

_is_grouped_comment() {
    local supported_types_list_length="${#supported_types_list[@]}"
    for ((i = 0; i < "${supported_types_list_length}"; i++)); do
        local __tmp_content="$(_filter_by_group "$1" "${supported_types_list[$i]}")"
        [[ -n "$__tmp_content" ]] && echo 1 && return
    done

    echo 0
}

_contains() {
    for i in ${array[@]}; do
        [ "$i" == "$var" ] && echo 1 return
    done
}

_create_content_changelog() {
    local group_list_length="${#group_list[@]}"
    local group_others=()

    local supported_types_list_length="${#supported_types_list[@]}"
    for ((i = 0; i < "${supported_types_list_length}"; i++)); do
        local _group="${supported_types_list[$i]}"
        local _show_group=0
        for ((_i = 0; _i < "${group_list_length}"; _i++)); do
            local __tmp_comment="${group_list[$_i]}"
            local is_grouped_comment="$(_is_grouped_comment "$__tmp_comment")"

            if [ $is_grouped_comment -eq 0 ]; then
                local others_contains=0
                for ((__i = 0; __i < "${#group_others[@]}"; __i++)); do
                    [[ "${group_others[$__i]}" == "$__tmp_comment" ]] && others_contains=1 && break
                done
                [[ $others_contains -eq 0 ]] && group_others+=("$__tmp_comment")
                continue
            fi

            local __tmp_content="$(_filter_by_group "$__tmp_comment" "$_group")"
            if [ -z "$__tmp_content" ]; then
                continue
            fi
            if [ $_show_group -eq 0 ]; then
                printf "\n## $(_get_group_title "$_group")\n"
                _show_group=1
            fi

            local __commit_author="${__tmp_content%%|*}"
            local __commit_hash="${__tmp_content#*|}"
            local __scope="${__tmp_content%%\)*}"

            __commit_hash="${__commit_hash%%|*}"
            __scope="${__scope#*\(}"
            if [ "$__scope" != "$__tmp_content" ]; then
                printf "* **%s** %s ([@%s]($GIT_LOG_AUTHOR%s) in [%s]($GIT_LOG_COMMITS%s))\n" \
                    "${__scope#*\: }" \
                    "${__tmp_content#*\: }" \
                    "$__commit_author" "$__commit_author" \
                    "$__commit_hash" "$__commit_hash"
            else
                printf "* %s ([@%s]($GIT_LOG_AUTHOR%s) in [%s]($GIT_LOG_COMMITS%s))\n" \
                    "${__tmp_content#*\: }" \
                    "$__commit_author" "$__commit_author" \
                    "$__commit_hash" "$__commit_hash"
            fi
        done
    done

    local group_others_length="${#group_others[@]}"
    local show_other_group=0

    for ((i = 0; i < "${group_others_length}"; i++)); do
        local __tmp_other_comment="${group_others[$i]}"
        [[ -z "$__tmp_other_comment" ]] && continue
        if [ $show_other_group -eq 0 ]; then
            printf "\n## $(_get_group_title)\n"
            show_other_group=1
        fi
        __tmp_content="${__tmp_other_comment#*|}"
        __tmp_content="${__tmp_content#*|}"
        __commit_author="${__tmp_other_comment%%|*}"
        __commit_hash="${__tmp_other_comment#*|}"
        __commit_hash="${__commit_hash%%|*}"

        printf "* %s ([@%s]($GIT_LOG_AUTHOR%s) in [%s]($GIT_LOG_COMMITS%s))\n" \
            "${__tmp_content#*|}" \
            "$__commit_author" "$__commit_author" \
            "$__commit_hash" "$__commit_hash"
    done
}

_fetchCommitRange() {
    local list_all="${1:-false}"
    local start_tag="$2"
    local final_tag="$3"

    while read _commit_list; do
        group_list+=("$_commit_list")

        # Resolve body
        local __commit_author="${_commit_list%%|*}"
        local __commit_hash="${_commit_list#*|}"
        __commit_hash="${__commit_hash%%|*}"
        while read __commit_comment_body; do
            local is_grouped_comment="$(_is_grouped_comment "$__commit_comment_body")"
            if [ $is_grouped_comment -eq 1 ]; then
                group_list+=("$__commit_author|$__commit_hash|$__commit_comment_body")
            fi
        done <<<"$(
            git log -1 --pretty=format:%b $__commit_hash
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
    _create_content_changelog
}

_formatCommitPlain() {
    local start_tag="$1"
    local final_tag="$2"

    printf "%s\n" "$(_fetchCommitRange "false" "$start_tag" "$final_tag")"
}

_formatCommitPretty() {
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
    printf "\n%s\n" "$(_fetchCommitRange "false" "$start_tag" "$final_tag")"
}

commitList() {
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
            _formatCommitPlain "${start_commit}~"
        else
            _formatCommitPretty "$title_tag" "$title_date" "$start_commit~"
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
    local _ref _date _tag _tab='%x09'
    local _tag_regex='tag: *'
    while IFS=$'\t' read _ref _date _tag; do
        [[ -z "${_tag}" ]] && continue
        # strip out tags form ()
        # git v2.2.0+ supports '%D', like '%d' without the " (", ")" wrapping. One day we should use it instead.
        _tag="${_tag# }"
        _tag="${_tag//[()]/}"
        # trap tag if it points to last commit (HEAD)
        _tag="${_tag#HEAD*, }"
        # strip out branches
        [[ ! "${_tag}" =~ ${_tag_regex} ]] && continue
        # strip out any additional tags pointing to same commit, remove tag label
        _tag="${_tag%%,*}"
        _tag="${_tag#tag: }"
        if [[ "$(_valueForKeyFakeAssocArray "pro_release" "${option[*]}")" == true && "$(grep -qE "^v([0-9])+.([0-9])+.([0-9])+$" <<<"${_tag}")" != "${_tag}" ]]; then
            continue
        fi
        tags_list+=("${_tag}:${_ref}=>${_date}")
        tags_list_keys+=("${_tag}")
    done <<<"$(git log --tags --simplify-by-decoration --date="short" --pretty="format:%h${_tab}%ad${_tab}%d")"
    IFS="$defaultIFS"
    unset _tag_regex
    unset _ref _date _tag _tab

    local _tags_list_keys_length="${#tags_list_keys[@]}"
    if [[ "${_tags_list_keys_length}" -eq 0 ]]; then
        unset _tags_list_keys_length
        if [[ "$list_style" == true ]]; then
            printf "%s" "$(_fetchCommitRange "true")"
        else
            local title="$title_tag ( $title_date )"
            local title_underline=""

            local i
            for i in $(seq ${#title}); do
                title_underline+="="
            done
            unset i

            printf '\n%s\n%s\n' "$title" "$title_underline"
            printf "\n%s\n" "$(_fetchCommitRange "true")"
        fi
        return
    fi

    local _final_tag_found=false
    local _start_tag_found=false
    local i
    for ((i = 0; i < "${_tags_list_keys_length}"; i++)); do
        local __curr_tag="${tags_list_keys[$i]}"
        local __prev_tag="${tags_list_keys[$i + 1]:-null}"
        local __curr_date="$(_valueForKeyFakeAssocArray "${__curr_tag}" "${tags_list[*]}")"
        __curr_date="${__curr_date##*=>}"

        # output latest commits, up until the most-recent tag, these are all
        # new commits made since the last tagged commit.
        if [[ $i -eq 0 && (-z "$final_tag" || "$final_tag" == "null") ]]; then
            if [[ "$list_style" == true ]]; then
                _formatCommitPlain "${__curr_tag}" >>"$tmpfile"
            else
                _formatCommitPretty "$title_tag" "$title_date" "${__curr_tag}"
            fi
        fi

        # both final_tag and start_tag are "null", user just wanted recent commits
        [[ "$final_tag" == "null" && "$start_tag" == "null" ]] && break

        # find the specified final tag, continue until found
        if [[ -n "$final_tag" && "$final_tag" != "null" ]]; then
            [[ "$final_tag" == "${__curr_tag}" ]] && _final_tag_found=true
            [[ "$final_tag" != "${__curr_tag}" && "${_final_tag_found}" == false ]] && continue
        fi

        # find the specified start tag, break when found
        if [[ -n "$start_tag" ]]; then
            [[ "$start_tag" == "${__curr_tag}" ]] && _start_tag_found=true
            if [[ "${_start_tag_found}" == true ]]; then
                if [[ -n "$start_commit" ]]; then

                    # output commits after start_commit to its closest tag
                    if [[ "$list_style" == true ]]; then
                        _formatCommitPlain "$start_commit~" "${__curr_tag}"
                    else
                        _formatCommitPretty "${__curr_tag}" "${__curr_date}" \
                            "$start_commit~" "${__curr_tag}"
                    fi

                    break
                fi

                [[ "$start_tag" != "${__curr_tag}" ]] && break

            fi
        fi

        # output commits made between prev_tag and curr_tag, these are all of the
        # commits related to the tag of interest.
        if [[ "$list_style" == true ]]; then
            _formatCommitPlain "${__prev_tag}" "${__curr_tag}"
        else
            _formatCommitPretty "${__curr_tag}" "${__curr_date}" "${__prev_tag}" "${__curr_tag}"
        fi
        unset __curr_date
        unset __prev_tag
        unset __curr_tag
    done
    unset i
    unset _start_tag_found
    unset _final_tag_found
    unset _tags_list_keys_length

    return
}

commitListPlain() {
    local list_all="${1:-false}"
    local start_tag="$2"
    local final_tag="$3"
    local start_commit="$4"

    commitList "$list_all" "" "$start_tag" "$final_tag" "true" "$start_commit"
}

commitListPretty() {
    local list_all="${1:-false}"
    local title_tag="$2"
    local start_tag="$3"
    local final_tag="$4"
    local start_commit="$5"
    local title_date="$(date +'%Y-%m-%d')"

    commitList "$list_all" "$title_tag" "$start_tag" "$final_tag" "false" \
        "$start_commit"
}

_exit() {
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

    local _pid
    for _pid in "${pid_list[@]}"; do
        echo "killing: ${_pid}"
        kill -TERM ${_pid}
    done

    wait
    stty sane
    exit 1
}

trap '_exit' SIGINT SIGQUIT SIGTERM

main() {
    # empty string and "null" mean two different things!
    local start_tag="null"
    local final_tag="null"

    local option=(
        "list_all:false"
        "list_style:false"
        "title_tag:$DEF_TAG_RECENT"
        "start_tag:"
        "start_commit:"
        "final_tag:"
        "output_file:"
        "use_stdout:false"
        "prune_old:false"
        "pro_release:true"
    )

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
            option=($(_setValueForKeyFakeAssocArray "list_all" true "${option[*]}"))
            ;;
        -l | --list)
            option=($(_setValueForKeyFakeAssocArray "list_style" true "${option[*]}"))
            ;;
        -t | --tag)
            option=($(_setValueForKeyFakeAssocArray "title_tag" "$2" "${option[*]}"))
            shift
            ;;
        -f | --final-tag)
            option=($(_setValueForKeyFakeAssocArray "final_tag" "$2" "${option[*]}"))
            shift
            ;;
        -s | --start-tag)
            option=($(_setValueForKeyFakeAssocArray "start_tag" "$2" "${option[*]}"))
            shift
            ;;
        --start-commit)
            option=($(_setValueForKeyFakeAssocArray "start_commit" "$2" "${option[*]}"))
            shift
            ;;
        -r | --pro-release)
            option=($(_setValueForKeyFakeAssocArray "pro_release" true "${option[*]}"))
            shift
            ;;
        -n | --no-merges)
            GIT_LOG_OPTS='--no-merges'
            ;;
        -m | --merges-only)
            GIT_LOG_OPTS='--merges'
            ;;
        -p | --prune-old)
            option=($(_setValueForKeyFakeAssocArray "prune_old" true "${option[*]}"))
            ;;
        -x | --stdout)
            option=($(_setValueForKeyFakeAssocArray "use_stdout" true "${option[*]}"))
            ;;
        -h | ? | help | --help)
            _usage
            exit 1
            ;;
        *)
            [[ "${1:0:1}" == '-' ]] && _error "Invalid option: $1" && _usage && exit 1
            option=($(_setValueForKeyFakeAssocArray "output_file" "$1" "${option[*]}"))
            ;;
        esac
        shift
    done

    local _tag="$(_valueForKeyFakeAssocArray "start_tag" "${option[*]}")"
    local start_commit="$(_valueForKeyFakeAssocArray "start_commit" "${option[*]}")"

    if [[ -n "$start_commit" ]]; then
        if [[ -n "${_tag}" ]]; then
            _error "--start-tag could not use with --start-commit!"
            return 1
        fi

        start_commit="$start_commit"
        start_tag="$(git describe --tags --contains "$start_commit" 2>/dev/null || echo 'null')"
        if [[ -z "$start_tag" ]]; then
            _error "Could find the associative tag for the start-commit!"
            return 1
        fi

        # remove suffix from the $start_tag when no tag matched exactly
        start_tag="${start_tag%%~*}"
        # also remove "^0" added sometimes when tag matched exactly
        start_tag="${start_tag%%^0}"

    elif [[ -n "${_tag}" ]]; then
        start_tag="$(git describe --tags --abbrev=0 "${_tag}" 2>/dev/null)"
        if [[ -z "$start_tag" ]]; then
            _error "Specified start-tag does not exist!"
            return 1
        fi
    fi

    if [[ -n "${_tag}" ]]; then
        if [[ -n "$start_commit" ]]; then
            _error "--start-tag could not use with --start-commit!"
            return 1
        fi

    fi
    unset _tag

    local _tag="$(_valueForKeyFakeAssocArray "final_tag" "${option[*]}")"
    if [[ -n "${_tag}" ]]; then
        final_tag="$(git describe --tags --abbrev=0 "${_tag}" 2>/dev/null)"
        if [[ -z "$final_tag" ]]; then
            _error "Specified final-tag does not exist!"
            return 1
        fi
    fi
    unset _tag

    #
    # generate changelog
    #
    local tmpfile="$(_git_extra_mktemp)"
    local changelog="$(_valueForKeyFakeAssocArray "output_file" "${option[*]}")"
    local title_tag="$(_valueForKeyFakeAssocArray "title_tag" "${option[*]}")"

    if [[ "$(_valueForKeyFakeAssocArray "list_style" "${option[*]}")" == true ]]; then
        if [[ "$(_valueForKeyFakeAssocArray "list_all" "${option[*]}")" == true ]]; then
            commitListPlain "true" >>"$tmpfile"
        else
            commitListPlain "false" "$start_tag" "$final_tag" \
                "$start_commit" >>"$tmpfile"
        fi
    else
        if [[ "$(_valueForKeyFakeAssocArray "list_all" "${option[*]}")" == true ]]; then
            commitListPretty "true" "$title_tag" >>"$tmpfile"
        else
            commitListPretty "false" "$title_tag" "$start_tag" "$final_tag" \
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
    if [[ -f "$changelog" && "$(_valueForKeyFakeAssocArray "prune_old" "${option[*]}")" == false ]]; then
        cat "$changelog" >>"$tmpfile"
    fi

    # output file to stdout or move into place
    if [[ "$(_valueForKeyFakeAssocArray "use_stdout" "${option[*]}")" == true ]]; then
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
