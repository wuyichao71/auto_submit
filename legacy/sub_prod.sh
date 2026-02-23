#!/usr/bin/env bash
function set_config() {
    QUEUE="node_o"
    TIME="24:00:00"
    GROUP=$(groups |awk '{print $NF}')
    SPDYN="/home/2/uj02562/data/software/genesis-2.1.4/bin/spdyn-intel-mixed-cuda12"
    OMP=1
    DEFAULT_CPU=24
    n_loop=7
    max_runi=500
    nsteps=600000
    crdout_period=3000
}

function get_job_name() {
    # save job_name in job_name_list
    job_name_list=()
    jobid_list=$(qstat | awk -v user=$(whoami) '$4==user {print $1}')
    for jobid in ${jobid_list}
    do
        _name=$(qstat -j $jobid | awk '/^job_name:/{print $2}')
        job_name_list+=($_name)
    done
}

function is_run() {
    for job_name in "${job_name_list[@]}"
    do
        [[ ${job_name} == ${JOB_NAME} ]] && return 0
    done
    return 1
}

function find_ini_exist_runi() {
    ini_exist_runi=0
    while true
    do
        run_dir="run${ini_exist_runi}" 
        [[ -d $run_dir ]] && break
        ((ini_exist_runi++))
    done
}

function find_ini_runi() {
    ((ini_runi = ini_exist_runi + 1))
    while true
    do
        run_dir="run${ini_runi}" 
        dcd=${run_dir}/prod${ini_runi}.dcd
        rst=${run_dir}/prod${ini_runi}.rst
        output=${run_dir}/output/out.1.0
        [[ -d $run_dir ]] || break
        [[ -e $dcd ]] || break
        full_dcd || break
        full_output || break
        full_rst || break
        ((ini_runi++))
    done
}

function full_output() {
    grep 'total time' $output >/dev/null
}

function full_rst() {
    size=$(stat -c%s $rst)
    [[ $size -ne 0 ]] && return 0
    return 1
}

function full_dcd() {
    nframes=$(od -An -j 8 -N 4 -t d4 $dcd)
    ntitle=$(od -An -j 96 -N 4 -t d4 $dcd)
    ((nheader = 108 + ntitle * 80))
    natoms=$(od -An -j $nheader -N 4 -t d4 $dcd)
    ((desired_size = nheader + 8 + nframes * (56 + 24 + natoms * 12)))
    size=$(stat -c%s $dcd)
    [[ $size -eq $desired_size ]] && return 0
    return 1
}

function main() {
    get_job_name
    for ((traji=1; traji<=3; traji++))
    do
        target_dir=${traji}
        origin_dir=$(pwd)
        JOB_NAME="prod${traji}"

        is_run && continue

        cd $target_dir
        find_ini_exist_runi
        find_ini_runi
        if [[ $ini_runi -gt $max_runi ]]; then
            continue
        fi
        echo "$traji: $ini_exist_runi $ini_runi"
        echo "submit ($JOB_NAME)"
        if [[ "x$is_submit" == "xyes" ]]; then
            submit
        fi
        cd $origin_dir
    done
}

function submit() {
set_group=""
[[ -n $GROUP ]] && set_group="-g $GROUP"
qsub \
    $set_group \
    -cwd \
    -j y \
    -l "${QUEUE}=1" \
    -l "h_rt=${TIME}" \
    -N "${JOB_NAME}" \
    -o 'stdout.$JOB_NAME' <<EOF
#!/bin/sh

module purge
module load intel/2024.0.2 intel-mpi/2021.11 cuda/12.3.2

spdyn=${SPDYN}
export OMP_NUM_THREADS=${OMP}
openmp=\${OMP_NUM_THREADS:-1}
ncpu=\${NSLOTS:-${DEFAULT_CPU}}
((mpi = ncpu / openmp))

ini_runi=${ini_runi}
max_runi=${max_runi}
nsteps=${nsteps}
crdout_period=${crdout_period}
n_loop=${n_loop}
$(declare -f submit_main)
$(declare -f backup)
$(declare -f backup_output)
$(declare -f run_program)
$(declare -f generate_input)

submit_main
EOF
}

function submit_main() {
    [[ -n ${SGE_STDOUT_PATH} ]] && : > ${SGE_STDOUT_PATH}
    # find_ini_exist_runi
    # find_ini_runi
    echo $ini_runi
    for((i=0; i<n_loop; i++))
    do
        ((runi = ini_runi + i))
        if [[ $runi -gt $max_runi ]]; then
            break
        fi
        origin_dir=$(pwd)
        target_dir="run${runi}"
        mkdir -p $target_dir
        cd $target_dir
        echo "Generate ${target_dir}/prod.inp"
        generate_input
        echo "Run ${target_dir}"
        run_program
        cd $origin_dir
    done
}



function backup {
    if [[ -e prod${runi}.dcd ]] || [[ -e prod${runi}.rst ]]; then
        last=$(ls -hvd * |grep 'backup\.' |awk -F. 'END{print $2}')
        last=${last:--1}
        ((last++))
        backup_name="backup.$last"
        mkdir -p ${backup_name}
        mv *.dcd *.rst output ${backup_name}
    fi
}

function backup_output {
    if [[ -d output ]]; then
        last=$(ls -hvd * |grep 'output\.' |awk -F. 'END{print $2}')
        last=${last:--1}
        ((last++))
        mv output output.$last
    fi
}

function run_program {
    backup
    backup_output
    mkdir output
    mpiexec -np ${mpi} $spdyn prod.inp >output/out.1.0
}


function generate_input {
((prev_runi = runi - 1))
cat <<EOF >prod.inp
[INPUT]
prmtopfile  = ../../../1_setup/protein_solv_run.prmtop
ambcrdfile  = ../../../1_setup/protein_solv_run.inpcrd
ambreffile  = ../../../1_setup/protein_solv_run.inpcrd
rstfile     = ../run${prev_runi}/prod${prev_runi}.rst

[OUTPUT]
dcdfile = prod${runi}.dcd
rstfile = prod${runi}.rst

[ENERGY]
forcefield          = AMBER
electrostatic       = PME
switchdist          = 8.0
cutoffdist          = 8.0
pairlistdist        = 10.0
dispersion_corr     = EPRESS
contact_check       = YES
nonb_limiter        = NO

[DYNAMICS]
integrator          = VRES
timestep            = 0.0035
stoptr_period       = 10
nbupdate_period     = 6
elec_long_period    = 2
thermostat_period   = 6
barostat_period     = 6
hydrogen_mr         = YES
hmr_target          = solute
hmr_ratio           = 3.0
hmr_ratio_xh1       = 2.0
eneout_period       = ${crdout_period}
crdout_period       = ${crdout_period}
nsteps              = ${nsteps}
rstout_period       = ${nsteps}

[CONSTRAINTS]
rigid_bond          = YES
water_model         = WAT

[ENSEMBLE]
tpcontrol           = BUSSI
ensemble            = NPT
temperature         = 310
pressure            = 1.0
group_tp            = YES
gamma_t             = 1.0

[BOUNDARY]
type                = PBC

[SELECTION]
group1              = backbone
EOF
}

is_submit=$1
set_config
main
