#!/usr/bin/env bash

function set_config() {
    GROUP="hp250059"
    QUEUE=small
    EQ_NODE=1
    FEP_NODE=21
    PER_NODE=16
    GENESIS_BIN="/vol0003/mdt0/data/hp250059/u12262/software/genesis-2.1.4/bin"
    run_ini=1
    run_end=10
}

function main() {
    # complex
    struct=complex
    eq_time="03:30:00"
    fepeq_time="03:00:00"
    prod_time="60:00:00"
    submit_job

    # ligand
    struct=ligand
    eq_time="01:15:00"
    fepeq_time="01:10:00"
    prod_time="18:00:00"
    submit_job
}

function eq_loop() {
    echo 2_equil/{1_min1,2_min2,3_heat,4_eq1,5_eq2}
}

function eq_setup() {
    inphead=$(echo $(basename $dir) | awk -F'_' '{print $2}')
}

function fepeq_loop() {
    echo 3_fep_equil
}

function fepeq_setup() {
    inphead="fep_eq"
}

function prod_loop() {
    seq $run_ini $run_end
}

function prod_setup() {
    dir=4_prod/run${runi}
    mkdir -p $dir
    generate_input
    inphead="prod"
}

function submit_script() {
    tee $3 <<EOF | "${CMD[@]}"
#!/usr/bin/env bash
bindir=${GENESIS_BIN}
run_ini=${run_ini}
run_end=${run_end}
$(declare -f submit_set_config)
$(declare -f backup_output)
$(declare -f recover_output)
$(declare -f run_program)
$(declare -f generate_input)
$(declare -f $1)
$(declare -f $2)

submit_set_config
for dir in \$($1)
do
    $2
    run_program
done
EOF
}

function submit_set_config() {
    export PLE_MPI_STD_EMPTYFILE=off
    spdyn=$bindir/spdyn_fj_mixed
    mpi=${PJM_MPI_PROC:-336}
    ((openmp = 48 / PJM_PROC_BY_NODE))
    export OMP_NUM_THREADS=${openmp:-3}
}

function is_full() {
    rst=2_equil/5_eq2/eq2.rst
    [[ -e $1 ]] || return 1
    size=$(stat -c%s $1)
    [[ $size -ne 0 ]] || return 1
    return 0
}

function get_jobid() {
    jobid=$(echo $jobid_str | awk '{print $6}' | awk -F '_' '{print $1}')
    jobid=${jobid%%_*}
}

function set_cmdtmp() {
    CMDTMP=("${DEFAULT_CMD[@]}" -L "node=${node}" -L "elapse=${time}" -N $name)
}

function submit_job() {
    cd ${fepdir}/${struct}

    # check runned state
    runned_eq=no
    is_full 2_equil/5_eq2/eq2.rst && runned_eq=yes
    runned_fepeq=no
    is_full 3_fep_equil/fep_eq1.rst && runned_fepeq=yes
    runned_prod=no
    is_full 4_prod/run10/prod10_rep1.rst && runned_prod=yes

    DEFAULT_CMD=(pjsub --step -g ${GROUP} -L "rscgrp=${QUEUE}" -L "rscunit=rscunit_ft01" --mpi "max-proc-per-node=${PER_NODE}" 
    -x "PJM_LLIO_GFSCACHE=/vol0003:/vol0004:/vol0005" -j -o stdout -e stderr)

    CMD=(cat)
    final_eval='echo ${CMDTMP[@]}'
    if [[ "x$is_submit" == "xyes" ]]; then
        final_eval='CMD=(${CMDTMP[@]})'
    fi
    # eq
    node=${EQ_NODE} && time=${eq_time} && name="${fepdir}-${struct}-eq" && set_cmdtmp
    eval $final_eval
    [[ "x${runned_eq}" == "xno" ]] && jobid_str=$(submit_script eq_loop eq_setup eq.sh) && echo "$jobid_str" && get_jobid
    # fepeq
    node=${FEP_NODE} && time=${fepeq_time} && name="${fepdir}-${struct}-fepeq" && set_cmdtmp
    [[ "x${runned_eq}" == "xno" ]] && CMDTMP+=(--sparam "jid=${jobid}") && eval $final_eval
    [[ "x${runned_fepeq}" == "xno" ]] && jobid_str=$(submit_script fepeq_loop fepeq_setup fepeq.sh) && echo "$jobid_str" && get_jobid
    # prod
    node=${FEP_NODE} && time=${prod_time} && name="${fepdir}-${struct}-prod" && set_cmdtmp
    [[ "x${runned_eq}" == "xno" ]] || [[ "x${runned_fepeq}" == "xno" ]] && CMDTMP+=(--sparam "jid=${jobid}") && eval $final_eval
    [[ "x${runned_prod}" == "xno" ]] && jobid_str=$(submit_script prod_loop prod_setup prod.sh) && echo "$jobid_str" && get_jobid
    cd $oldDir
}

function backup_output () {
    if [[ -d output ]]; then
        last=$(ls -hvd * |grep 'output\.' |awk -F. 'END{print $2}')
        last=${last:--1}
        ((last++))
        mv output output.$last
    fi
}

function recover_output() {
    # recover output/out.1.0
    if compgen -G "output/out.*.0" > /dev/null; then
        if ! [[ -e output/out.1.0 ]]; then
            mv output/out.*.0 output/out.1.0
        fi
    fi
}

function run_program() {
    echo "==========${dir}============="
    oldDir=$PWD
    echo cd $dir
    cd $dir
    backup_output
    echo $dir : "mpi = $mpi"
    echo $dir : "openmp = $OMP_NUM_THREADS"
    mpiexec -np $mpi -stdout-proc output/out -stderr-proc output/err $spdyn ${inphead}.inp
    exitcode=$?
    recover_output
    echo "exitcode = $exitcode"
    echo $oldDir
    echo "==========${dir}============="
    cd $oldDir
}

function generate_input() {
    runi=${dir#*/run}
    ((prev_i=runi-1))
    workdir=$(dirname $dir)
    awk "/xxx/{gsub(\"xxx\", $prev_i)} /yyy/{gsub(\"yyy\", $runi)} {print}" ${workdir}/template/prod.inp > ${dir}/prod.inp
}

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 jobdir"
    exit 1
fi

fepdir=$1
is_submit=$2
oldDir=$PWD
set_config
main


