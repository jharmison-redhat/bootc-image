#!/bin/bash

set -e

user="${1:-vllm}"
subuidfile="${2:-/etc/subuid}"
subgidfile="${3:-/etc/subgid}"

function addentry {
    local subxidfile
    subxidfile="$1"
    local subxids
    subxids=$(<"$subxidfile")

    if ! echo "$subxids" | grep -q "^$user:"; then
        local starts
        readarray -t starts < <(echo "$subxids" | cut -d: -f2)
        local lens
        readarray -t lens < <(echo "$subxids" | cut -d: -f3)
        if (( ${#starts[@]} == 1 )); then
            local newlen
            newlen="${lens[0]}"
            local newstart
            newstart=$(( starts[0] + newlen + 1 ))
        else
            declare -A ranges
            for i in $( seq 0 $(( ${#starts[@]} - 1 )) ); do
                ranges[${starts[$i]}]=${lens[$i]}
            done
            highest=$(printf '%s\n' "${starts[@]}" | sort -n | tail -1)
            highestlen="${ranges[$highest]}"
            newlen="$highestlen"
            newstart=$(( highest + highestlen + 1 ))
        fi
        echo "$user:$newstart:$newlen" >> "$subxidfile"
    fi
}

addentry "$subuidfile"
addentry "$subgidfile"
