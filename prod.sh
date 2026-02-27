#!/usr/bin/env bash

#################################################
function submit_config() {
    for key in "${!input[@]}"; do
        printf -v "$key" '%s' "${input[$key]}"
    done

    env

    mpiexec=mpiexec
    local=/home/wuyichao/Documents/software/genesis-2.1.6.1
    tsubame_local=/home/2/uj02562/data/software/genesis-2.1.6.1
    # beta and serine
    if [[ "x${SLURMD_NODENAME}" =~ x(beta|serine) ]]; then
        mpi=24
        export OMP_NUM_THREADS=1
        spdyn=${local}/bin/spdyn-mixed-intel-cuda12-${SLURMD_NODENAME}
        source ${local}/setup-mixed-intel-cuda12-${SLURMD_NODENAME}.sh
        return
    fi
    # tsubame
    ## node_* gpu_*
    if [[ ${queue} =~ (gpu|node)_. ]]; then
        ncpu=${NSLOTS}
        source ${tsubame_local}/setup-mixed-intel-cuda12-tsubame.sh
        spdyn="${tsubame_local}/bin/spdyn-mixed-intel-cuda12-tsubame"
        export OMP_NUM_THREADS=${omp}
        openmp=${OMP_NUM_THREADS}
        ((mpi = ncpu / openmp))
        return
    fi
    ## cpu_*
    if [[ ${queue} =~ cpu_[0-9]+ ]]; then
        ncpu=${NSLOTS}
        source ${tsubame_local}/setup-mixed-intel-tsubame.sh
        spdyn="${tsubame_local}/bin/spdyn-mixed-intel-tsubame"
        export OMP_NUM_THREADS=${omp}
        openmp=${OMP_NUM_THREADS}
        ((mpi = ncpu / openmp))
        return
    fi
    # kinase and helix
    if [[ "x${HOSTNAME}" == "x"*".local" ]]; then
        ncpu=${NSLOTS:-$(nproc)}
        export OMP_NUM_THREADS=1
        openmp=${OMP_NUM_THREADS}
        ((mpi = ncpu / openmp))
        spdyn=${local}/bin/spdyn-mixed-intel-cuda12
        source ${local}/setup-mixed-intel-cuda12.sh
        return
    fi
    #ims
    if [[ "${queue}" == ims ]]; then
        openmp=${OMP_NUM_THREADS}
        mpi=$(wc -l < "${PBS_NODEFILE}")
        if [ ! -z "${PBS_O_WORKDIR}" ]; then
          cd ${PBS_O_WORKDIR}
        fi
        source ~/software/genesis-2.1.6.1/setup-mixed-ims.sh
        spdyn=/lustre/home/users/fen/software/genesis-2.1.6.1/bin/spdyn-mixed-ims
        return
    fi
    # fugaku
    if [[ ${PJM_RSCGRP} == small ]]; then
        export PLE_MPI_STD_EMPTYFILE=off
        export OMP_NUM_THREADS=$((PJM_NODE * $(nproc) / PJM_MPI_PROC))
        mpi=${PJM_MPI_PROC:-16}
        source /vol0004/apps/oss/spack/share/spack/setup-env.sh
        spack load /46ohljh # genesis#2.1.6.1 mixed
        spdyn=spdyn
        return
    fi
}

