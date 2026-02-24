#!/usr/bin/env bash

#################################################
function submit_config() {
    mpiexec=mpiexec
    if [[ "x${SLURMD_NODENAME}" == "xbeta" ]]; then
        mpi=24
        export OMP_NUM_THREADS=1
        spdyn=/home/wuyichao/Documents/software/genesis-2.1.6.1/bin/spdyn-mixed-intel-cuda12-beta
        source ~/Documents/software/genesis-2.1.6.1/setup-mixed-intel-cuda12.sh
    elif [[ "x${SLURMD_NODENAME}" == "xserine" ]]; then
        mpi=24
        export OMP_NUM_THREADS=1
        spdyn=/home/wuyichao/Documents/software/genesis-2.1.6.1/bin/spdyn-mixed-intel-cuda12-serine
        source ~/Documents/software/genesis-2.1.6.1/setup-mixed-intel-cuda12-serine.sh
    elif [[ "x${QUEUE}" == "all.q" ]]; then
        module purge
        module load intel/2024.0.2 intel-mpi/2021.11 cuda/12.3.2
        spdyn="/home/2/uj02562/data/software/genesis-2.1.4/bin/spdyn-intel-mixed-cuda12"
        export OMP_NUM_THREADS=1
        openmp=${OMP_NUM_THREADS}
        ncpu=${NSLOTS}
        ((mpi = ncpu / openmp))
    elif [[ ${HOSTNAME} == cell ]]; then
        export OMP_NUM_THREADS=1
        openmp=${OMP_NUM_THREADS}
        ncpu=$(nproc)
        ((mpi = ncpu / openmp))
        spdyn=/home/wuyichao/Documents/software/genesis-2.1.6.1/bin/spdyn-mixed-intel-cuda12
        source ~/Documents/software/genesis-2.1.6.1/setup-mixed-intel-cuda12.sh
    elif [[ ${PBS_O_HOST} == ccpbs* ]]; then
        openmp=${OMP_NUM_THREADS}
        ncpu=${NCPUS}
        ((mpi = ncpu / openmp))
        if [ ! -z "${PBS_O_WORKDIR}" ]; then
          cd ${PBS_O_WORKDIR}
        fi
        module -s purge
        module -s load genesis/2.1.4
        spdyn=spdyn
    elif [[ ${PJM_RSCGRP} == small ]]; then
        export PLE_MPI_STD_EMPTYFILE=off
        export OMP_NUM_THREADS=$((PJM_NODE * $(nproc) / PJM_MPI_PROC))
        # echo "OMP_NUM_THREADS=${OMP_NUM_THREADS}"
        # bindir=/vol0004/hp150272/data/u12262/genesis-2.1.2/bin
        # spdyn=$bindir/spdyn_fj_mixed
        mpi=${PJM_MPI_PROC:-16}
        source /vol0004/apps/oss/spack/share/spack/setup-env.sh
        spack load /46ohljh # genesis#2.1.6.1 mixed
        spdyn=spdyn
    else
        printenv
        export OMP_NUM_THREADS=1
        openmp=${OMP_NUM_THREADS}
        ncpu=${NSLOTS:-$(nproc)}
        ((mpi = ncpu / openmp))
        spdyn=/home/wuyichao/Documents/software/genesis-2.1.6.1/bin/spdyn-mixed-intel-cuda12
        source ~/Documents/software/genesis-2.1.6.1/setup-mixed-intel-cuda12.sh
    fi
    
    for key in "${!input[@]}"; do
        printf -v "$key" '%s' "${input[$key]}"
    done
}

function submit_main() {
    submit_config
    for((i=0; i<n_loop; i++))
    do
        ((runi = ini_runi + i))
        ((prev_runi = runi - 1))
        if [[ ${runi} -gt ${max_runi} ]]; then
            break
        fi
        origin_dir=$(pwd)
        target_dir="run${runi}"
        mkdir -p $target_dir
        cd $target_dir

        box_size=""
        restraints=""
        if [[ $runi -eq 0 ]]; then
            box_size=${initial_box_size}
            restraints=${initial_restraints}
        fi
        generate_inp
        run_program
        cd $origin_dir
    done
}

