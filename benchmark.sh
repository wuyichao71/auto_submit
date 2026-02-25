#!/usr/bin/env bash


function set_config() {
    repi_ini=1
    repi_end=20
}

function extract() {
    echo $(grep "$1" "$2" | awk -F= '{print $2}' | xargs)
}

function main() {
    declare -A time_sum
    declare -A time
    declare -A count
    for file in $(ls -hv */run*/prod/out.1.0)
    do
        if [[ "x$HOSTNAME" == xlogin* ]]; then
            gpu_model="$(grep 'gpu model' $file)"
            if [[ "x${gpu_model}" == "x"*"NVIDIA H100 (CC 9.0)"* ]]; then
                queue="node_q"
            elif [[ "x${gpu_model}" == "x"*"NVIDIA H100 MIG 3g.47gb (CC 9.0)"* ]]; then
                queue="node_o"
            fi
        fi
        gpu=$(extract '# of GPUs' $file)
        gpu=${gpu:-0}
        mpi=$(extract 'MPI proc' $file)
        omp=$(extract 'OpenMP' $file)
        cpu=$(extract "CPU cores" $file)
        total_time=$(extract 'total time' $file)
        if [[ -n "${total_time}" ]]; then
            key="queue=${queue},gpu=${gpu},cpu=${cpu},mpi=${mpi},omp=${omp}"
            time_sum[$key]=$(bc <<<"${time_sum[$key]:-0} + ${total_time}")
            ((count[$key] += 1))
        fi
    done
    for key in "${!time_sum[@]}"
    do
        time=$(bc <<<"scale=3; ${time_sum[$key]} / ${count[$key]}")
        hour=$(bc <<<"scale=1; ${time} / 3600")
        ns=$(bc <<<"scale=1; 0.0035 * 600000 * 24 * 3600 / ${time} / 1000")
        echo "${key},time_sum=${time_sum[$key]},count=${count[$key]},time=${time},hour=${hour},ns/day=${ns},"
    done

}

main "$@"
