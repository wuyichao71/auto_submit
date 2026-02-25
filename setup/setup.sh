name=${BASH_SOURCE[0]}
if [[ $name == *ims* ]]; then
    module -s purge
    module -s load gcc-toolset/13
    module -s load mkl/2025.0.0.1
    module -s load intelmpi/2021.14.1
    if [[ $name == *cuda12* ]]; then
        module -s load cuda/12.6u2
    fi
else
    if [[ $name == *intel* ]]; then
        source /home/appl/intel/oneapi/setvars.sh
    fi
    if [[ $name == *cuda12* ]] && [[ $name != *serine* ]]; then
        export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:$LD_LIBRARY_PATH
        export PATH=/usr/local/cuda-12.8/bin:$PATH
    elif [[ $name == *cuda12* ]] && [[ $name == *serine* ]]; then
        export LD_LIBRARY_PATH=/home/appl/cuda/cuda-12.3/lib64:$LD_LIBRARY_PATH
        export PATH=/home/wuyichao/bin/bin:/home/appl/cuda/cuda-12.3/bin:$PATH
    elif [[ $name == *cuda11* ]]; then
        export LD_LIBRARY_PATH=~/miniconda3/envs/cuda_11/lib:$LD_LIBRARY_PATH
        export PATH=/home/wuyichao/miniconda3/envs/cuda_11/bin:$PATH
    fi
fi

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
basedir=$(dirname ${SCRIPT_PATH})
base=$(basename ${basedir})
suffix=$(basename ${BASH_SOURCE[0]} .sh)
suffix=${suffix#setup-}
spdyn=${basedir}/bin/spdyn-${suffix}

if ! [[ -e $spdyn ]]; then
    mixed=""
    if [[ $name == *mixed* ]]; then
        mixed="--enable-mixed"
    fi
    gpu=""
    if [[ $name == *cuda* ]]; then
        gpu="--enable-gpu"
    fi

    if [[ $1 == configure ]]; then
        if [[ $name == *ims* ]]; then
            FC=mpif90 CC=mpicc LAPACK_LIBS=" -L${MKLROOT}/lib/intel64 -Wl,--no-as-needed -lmkl_gf_lp64 -lmkl_gnu_thread -lmkl_core -lgomp -lpthread -lm -ldl" ./configure --program-suffix="-${suffix}" "${mixed}" "${gpu}"
        else
            ./configure --program-suffix="-${suffix}" "$mixed" "$gpu"
        fi
    elif [[ $1 == make ]]; then
        make -j 8
    elif [[ $1 == install ]]; then
        make install -j 8
    fi
fi
