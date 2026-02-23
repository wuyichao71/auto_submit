#!/usr/bin/env bash
#SBATCH --cpus-per-task=24
#SBATCH -p beta
#SBATCH -o stdout.%x
#SBATCH -e stdout.%x

#$ -S /bin/bash
#$ -cwd
#$ -V
#$ -pe mpi 16
#$ -l mem_total=100G
#$ -q all.q@helix.local
#$ -e stdout.$JOB_NAME
#$ -o stdout.$JOB_NAME

function get_job_name {
    _tmp=${JOB_NAME:-$0}
    _tmp=${_tmp%%.*}
    _tmp=${_tmp##*/}
    _tmp=${_tmp#sub_*_}
    jobname=$_tmp
}

function set_cpu {
    if [[ -n $SLURM_CPUS_PER_TASK ]]; then
        cpu=$SLURM_CPUS_PER_TASK
    elif [[ -n $NSLOTS ]]; then
        cpu=$NSLOTS
    else
        cpu=$(nproc)
    fi
}

get_job_name
set_cpu
PYTHON=/home/wuyichao/anaconda3/envs/work/bin/python

mkdir -p log
repi=0
for traji in {1..288}
do
    $PYTHON ${jobname}.py $traji -d -o | tee log/${jobname}_rep${traji}.log &
    ((repi++))
    if [[ $repi -ge $cpu ]]; then
        wait
        repi=0
    fi
done
wait