function generate_inp() {
    for inpname in "${inpname_list[@]}"
    do
        echo "Generate ${target_dir}/${inpname}"
        head=$(basename ${inpname} .inp)
        out_dcdfile=${head}${runi}.dcd
        out_rstfile=${head}${runi}.rst
        rstfile=""
        if [[ ${runi} -ne 0 ]]; then
            rstfile="rstfile = ../run${prev_runi}/${head}${prev_runi}.rst"
        fi
        
        eval "echo \"${template_list[idx]}\"" >${inpname}
    done
}

function run_program {
    backup
    for inpname in ${inpname_list[@]}
    do
        head=$(basename ${inpname} .inp)
        echo "Run ${target_dir}/${inpname}"
        if [[ "x$PJM_RSCGRP" == "xsmall" ]]; then
            ${mpiexec} -np $mpi -stdout-proc ${head}/out -stderr-proc ${head}/err $spdyn ${inpname}
        else
            mkdir -p "${head}"
            ${mpiexec} -np ${mpi} $spdyn ${inpname} >${head}/out.1.0
        fi
    done
}

function full_out() {
    grep 'total time' $1 >/dev/null
}

function full_rst() {
    size=$(stat -c%s $1)
    [[ $size -ne 0 ]] && return 0
    return 1
}

function full_dcd() {
    nframes=$(od -An -j 8 -N 4 -t d4 $1)
    ntitle=$(od -An -j 96 -N 4 -t d4 $1)
    ((nheader = 108 + ntitle * 80))
    natoms=$(od -An -j $nheader -N 4 -t d4 $1)
    ((desired_size = nheader + 8 + nframes * (56 + 24 + natoms * 12)))
    size=$(stat -c%s $1)
    [[ $size -eq $desired_size ]] && return 0
    return 1
}

function backup {
    last=$(ls -hvd * |grep 'backup\.' |awk -F. 'END{print $2}')
    last=${last:--1}
    ((last++))
    backup_name="backup.$last"
    for inpname in ${inpname_list[@]}
    do
        head=$(basename ${inpname} .inp)
        dcd=${head}${runi}.dcd
        rst=${head}${runi}.rst
        out=${head}
        [[ -e $dcd ]] && mkdir -p ${backup_name} && mv ${dcd} ${backup_name}
        [[ -e $rst ]] && mkdir -p ${backup_name} && mv ${rst} ${backup_name}
        [[ -d ${out} ]] && mkdir -p ${backup_name} && mv ${out} ${backup_name}
    done
}
#################################################

function is_run() {
    for job_name_i in "${job_name_list[@]}"
    do
        [[ ${job_name_i} == ${job_name} ]] && return 0
    done
    return 1
}

function get_job_name() {
    # save job_name in job_name_list
    job_name_list=()
    # depend on hpc
    # helix kinase
    if [[ $queue =~ (helix|kinase|gpu_.|node_.) ]]; then
        jobid_list=$(qstat | awk -v user=$(whoami) '$4==user {print $1}')
        for jobid in ${jobid_list}
        do
            _name=$(qstat -j $jobid | awk '/^job_name:/{print $2}')
            job_name_list+=($_name)
        done
    # beta serine
    elif [[ $queue =~ (beta|serine) ]]; then
        job_name_list=($(squeue -o '%j' | tail -n+2))
    fi
    echo "${job_name_list[@]}"
}

function find_ini_exist_runi() {
    ini_exist_runi=0
    run_dir="run${ini_exist_runi}"
    is_runned=false
    while [[ ${ini_exist_runi} -le ${max_runi} ]]
    do
        is_rst_exist=true
        for inpname in ${inpname_list[@]}
        do
            run_dir="run${ini_exist_runi}"
            head=$(basename ${inpname} .inp)
            rst=${run_dir}/${head}${ini_runi}.rst
            [[ -e ${rst} ]] && full_rst ${rst} || is_rst_exist=false
        done
        [[ ${is_rst_exist} == true ]] && { is_runned=true; break; }
        ((ini_exist_runi++))
    done
    if [[ ${is_runned} == false ]]; then
        ini_exist_runi=0
    fi
}

