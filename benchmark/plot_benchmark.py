import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import os
from pathlib import Path
from itertools import cycle

config = {
    'csv_template': 'benchmark.csv',
    'markers': cycle(["o", "s", "^", "D", "v", "*", "P", "X"]), 
    'out_template': os.path.join('picture', 'benchmark.jpg'),
}


def convert_value(x: str):
    if '.' in x:
        return float(x)
    elif x.isdigit():
        return int(x)
    return x


def main():
    csv_name = config['csv_template']

    # load CSV without a header row (header=None). pandas will assign
    # integer column names 0,1,2,... unless you provide names explicitly.
    df = pd.read_csv(csv_name, sep=',', header=None,)

    benchmark = []
    for idx, row in df.iterrows():
        a_bench = {}
        for col_name, value in row.items():
            k, v = value.split('=')
            a_bench[k] = convert_value(v)
        benchmark.append(a_bench)
    
    plot_data = {}
    omp_set = set(d['omp'] for d in benchmark)
    for omp in sorted(omp_set):
        node = np.array([d['node'] for d in benchmark if d['omp'] == omp])
        ns = np.array([d['ns/day'] for d in benchmark if d['omp'] == omp])
        idx = node.argsort()
        node_sort = node[idx]
        ns_sort = ns[idx]
        plot_data[omp] = {"x": node_sort, "y": ns_sort}
    
    fig = plt.figure()
    for i, omp in enumerate(plot_data):
        plt.plot(plot_data[omp]['x'], plot_data[omp]['y'], 
                 marker=next(config['markers']),
                 label=f'OpenMP={omp}')
    plt.legend(frameon=False)
    plt.grid(which='both')
    plt.xlabel('# of node')
    plt.ylabel('benchmark [ns/day]')
    plt.xscale('log', base=2)
    plt.yscale('log', base=10)
    plt.tight_layout()
    outname = config['out_template']
    Path(outname).parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(outname)
    



if __name__ == '__main__':
    main()