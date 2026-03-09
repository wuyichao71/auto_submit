#!/usr/bin/env bash

function run() {
    job_i=0
    for repi in $(seq ${repi_ini} ${repi_end})
    do
        runi=0
        while (( max_runi < 0 || runi <= max_runi))
        do
            local trjname="${repi}/run${runi}/${inp_head}${runi}.dcd"
            if [[ -e ${trjname} ]]; then
                full_dcd ${trjname} || break
            fi
            conv "${trjname}"
            ((runi++))
        done
    done
}

function generate_inp() {
    eval "echo \"${template_list[idx]}\"" >${inpname}
}

function conv() {
    local olddir=$(pwd)
    local workdir="$(dirname $1)/${dir}"
    realpath="$(realpath $1)"
    mkdir -p "${workdir}"
    cd "${workdir}"
    trjfile1="$(realpath --relative-to=. ${realpath})"
    for idx in "${!inpname_list[@]}"
    do
        inpname="${inpname_list[$idx]}"
        out_head=$(basename "${inpname}" .inp)
        out_trjfile="${out_head}${runi}.dcd"
        out_pdbfile=""
        out_pdbfile_line=""
        if (( runi == 0 )); then
            out_pdbfile="${out_trjfile%%.dcd}.pdb"
            out_pdbfile_line="pdbfile        = ${out_pdbfile}"
        fi
        # echo "out_trjfile=${out_trjfile}, out_pdbfile=${out_pdbfile}" 
        if [[ -e "${out_trjfile}" ]]; then
            if full_dcd "${out_trjfile}"; then
                cd "${olddir}"
                return
            else
                backup "${out_trjfile}" "${out_pdbfile}"
            fi
        fi
        if [[ -n "${out_pdbfile}" && -e "${out_pdbfile}" ]]; then
            backup "${out_pdbfile}"
        fi
        generate_inp
        conv_runi
    done
    cd "${olddir}"
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
    for file in "$@"
    do
        mkdir -p "${backup_name}"
        mv "${file}" "${backup_name}"
    done
}

function conv_runi() {
    ((job_i++))
    log="$(basename ${inpname} .inp)".log
    cmd="${crd_convert} ${inpname} > ${log} &"
    echo "in $(pwd)"
    echo "${cmd}"
    eval "${cmd}"
    if (( job_i >= max_job )); then
        echo wait
        echo "======================================"
        (( job_i = 0 ))
        wait
    fi

}

function main() {
    set_config "$@"
    run
    echo wait
    echo "======================================"
    wait
}

function set_program() {
    if [[ "$HOSTNAME" == fn*sv* || ${SLURM_JOB_PARTITION} == mem* ]]; then
        source /opt/intel/oneapi/setvars.sh
        crd_convert=/vol0003/mdt0/data/hp250059/u12262/software/genesis-2.1.6.1/bin/crd_convert-intel-fugakupost
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
  -j, --jobs N      Run N jobs at the same time
  -m, --max_runi    The max_runi (default: -1)
  -h, --help        Show this help message and exit

Behavior:
  No positional arguments:
      Process all replicas.
  One positional argument:
      Process only that replica.
  Two positional arguments:
      Process replicas in range [repi_ini, repi_end].

Examples:
  $(basename "$0") 1 3 --jobs 8
  $(basename "$0") -j 9 1 3
  $(basename "$0") --max_runi 10 1 1
  $(basename "$0") -m 10 -j 8 1 3
  $(basename "$0") --help
EOF
}

function set_config() {
    repi_ini=1
    repi_end=20
    dir=conv
    inp_head=prod
    psffile=../../data/step3_input.psf
    pdbfile=../../data/initial_min.pdb
    reffile=${pdbfile}
    md_step1=600000
    mdout_period1=3000
    (( ana_period1 = mdout_period1 ))

    inpname_list=(conv.inp)
    template_list=(
"$(cat <<'EOF'
[INPUT]
psffile     = ${psffile}
pdbfile     = ${pdbfile}
reffile     = ${reffile}
 
[OUTPUT]
${out_pdbfile_line}
trjfile        = ${out_trjfile}
 
[TRAJECTORY]
trjfile1       = ${trjfile1}
md_step1       = ${md_step1}
mdout_period1  = ${mdout_period1}
ana_period1    = ${ana_period1}
repeat1        = 1
trj_format     = DCD
trj_type       = COOR+BOX
trj_natom      = 0               # (0:uses reference PDB atom count)
 
[SELECTION]
group1          = (not sid:IONS) and (not sid:SOLV)  # selection group 1
 
[OPTION]
check_only      = NO              # (YES/NO)
trjout_format   = DCD             # (PDB/DCD)
trjout_type     = COOR+BOX        # (COOR/COOR+BOX)
trjout_atom     = 1               # atom group
centering       = YES            # shift center of mass (YES requres psf/prmtop/grotop)
centering_atom  = 1              # atom group
center_coord    = 0.0 0.0 0.0    # target center coordinates
pbc_correct     = MOLECULE              # (NO/MOLECULE)
EOF
)"
    )

    max_job=1
    max_runi=-1
    positional=()
    while [[ $# -gt 0 ]]
    do
        case "$1" in
            -j|--jobs)
                [[ $# -ge 2 ]] || { echo "Error: --jobs needs a value"; exit 1; }
                max_job="$2"
                shift 2
                ;;
            -m|--max_runi)
                [[ $# -ge 2 ]] || { echo "Error: --max_runi needs a value"; exit 1; }
                max_runi="$2"
                shift 2
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
    set_program
}

main "$@"