function submit_main() {
    submit_config
    mpi_idx=0
    i=0
    ((runi=initial_runi))
    while [[ $i -lt $n_loop ]]
    do
        ((prev_runi = runi - 1))
        if [[ ${runi} -gt ${max_runi} ]]; then
            break
        fi
        origin_dir=$(pwd)
        target_dir="run${runi}"
        mkdir -p $target_dir
        cd $target_dir
        if ! submit_check_full; then
            box_size=""
            restraints=""
            if [[ $runi -eq 0 ]]; then
                box_size=${initial_box_size}
                restraints=${initial_restraints}
            fi
            generate_inp
            run_program
            ((i++))
        fi
        ((runi++))
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
            ((mpi_idx++))
            cmd="${mpiexec} -np $mpi -stdout-proc ${head}/out -stderr-proc ${head}/err $spdyn ${inpname}"
            echo "${cmd}"
            eval "${cmd}"
            rename_output
        else
            mkdir -p "${head}"
            cmd="${mpiexec} -np ${mpi} $spdyn ${inpname} >${head}/out.1.0"
            echo "${cmd}"
            eval "${cmd}"
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

function rename_output() {
    # recover output/out.1.0
    [[ -e ${head}/out.${mpi_idx}.0 ]] && ! [[ -e ${head}/out.1.0 ]] && mv ${head}/out.${mpi_idx}.0 ${head}/out.1.0
}

function submit_check_full() {
    for inpname in "${inpname_list[@]}"
    do
        head=$(basename ${inpname} .inp)
        dcd=${head}${runi}.dcd
        rst=${head}${runi}.rst
        out=${head}/out.1.0
        [[ -e "$dcd" ]] && full_dcd "$dcd" || return 1
        [[ -e "$rst" ]] && full_rst "$rst" || return 1
        [[ -e "$out" ]] && full_out "$out" || return 1
    done
    return 0
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
    # depend on hpc
    # helix kinase
    if [[ $queue =~ (helix|kinase|gpu_.|node_.|cpu_.*) ]]; then
        job_name_list=()
        job_id_list=($(qstat | awk -v user=$(whoami) '$4==user {print $1}'))
        for jobid in "${job_id_list[@]}"
        do
            _name=$(qstat -j $jobid | awk '/^job_name:/{print $2}')
            job_name_list+=($_name)
        done
    # beta serine
    elif [[ $queue =~ (beta|serine) ]]; then
        job_name_list=($(squeue -o '%j' | tail -n+2))
    # ims
    elif [[ $queue =~ ims ]]; then
        job_name_list=($(jobinfo -c |grep -v '^[-Q]' |awk '{print $3}'))
        job_id_list=($(jobinfo -c |grep -v '^[-Q]' |awk '{print $2}'))
    # fugaku
    elif [[ $queue =~ (small) ]]; then
        job_name_list=($(pjstat --data |grep '^,' |awk -F, '{print $3}'))
        job_id_list=($(pjstat --data |grep '^,' |awk -F, '{print $2}'))
    fi
    if [[ ${is_slient} == false ]]; then
        for idx in "${!job_name_list[@]}"
        do
            echo "${job_id_list[$idx]} --> ${job_name_list[$idx]}"
        done
    fi
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
            rst=${run_dir}/${head}${initial_runi}.rst
            [[ -e ${rst} ]] && full_rst ${rst} || is_rst_exist=false
        done
        [[ ${is_rst_exist} == true ]] && { is_runned=true; break; }
        ((ini_exist_runi++))
    done
    if [[ ${is_runned} == false ]]; then
        ini_exist_runi=0
    fi
}

function check_full() {
    for inpname in "${inpname_list[@]}"
    do
        head=$(basename ${inpname} .inp)
        run_dir="run${initial_runi}"
        dcd=${run_dir}/${head}${initial_runi}.dcd
        rst=${run_dir}/${head}${initial_runi}.rst
        out=${run_dir}/${head}/out.1.0
        [[ -d $run_dir ]] || return 1
        [[ -e "$dcd" ]] && full_dcd "$dcd" || return 1
        [[ -e "$rst" ]] && full_rst "$rst" || return 1
        [[ -e "$out" ]] && full_out "$out" || return 1
    done
    return 0
}

function find_initial_runi() {
    initial_runi=0
    for inpname in "${inpname_list[@]}"
    do
        run_dir="run${initial_runi}"
        head=$(basename ${inpname} .inp)
        rst=${run_dir}/${head}${initial_runi}.rst
        [[ ${ini_exist_runi} -eq 0 ]] && ! ([[ -e $rst ]] && full_rst ${rst}) && return
    done 
    ((initial_runi = ini_exist_runi + 1))
    while true
    do
        check_full || break
        ((initial_runi++))
    done
}

function is_normal_mode() {
    # check whether the job is in normal mode
    if [[ "$queue" == small ]]; then
        local mode=$(pjstat --data --filter "jnam=$1" | grep '^,' | awk -F, '{print $4}')
        [[ "x$mode" == "xNM" ]] && return 0
    fi
    return 1
}

function submit() {
    for((repi=$repi_ini;repi<=$repi_end;repi++))
    do
        target_dir=${repi}
        origin_dir=$(pwd)
        job_name="${job_head}-${type}-${repi}"

        if [[ $is_step == false ]]; then
            is_run && continue
        elif is_normal_mode "${job_name}"; then
            echo "The job is not step mode!"
            continue
        fi

        cd ${target_dir}
        find_ini_exist_runi
        find_initial_runi
        if [[ $initial_runi -gt ${input[max_runi]} ]]; then
            continue
        fi
        echo "${job_name}: ini_exist_runi=$ini_exist_runi, initial_runi=$initial_runi"
        echo "submit ($job_name)"
        generate_script
        submit_repi
        cd ${origin_dir}
    done
}

function generate_script() {
    mkdir -p ${submit_dir}
    ((runi_ini=initial_runi))
    ((runi_end=runi_ini+input[n_loop]-1))
    script=$(eval "echo ${submit_dir}/${submit_name}")
    cat >${script} <<EOF
#!/usr/bin/env bash
#PBS -j oe
echo "queue=\${queue}"
echo "omp=\${omp}"
echo "initial_runi=\${initial_runi}"
initial_runi=${initial_runi}
$(declare -p input)
$(declare -p inpname_list)
$(declare -p template_list)
$(declare -f submit_config)
$(declare -f submit_main)
$(declare -f generate_inp)
$(declare -f run_program)
$(declare -f backup)
$(declare -f rename_output)
$(declare -f full_dcd)
$(declare -f full_out)
$(declare -f full_rst)
$(declare -f submit_check_full)
submit_main
EOF
}

function find_jid() {
    local jidx
    for jidx in "${!job_name_list[@]}"
    do
        [[ "$1" == "${job_name_list[$jidx]}" ]] && echo "${job_id_list[$jidx]}"
    done | sort -n | tail -n1
}

function submit_repi() {
    log=log/stdout
    step_para=""
    # helix kinase
    if [[ ${queue} =~ (helix|kinase) ]]; then
        cmd="qsub \
            -cwd \
            -pe mpi ${node} \
            -q ${queue} \
            -e ${log} \
            -o ${log} \
            -N ${job_name} \
            -v 'initial_runi=${initial_runi},omp=${omp}' \
            ${script}"
        echo $cmd
    elif [[ ${queue} == cell ]]; then
        cmd="echo 'hello, world'"
    # beta serine
    elif [[ ${queue} =~ (beta|serine) ]]; then
        cmd="sbatch -p ${queue} -o ${log} -e ${log} --cpus-per-task=${node} -J ${job_name} ${script}"
        echo $cmd
    # tsubame
    elif [[ ${queue} =~ (gpu_.|node.|cpu_.*) ]]; then
        if [[ $is_step == true ]]; then
            step_para="-hold_jid ${job_name}"
        fi
        cmd="qsub -cwd \
            ${step_para} \
            -l 'h_rt=${time}' \
            -g $(groups | awk '{print $NF}') \
            -l '${queue}=${node}' \
            -o ${log} \
            -j y \
            -N ${job_name} \
            -v 'initial_runi=${initial_runi},queue=${queue},omp=${omp}' \
            ${script}"
        echo $cmd
    elif [[ ${queue} == ims ]]; then
        if [[ $is_step == true ]]; then
            local jid=$(find_jid ${job_name})
            if [[ -n ${jid} ]]; then
                step_para="-W depend=afterany:${jid}"
            fi
        fi
        ((mpi = node / omp))
        cmd="jsub -l 'select=1:ncpus=${node}:mpiprocs=${mpi}:ompthreads=${omp}' \
            ${step_para} \
            -N ${job_name} \
            -l 'walltime=${time}' \
            -v "log=${log},initial_runi=${initial_runi},queue=${queue}" \
            ${script}"
        echo $cmd
    elif [[ ${queue} == small ]]; then
        if [[ $is_step == true ]]; then
            step_para="--step --sparam 'jnam=${job_name}'"
        fi
        ((mpi_per_node = 48 / omp))
        cmd="pjsub -L 'rscgrp=${queue}' \
            ${step_para} \
            -L 'rscunit=rscunit_ft01' \
            -L 'node=${node}' \
            --mpi 'max-proc-per-node=${mpi_per_node}' \
            -g $(groups | awk '{print $NF}') \
            -L 'elapse=${time}' \
            -x 'PJM_LLIO_GFSCACHE=/vol0004:/vol0005:/vol0003' \
            -N ${job_name} \
            -x 'initial_runi=${initial_runi}' \
            -o ${log} \
            -e ${log} \
            ${script}"
        echo $cmd
    fi
    if [[ $is_submit == true ]]; then
        mkdir -p $(dirname ${log})
        [[ -n ${log} ]] && : > ${log}
        eval "$cmd"
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
    set_config "$@"
    get_job_name
    submit $is_submit $is_step
}

function set_submit_parameter() {
    name_list=(__file__ queue node omp time)
    IFS='-' read -ra tokens <<< $(basename ${BASH_SOURCE[0]} .sh)
    for i in "${!tokens[@]}"
    do
        printf -v "${name_list[i]}" "${tokens[i]}"
    done
}

function update_queue() {
    # depend on hpc
    # helix kinase
    if [[ "${queue}" =~ (kinase|helix) ]]; then
        queue="all.q@${queue}.local"
    fi
}
usage() {
  cat <<EOF
Usage:
  $(basename "$0") [OPTIONS] [repi_ini [repi_end]]

Description:
  Options and positional arguments may be interleaved.
  Use '--' to explicitly terminate option parsing.

Positional arguments:
  repi_ini          Starting replica index
  repi_end          Ending replica index (optional)

Options:
  -y, --submit      Enable submit mode
  -s, --step        Enable step mode
  -q, --queue       Queue name
  -n, --node        Node number (default: 1)
  -o, --omp         OpenMP number (default: 1)
  -t, --time        Elapse limit time (default: 24:00:00)
  -l, --n_loop N    Number of loops (default: 1)
  --slient          Slient mode
  -h, --help        Show this help message and exit

Behavior:
  No positional arguments:
      Process all replicas.
  One positional argument:
      Process only that replica.
  Two positional arguments:
      Process replicas in range [repi_ini, repi_end].

Examples:
  $(basename "$0") 1 3 --submit
  $(basename "$0") --step -n 7 3
  $(basename "$0") --step --n_loop 7 --queue small --omp 3 --node 24 3 6
  $(basename "$0") -y -s -- 1 3
  $(basename "$0") --help
EOF
}

# set_config function
function set_config() {
    inpname_list=(prod.inp)
    submit_dir="submit_script"
    submit_name='sub-${runi_ini}-${runi_end}.sh'
    omp=1
    node=1
    time=24:00:00

    job_head="homo"
    type=$(basename $PWD | awk -F'-' '{print $NF}')
    repi_ini=1
    repi_end=20
    declare -gA input
    input[n_loop]=1
    input[max_runi]=250
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

    set_submit_parameter
    [[ -f para ]] && set -a && source para && set +a
    [[ -f para.${queue} ]] && set -a && source para.${queue} && set +a
    is_submit=false
    is_step=false
    is_slient=false
    positional=()
    while [[ $# -gt 0 ]]
    do
        case "$1" in
            -y|--submit) is_submit=true; shift ;;
            -s|--step) is_step=true; shift ;;
            -l|--n_loop)
                [[ $# -ge 2 ]] || { echo "Error: --n_loop needs a value"; exit 1; }
                input[n_loop]="$2"
                shift 2
                ;;
            -q|--queue)
                queue=$2
                shift 2
                ;;
            -n|--node)
                node=$2
                shift 2
                ;;
            -o|--omp)
                omp=$2
                shift 2
                ;;
            -t|--time)
                time=$2
                shift 2
                ;;
            --slient)
                is_slient=true
                shift
                ;;
            -h|--help)
                usage; exit 0 ;;
            --)
                shift; positional+=("$@"); break ;;
            -*)
                echo "Unknown option: $1"; usage; exit 1 ;;
            *)
                positional+=("$1"); shift ;;
        esac
    done
    [[ ${#positional[@]} -gt 2 ]] && { usage; exit 1; }
    if [[ -n ${positional[0]} ]]; then
        if [[ "${positional[0]}" =~ [0-9]+ ]]; then
            repi_ini=${positional[0]}
            repi_end=${positional[0]}
        else
            usage; exit 1;
        fi
    fi
    if [[ -n ${positional[1]} ]]; then
        if [[ "${positional[1]}" =~ [0-9]+ ]]; then
            repi_end=${positional[1]}
        else
            usage; exit 1;
        fi
    fi

    update_queue
    if [[ ${is_slient} == false ]]; then
        echo "repi_ini=${repi_ini}, repi_end=${repi_end}, input[n_loop]=${input[n_loop]}, queue=${queue}, node=${node}, omp=${omp}, time=${time}, is_submit=${is_submit}, is_step=${is_step}"
    fi
    setup_directory
}

#################################################
# main
main "$@"
