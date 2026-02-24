name=${BASH_SOURCE[0]}
if [[ $name == *intel* ]]; then
    source /home/appl/intel/oneapi/setvars.sh
fi
if [[ $name == *cuda12* ]] && [[ $name != *serine* ]]; then
    export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:$LD_LIBRARY_PATH
    export PATH=/usr/local/cuda-12.8/bin:$PATH
elif [[ $name == *cuda12* ]] && [[ $name == *serine* ]]; then
    export LD_LIBRARY_PATH=/home/appl/cuda/cuda-12.3/lib64:$LD_LIBRARY_PATH
    export PATH=/home/wuyichao/bin/bin:/home/appl/cuda/cuda-12.3/bin:$PATH
    echo here
elif [[ $name == *cuda11* ]]; then
    export LD_LIBRARY_PATH=~/miniconda3/envs/cuda_11/lib:$LD_LIBRARY_PATH
    export PATH=/home/wuyichao/miniconda3/envs/cuda_11/bin:$PATH
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
        ./configure --program-suffix="-${suffix}" "$mixed" "$gpu"
    elif [[ $1 == make ]]; then
        make -j 8
    elif [[ $1 == install ]]; then
        make install -j 8
    fi
fi
