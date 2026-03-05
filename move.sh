#!/usr/bin/env bash

function full_dcd() {
    size=$(stat -c%s $1)
    [[ $size -eq 0 ]] && return 1
    nframes=$(od -An -j 8 -N 4 -t d4 $1)
    ntitle=$(od -An -j 96 -N 4 -t d4 $1)
    ((nheader = 108 + ntitle * 80))
    natoms=$(od -An -j $nheader -N 4 -t d4 $1)
    ((desired_size = nheader + 8 + nframes * (56 + 24 + natoms * 12)))
    size=$(stat -c%s $1)
    [[ $size -eq $desired_size ]] && return 0
    return 1
}

function move() {
    for repi in $(seq "${repi_ini}" "${repi_end}")
    do
        runi=0
        while (( max_runi < 0 || runi <= max_runi ))
        do
            dcd="${repi}/run${runi}/${head}${runi}.dcd"
            conv_dcd="${repi}/run${runi}/${conv_dir}/${conv_head}${runi}.dcd"
            if [[ -e "$conv_dcd" ]] && full_dcd "${conv_dcd}"; then
                if [[ -e "${dcd}" ]]; then
                    full_path="$(pwd)/${dcd}"
                    trash_path=${full_path/data3/trash2}
                    mkdir -p "$(dirname ${trash_path})"
                    mv ${full_path} ${trash_path}
                fi    
            else
                break
            fi
            (( runi++ ))
        done
        
    done
}

function main() {
    set_config "$@"
    move
} 

function set_config() {
    repi_ini=1
    repi_end=20
    head=prod
    conv_dir=conv
    conv_head=conv

    max_runi=-1
}


main "$@"