function find_ini_runi() {
    ini_runi=0
    for inpname in "${inpname_list[@]}"
    do
        run_dir="run${ini_runi}"
        head=$(basename ${inpname} .inp)
        rst=${run_dir}/${head}${ini_runi}.rst
        [[ ${ini_exist_runi} -eq 0 ]] && ! ([[ -e $rst ]] && full_rst ${rst}) && return
    done 
    ((ini_runi = ini_exist_runi + 1))
    while true
    do
        is_break=false
        for inpname in "${inpname_list[@]}"
        do
            head=$(basename ${inpname} .inp)
            run_dir="run${ini_runi}"
            dcd=${run_dir}/${head}${ini_runi}.dcd
            rst=${run_dir}/${head}${ini_runi}.rst
            out=${run_dir}/${head}/out.1.0
            [[ -d $run_dir ]] || { is_break=true; break; }
            [[ -e $dcd ]] || { is_break=true; break; }
            full_dcd ${dcd} || { is_break=true; break; }
            full_out ${out} || { is_break=true; break; }
            full_rst ${rst} || { is_break=true; break; }
        done
        [[ "${is_break}" == true ]] && break
        ((ini_runi++))
    done
}

function submit() {
    get_job_name
    for((repi=$repi_ini;repi<=$repi_end;repi++))
    do
        target_dir=${repi}
        origin_dir=$(pwd)
        job_name="${job_head}-${type}-${repi}"

        is_run && continue
        cd ${target_dir}
        find_ini_exist_runi
        find_ini_runi
        if [[ $ini_runi -gt ${input[max_runi]} ]]; then
            continue
        fi
        echo "${job_name}: ini_exist_runi=$ini_exist_runi, ini_runi=$ini_runi"
        echo "submit ($job_name)"
        generate_script
        log=log/stdout
        mkdir -p $(dirname ${log})
        [[ -n ${log} ]] && : > ${log}
        if [[ "x$1" == "xyes" ]]; then
            submit_repi
        fi
        cd ${origin_dir}
    done
}

function generate_script() {
    mkdir -p ${submit_dir}
    ((runi_ini=ini_runi))
    ((runi_end=runi_ini+input[n_loop]-1))
    script=$(eval "echo ${submit_dir}/${submit_name}")
    cat >${script} <<EOF
#!/bin/sh
#PBS -j oe
ini_runi=${ini_runi}
$(declare -p input)
$(declare -p inpname_list)
$(declare -p template_list)
$(declare -f submit_config)
$(declare -f submit_main)
$(declare -f generate_inp)
$(declare -f run_program)
$(declare -f backup)
submit_main
EOF
}

function submit_repi() {
    # helix kinase
    if [[ ${queue} =~ (helix|kinase) ]]; then
        cmd="qsub -cwd -pe mpi ${node} -q ${queue} -e ${log} -o ${log} -N ${job_name} ${script}"
        echo $cmd
        eval $cmd
    elif [[ ${queue} == cell ]]; then
        echo "qsub -cwd -pe mpi ${node} -q ${queue} -e ${log} -o ${log} -N ${job_name} ${script}"
        echo "sbatch -p ${queue} -o ${log} -e ${log} --cpus-per-task=${node} -J ${job_name} ${script}"
        bash ${script}
    elif [[ ${queue} =~ (beta|serine) ]]; then
        sbatch -p ${queue} -o ${log} -e ${log} --cpus-per-task=${node} -J ${job_name} ${script}
    elif [[ ${queue} =~ (gpu|node)_. ]]; then
        qsub -cwd -l "h_rt=24:00:00" -g $(groups | awk '{print $NF}') -l "${queue}=${node}" -o ${log} -j y -N ${job_name} ${script}
    elif [[ ${queue} == ims ]]; then
        ((mpi = node * mpi_per_node))
        cmd="jsub -l 'select=1:ncpus=${node}:mpiprocs=${mpi}:ompthreads=1' -l 'walltime=${time}' -N ${job_name} -v log=${log} ${script}"
        echo $cmd
        eval $cmd
    elif [[ ${queue} == small ]]; then
        cmd="pjsub -L 'rscgrp=${queue}' \
        -L 'rscunit=rscunit_ft01' \
        -L 'node=${node}' \
        --mpi 'max-proc-per-node=${mpi_per_node}' \
        -g $(groups | awk '{print $NF}') \
        -L 'elapse=00:05:00' \
        -x 'PJM_LLIO_GFSCACHE=/vol0004:/vol0005:/vol0003' \
        -N ${job_name} \
        -o ${log} \
        -e ${log} \
        ${script}"
        echo $cmd
        eval $cmd
    fi
}

