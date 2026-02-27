#!/usr/bin/env bash

set -euo pipefail

function set_config() {
    CONF="targets.conf"
    SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2)
    declare -gA NEXT MODE TARGET INTERVAL WORKDIR CMD
}

function now_epoch () { date +%s; }

function parse_interval_to_seconds() {
  local s="$1"

  # 纯数字：按秒
  if [[ "$s" =~ ^[0-9]+$ ]]; then
    echo "$s"
    return 0
  fi

  # 允许组合：例如 1h30m、2d4h、10m5s
  # 格式必须是 (数字+单位) 的重复，单位：s m h d
  if [[ ! "$s" =~ ^([0-9]+[smhd])+$ ]]; then
    echo "[ERROR] invalid interval: '$s' (use e.g. 30s, 10m, 4h, 2d, 1h30m)" >&2
    return 1
  fi

  local total=0 num unit rest="$s"
  while [[ -n "$rest" ]]; do
    [[ "$rest" =~ ^([0-9]+)([smhd])(.*)$ ]] || break
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    rest="${BASH_REMATCH[3]}"

    case "$unit" in
      s) total=$(( total + num )) ;;
      m) total=$(( total + num * 60 )) ;;
      h) total=$(( total + num * 3600 )) ;;
      d) total=$(( total + num * 86400 )) ;;
    esac
  done

  echo "$total"
}

function load_targets() {
    declare -A NEW_MODE NEW_TARGET NEW_INTERVAL NEW_WORKDIR NEW_CMD

    mapfile lines < "${CONF}"
    for line in "${lines[@]}"
    do
        IFS='|' read -r name mode target interval_str workdir cmd <<<"$line"

        # skip the header
        if [[ "$name" == "name" ]]; then
            continue
        fi
        interval="$(parse_interval_to_seconds "$interval_str")"

        [[ -z "${name:-}" || "${name:0:1}" == "#" ]] && continue

        NEW_MODE["$name"]="$mode"
        NEW_TARGET["$name"]="$target"
        NEW_INTERVAL["$name"]="$interval"
        NEW_WORKDIR["$name"]="$workdir"
        NEW_CMD["$name"]="$cmd"

        # now task, initialize NEXT
        if [[ -z "${NEXT[$name]+x}" ]]; then
            NEXT["$name"]="$(now_epoch)"
        fi
    done

    # remove removal task
    for name in "${!MODE[@]}"
    do
        if [[ -z "${NEW_MODE[$name]+x}" ]]; then
            unset MODE["$name"] TARGET["$name"] INTERVAL["$name"] WORKDIR["$name"] CMD["$name"] NEXT["$name"]
            echo "Removed monitor: $name"
        fi
    done

    for name in "${!NEW_MODE[@]}"
    do
        MODE[$name]="${NEW_MODE[$name]}"
        TARGET[$name]="${NEW_TARGET[$name]}"
        INTERVAL[$name]="${NEW_INTERVAL[$name]}"
        WORKDIR[$name]="${NEW_WORKDIR[$name]}"
        CMD[$name]="${NEW_CMD[$name]}"
    done
}


function run_item() {
    local name="$1"
    local mode="${MODE[$name]}"
    local target="${TARGET[$name]}"
    local workdir="${WORKDIR[$name]}"
    local cmd="${CMD[$name]}"

    echo "===== $(date '+%F %T') | $name ====="

    if [[ "$mode" == "local" ]]; then
        bash -lc "cd ${workdir} && $cmd" || echo "[ERROR] local cmd failed ($?)"
    elif [[ "$mode" == "ssh" ]]; then
        ssh "${SSH_OPTS[@]}" "$target" "cd ${workdir} && ${cmd}" || echo "[ERROR] ssh failed ($?)"
    else
        echo "[ERROR] unknown mode: $mode"
    fi
}

function main () {
    set_config

    while true
    do
        load_targets

        now="$(now_epoch)"

        for name in "${!MODE[@]}"
        do
            if (( now >= NEXT[$name] )); then
                run_item "$name"
                NEXT["$name"]=$(( now + INTERVAL[$name]  ))
            fi
        done
        break

        sleep 5
    done
}

main

# abltide_tsubame_dir="/home/2/uj02562/data/abltide/production/highfold2_cyclic/cyclic-2/3_prod"
# igf1r_tsubame_dir="/home/2/uj02562/data/igf1r/prod/cmd-homo-dm"
# while true
# do
#     ssh -X tsubame "cd ${abltide_tsubame_dir} && source /etc/profile.d/zT4.sh && bash sub_prod.sh yes"
#     ssh -X tsubame "cd ${igf1r_tsubame_dir} && source /etc/profile.d/zT4.sh && bash prod.sh --slient 8 20 -q node_o -t 19:00:00 -l 2 -y"
#     sleep 4h
# done