# set_value_for_key_fake_assoc_array()
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
set_value_for_key_fake_assoc_array() {
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

# value_for_key_fake_assoc_array()
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
value_for_key_fake_assoc_array() {
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