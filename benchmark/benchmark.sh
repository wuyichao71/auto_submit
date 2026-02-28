#!/usr/bin/env bash

set -eu

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
        # get version
        version=$(extract 'version' $file)
        # get precision
        precision=$(extract 'precision' $file)
        # get gpu card number
        gpu=$(extract '# of GPUs' $file)
        # if gpu is empty, set to zero
        gpu=${gpu:-0}
        # get mpi number
        mpi=$(extract 'MPI proc' $file)
        # get openmp number
        omp=$(extract 'OpenMP' $file)
        # get cpu number (mpi * omp)
        cpu=$(extract "CPU cores" $file)
        node=0
        queue=""
        # if on tsubame, set queue dependent on gpu card type and gpu card number
        case "${HOSTNAME}" in
            login*)
                ;;
            cell)
                ;;
            fn*sv*)
                ;;
            *ims*)
                if [[ ${gpu} -eq 0 ]]; then
                    queue=ims_cpu
                else
                    queue=ims_gpu
                fi
                ;;
        esac
        if [[ "x$HOSTNAME" == "xlogin"* ]]; then
            gpu_model="$(grep 'gpu model' $file)"
            if [[ "x${gpu_model}" == "x"*"NVIDIA H100 MIG 3g.47gb (CC 9.0)"* ]]; then
                queue="node_o"
            elif [[ "x${gpu_model}" == "x"*"NVIDIA H100 (CC 9.0)"* ]]; then
                if [[ $gpu -eq 1 ]]; then
                    queue="node_q"
                elif [[ $gpu -eq 2 ]]; then
                    queue="node_h"
                elif [[ $gpu -eq 4 ]]; then
                    queue="node_f"
                fi
            else
                queue="cpu_${cpu}"
            fi
        elif [[ "x$HOSTNAME" == "xcell" ]]; then
            queue=$(extract 'exec. host' $file)
            if [[ "x${queue}" == "xu"* ]]; then
                continue
            fi
            queue=${queue#*@}
            queue=${queue%.*}
        elif [[ "x$HOSTNAME" == xfn*sv* ]]; then
            ((node = cpu / 48))
            host_info=$(extract 'exec. host' $file)
            if [[ "${host_info}" =~ u.*@.+ ]]; then
                queue=small
            elif [[ "${host_info}" == u*@ ]]; then
                queue=gpu1
            fi
        fi

        # get total time
        total_time=$(extract 'total time' $file)
        # if total time is empty, skip this part
        if [[ -n "${total_time}" ]]; then
            key="queue=${queue},version=${version},precision=${precision},node=${node},gpu=${gpu},cpu=${cpu},mpi=${mpi},omp=${omp}"
            time_sum[$key]=$(bc <<<"${time_sum[$key]:-0} + ${total_time}")
            count[$key]=${count[$key]:-0}
            ((count[$key] += 1))
        fi
    done
    for key in "${!time_sum[@]}"
    do
        # calculate the benchmark result
        time=$(bc <<<"scale=3; ${time_sum[$key]} / ${count[$key]}")
        hour=$(bc <<<"scale=1; ${time} / 3600")
        ns=$(bc <<<"scale=1; 0.0035 * 600000 * 24 * 3600 / ${time} / 1000")
        echo "${key},time_sum=${time_sum[$key]},count=${count[$key]},time=${time},hour=${hour},ns/day=${ns}"
    done | tee benchmark.csv

}

main "$@"
