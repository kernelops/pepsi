# Read data.yaml and iterate over the 'effective_bitlength' parameter

import yaml
import os
import sys
import subprocess
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

# Paths are resolved relative to this file, so the script can be started from any
# directory. The executables write their metrics to experiments/results/.
EXPERIMENTS_DIR = Path(__file__).resolve().parent
EXE_SUFFIX = '.exe' if os.name == 'nt' else ''
PATH_TO_MAIN = EXPERIMENTS_DIR.parent / 'build' / f'main-base{EXE_SUFFIX}'

if not PATH_TO_MAIN.exists():
    sys.exit(f"{PATH_TO_MAIN} not found. Build the project first (see README.md).")

# Read data.yaml
with open(EXPERIMENTS_DIR / 'data.yaml') as f:
    data = yaml.load(f, Loader=yaml.FullLoader)
    params = data['compare_w_dipsi']
    for rep in range(params['repeat']):
        for mu in params['mu']:
            for type in [1,2]:
                cmd = [str(PATH_TO_MAIN),
                    '-m', str(mu),
                    '-t', 'PSISum',
                    '-x', str(type)]
                res=subprocess.run(cmd, cwd=EXPERIMENTS_DIR,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )
                if res.returncode != 0:
                    print(f"Run failed (exit code {res.returncode}): {' '.join(cmd)}")
                    print(res.stderr.decode(errors='replace'))
        print(f"Finished {rep}")