function setup_directory() {
    mkdir -p $(seq $repi_ini $repi_end)
    for repi in $(seq $repi_ini $repi_end)
    do

        [[ -e ${repi}/data ]] || ln -snT ../../../data/${job_head}-${type} ${repi}/data
        [[ -e ${repi}/toppar ]] || ln -snT ../../../data/${job_head}-${type}/toppar ${repi}/toppar
    done
}

# main function
function main() {
    set_config
    submit $1
}

function set_submit_parameter() {
    name_list=(__file__ queue node mpi_per_node time)
    IFS='-' read -ra tokens <<< $(basename ${BASH_SOURCE[0]} .sh)
    for i in "${!name_list[@]}"
    do
        # depend on hpc
        if [[ "${name_list[i]}" == "queue" ]]; then
            # helix kinase
            if [[ ${tokens[i]} =~ (kinase|helix) ]]; then
                printf -v "${name_list[i]}" "all.q@${tokens[i]}.local"
            # beta serine cell
            else
                printf -v "${name_list[i]}" "${tokens[i]}"
            fi
        else
            printf -v "${name_list[i]}" "${tokens[i]}"
        fi
    done
}

# set_config function
function set_config() {
    set_submit_parameter

    inpname_list=(prod.inp)
    submit_dir="submit_script"
    submit_name='sub-${runi_ini}-${runi_end}.sh'

    job_head="homo"
    type=$(basename $PWD | awk -F'-' '{print $NF}')
    repi_ini=1
    repi_end=1
    declare -gA input
    input[n_loop]=2
    input[max_runi]=500
    input[psffile]=../data/step3_input.psf
    input[pdbfile]=../data/initial_equ.pdb
    input[reffile]=../data/initial_min.pdb
    input[nsteps]=600000
    input[crdout_period]=3000
    input[eneout_period]=${input["crdout_period"]}
    input[rstout_period]=${input["nsteps"]}
    box_length=($(grep "^CRYST1" ../../data/homo-${type}/initial_equ.pdb | awk '{print $2,$3,$4}'))
    input[initial_box_size]=$(cat <<EOF
box_size_x = ${box_length[0]}
box_size_y = ${box_length[1]}
box_size_z = ${box_length[2]}
EOF
)
    input[group]=$(grep '^group' ../../data/homo-${type}/step4.1_equilibration.inp)
    input[initial_restraints]=$(sed -n '/^\[RESTRAINTS\]/,$p' ../../data/homo-${type}/step4.1_equilibration.inp)

    setup_directory

    template_list=(
"$(cat <<'EOF'
[INPUT]
topfile = ../toppar/top_all36_prot.rtf, ../toppar/top_all36_na.rtf, ../toppar/top_all36_carb.rtf, ../toppar/top_all36_lipid.rtf, ../toppar/top_all36_cgenff.rtf, ../toppar/top_interface.rtf 
parfile = ../toppar/par_all36m_prot.prm, ../toppar/par_all36_na.prm, ../toppar/par_all36_carb.prm, ../toppar/par_all36_lipid.prm, ../toppar/par_all36_cgenff.prm, ../toppar/par_interface.prm 
strfile = ../toppar/toppar_all36_moreions.str, ../toppar/toppar_all36_nano_lig.str, ../toppar/toppar_all36_nano_lig_patch.str, ../toppar/toppar_all36_synthetic_polymer.str, ../toppar/toppar_all36_synthetic_polymer_patch.str, ../toppar/toppar_all36_polymer_solvent.str, ../toppar/toppar_water_ions.str, ../toppar/toppar_dum_noble_gases.str, ../toppar/toppar_ions_won.str, ../toppar/cam.str, ../toppar/toppar_all36_prot_arg0.str, ../toppar/toppar_all36_prot_c36m_d_aminoacids.str, ../toppar/toppar_all36_prot_fluoro_alkanes.str, ../toppar/toppar_all36_prot_heme.str, ../toppar/toppar_all36_prot_na_combined.str, ../toppar/toppar_all36_prot_retinol.str, ../toppar/toppar_all36_prot_model.str, ../toppar/toppar_all36_prot_modify_res.str, ../toppar/toppar_all36_na_nad_ppi.str, ../toppar/toppar_all36_na_rna_modified.str, ../toppar/toppar_all36_lipid_sphingo.str, ../toppar/toppar_all36_lipid_archaeal.str, ../toppar/toppar_all36_lipid_bacterial.str, ../toppar/toppar_all36_lipid_cardiolipin.str, ../toppar/toppar_all36_lipid_cholesterol.str, ../toppar/toppar_all36_lipid_dag.str, ../toppar/toppar_all36_lipid_inositol.str, ../toppar/toppar_all36_lipid_lnp.str, ../toppar/toppar_all36_lipid_lps.str, ../toppar/toppar_all36_lipid_mycobacterial.str, ../toppar/toppar_all36_lipid_miscellaneous.str, ../toppar/toppar_all36_lipid_model.str, ../toppar/toppar_all36_lipid_prot.str, ../toppar/toppar_all36_lipid_tag.str, ../toppar/toppar_all36_lipid_yeast.str, ../toppar/toppar_all36_lipid_hmmm.str, ../toppar/toppar_all36_lipid_detergent.str, ../toppar/toppar_all36_lipid_ether.str, ../toppar/toppar_all36_lipid_oxidized.str, ../toppar/toppar_all36_carb_glycolipid.str, ../toppar/toppar_all36_carb_glycopeptide.str, ../toppar/toppar_all36_carb_imlab.str, ../toppar/toppar_all36_label_spin.str, ../toppar/toppar_all36_label_fluorophore.str 

psffile     = ${psffile}
pdbfile     = ${pdbfile}
reffile     = ${reffile}
${rstfile}

[OUTPUT]
rstfile = ${out_rstfile}
dcdfile = ${out_dcdfile}

[ENERGY]
forcefield      = CHARMM        # [CHARMM]
electrostatic   = PME           # [CUTOFF,PME]
switchdist      = 10.0          # switch distance
cutoffdist      = 12.0          # cutoff distance
pairlistdist    = 13.5          # pair-list distance
vdw_force_switch = YES
pme_nspline     = 4

[DYNAMICS]
integrator      = VRES          # [VRES]
timestep        = 0.0035        # timestep (ps)
nsteps          = ${nsteps}
crdout_period   = ${crdout_period}
eneout_period   = ${eneout_period}
rstout_period   = ${rstout_period}
nbupdate_period = 6
elec_long_period = 2
thermostat_period = 6
barostat_period = 6
hydrogen_mr   = yes
hmr_ratio     = 3.0
hmr_ratio_xh1 = 2.0
hmr_target    = solute

[CONSTRAINTS]
rigid_bond      = YES           # constraints all bonds involving hydrogen
fast_water      = YES
shake_tolerance = 1.0D-10

[ENSEMBLE]
ensemble        = NPT           # [NVE,NVT,NPT]
tpcontrol       = BUSSI         # thermostat and barostat
temperature     = 303.15
pressure        = 1.0           # target pressure (atm)
group_tp        = YES
gamma_t         = 1.0           # thermostat friction (ps-1) in [LANGEVIN]
isotropy        = ISO

[BOUNDARY]
type            = PBC           # [PBC]
${box_size}

[SELECTION]
${group}

${restraints}
EOF
)"
    )
    [[ -f .env ]] && set -a && source .env && set +a
}

#################################################
# main
main "$@"
