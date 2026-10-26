# Read data.yaml and iterate over the 'effective_bitlength' parameter

import yaml
import os
import sys
import subprocess
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

def valid_hw(bl, hw):
    if hw > bl/2:
        return False
    if hw < 1:
        return False
    if bl / hw > 12:
        return False
    if bl > 12 and hw > bl/2-2:
        return False
    if bl > 24 and hw > bl/2-4:
        return False
    if bl > 28 and hw > bl/2-6:
        return False
    return True

# Paths are resolved relative to this file, so the script can be started from any
# directory. The executables write their metrics to experiments/results/.
EXPERIMENTS_DIR = Path(__file__).resolve().parent
EXE_SUFFIX = '.exe' if os.name == 'nt' else ''
PATH_TO_MAIN2 = EXPERIMENTS_DIR.parent / 'build' / f'main2{EXE_SUFFIX}'

if not PATH_TO_MAIN2.exists():
    sys.exit(f"{PATH_TO_MAIN2} not found. Build the project first (see README.md).")

# Read data.yaml
with open(EXPERIMENTS_DIR / 'data.yaml') as f:
    data = yaml.load(f, Loader=yaml.FullLoader)
    params = data['find_comp_hw']
    for rep in range(params['repeat']):
        for bl in params['effective_bitlength']:
            for hw in range(1, bl):
                if not valid_hw(bl, hw):
                    continue
                cmd = [str(PATH_TO_MAIN2),
                    '-l', str(bl),
                    '-h', str(hw)]
                res=subprocess.run(cmd, cwd=EXPERIMENTS_DIR,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )
                if res.returncode != 0:
                    print(f"Run failed (exit code {res.returncode}): {' '.join(cmd)}")
                    print(res.stderr.decode(errors='replace'))
        print(f"Finished {rep}")
