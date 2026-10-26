# PEPSI

Code for our paper titled `PEPSI: Practically Efficient Private Set Intersection in the Unbalanced Setting`
Presented at Usenix 2024

The executables are benchmarks of the protocol built on [Microsoft SEAL](https://github.com/microsoft/SEAL) (BFV) and OpenMP. Client and server run in one process and exchange serialized ciphertexts through in-memory streams. Set elements are generated synthetically, so a run reports timings, noise budget and communication sizes rather than an actual intersection.

```
src/          C++ sources: client.cpp, server.cpp, utils.cpp and four drivers (main-*.cpp)
experiments/  parameter sweeps (Python), data.yaml, plots.ipynb, max-load simulation (script.cpp)
scripts/      build-windows.ps1
```

## Requirements

- A C++17 compiler with OpenMP: GCC or Clang. MSVC is not supported (the code uses `<getopt.h>` and OpenMP `collapse`). On Windows, use GCC from [MSYS2](https://www.msys2.org).
- CMake 3.22 or newer, plus Ninja or Make.
- Internet access for the first configure. CMake downloads Microsoft SEAL 4.7.1 (pinned and hash-checked) and SEAL's dependencies (Microsoft GSL, zlib, zstd), then builds them with the project. Nothing is installed system-wide.

## Build

### Windows (MSYS2 UCRT64)

1. Install MSYS2. Then, in the **MSYS2 UCRT64** shell, install the toolchain:

   ```bash
   pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja
   ```

   If Visual Studio 2022 is installed, `gcc` alone is enough. The build script falls back to the CMake and Ninja that ship with Visual Studio.

2. Build from PowerShell in the repository root. The first run downloads and builds SEAL, which takes a few minutes.

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
   ```

   Options: `-Clean` deletes `build\` first, `-BuildType RelWithDebInfo|Debug` changes the build type, and `-Msys2Root` sets a non-default MSYS2 location (default `C:\msys64`).

   You can also build in the MSYS2 UCRT64 shell directly: `cmake -S src -B build -G Ninja && cmake --build build`.

The `.exe` files are linked statically, so they run from any shell (PowerShell, cmd, Python) without MSYS2 on `PATH`.

### Linux / WSL

```bash
sudo apt install build-essential cmake git    # Ubuntu 22.04+ ships CMake >= 3.22
cmake -S src -B build
cmake --build build -j
```

macOS is untested. Apple Clang needs Homebrew's `libomp` for OpenMP.

### Using an installed SEAL instead (e.g. vcpkg)

```bash
cmake -S src -B build -DPEPSI_USE_SYSTEM_SEAL=ON -DCMAKE_PREFIX_PATH=/path/to/seal/install
# or, with vcpkg (what the original CMakeLists expected):
cmake -S src -B build -DPEPSI_USE_SYSTEM_SEAL=ON -DCMAKE_TOOLCHAIN_FILE=<vcpkg-root>/scripts/buildsystems/vcpkg.cmake
```

SEAL 4.0 or newer is required. Both 4.1.2 (the mid-2024 release) and 4.7.1 were tested on Linux. They gave the same noise budgets and communication sizes, and server time was 25 to 40% lower with 4.7.1. Expect timings to differ from the paper's numbers anyway, since the machine and SEAL version are different.

## Run

Executables are written to `build/` (with `.exe` on Windows):

| Executable | What it runs | Options (default) |
|---|---|---|
| `main-psi` | PSI for given set sizes. N=8192, Hamming weight h=8, effective bit-length λ=19. | `-c` client set size (1024), `-s` server set size (1048576), `-t` task (`PSI`), `-l` label size in bytes (1) |
| `main-psi-large` | Same with N=16384, h=16, λ = 40 + ⌈log2 μ⌉ | same as `main-psi`, default task `PSISum` |
| `main-base` | Fixed μ and γ. h is taken from a lookup table. | `-m` μ (250), `-g` γ (1), `-t` task (`LabelledPSI`), `-l` effective bit-length (19), `-x` `1` = communication-optimal h (default) or `2` = computation-optimal h |
| `main2` | One (bit-length, h) point on a single thread, μ=100, γ=1. Used by the h sweep. | `-l` effective bit-length (19), `-h` Hamming weight (8) |

Tasks: `PSI`, `LabelledPSI`, `PSICardinality`, `PSISum` (printed as 0 to 3). Long forms such as `--client_set 2048`, `--task PSISum`, `--mu 109` and `--effective_bitlength 24` also work.

Examples (Windows paths; drop `.exe` and use `/` on Linux):

```powershell
.\build\main-psi.exe                                  # defaults: 1024 vs 2^20 elements
.\build\main-psi.exe -c 2048 -s 4096 -t PSICardinality
.\build\main-psi.exe -t LabelledPSI -l 4
.\build\main-base.exe -m 109 -t PSISum -x 2
.\build\main2.exe -l 19 -h 8
```

Each run prints the parameters, the final noise budget in bits, the server time and the communication. A budget of 0 means the noise used up the budget, so the decrypted result may be wrong. Some configurations end at 0, e.g. `main-base -m 109 -t PSISum -x 2`. That happens with both SEAL 4.1.2 and 4.7.1, so it comes from the parameter choice, not the SEAL version. Each run also writes a metrics file `results/<timestamp>.csv` relative to the current directory (`metric,value` rows: `time_*` in ms, `comm_*` in bytes, plus the parameters `mu`, `gamma`, `hw`, `ell`, `effective_lambda`, ...).

`main-psi`, `main-psi-large` and `main-base` call `omp_set_num_threads(32)` (the paper's machine), and `main2` uses 1 thread. This works on machines with fewer cores. To change it, edit the call in the `main-*.cpp` file. Rough server times with default options on a 16-thread laptop (Core Ultra 7 255H): `main-base` 1.7 s, `main-psi` 3.5 s, `main2` 6.3 s, `main-psi-large` 10.5 s.

## Experiments

```bash
pip install -r experiments/requirements.txt
python experiments/find-comp-optimal-hw.py   # main2 over data.yaml:find_comp_hw (takes hours)
python experiments/compare.py                # main-base over data.yaml:compare_w_dipsi
jupyter notebook experiments/plots.ipynb
```

The scripts can be started from any directory. They run the binaries in `build/` and collect the metrics in `experiments/results/`, which `plots.ipynb` reads. Edit `experiments/data.yaml` to shrink a sweep. Run time grows roughly linearly with μ, so expect the largest μ values in `compare_w_dipsi` to take minutes per run and several GB of RAM.

`experiments/script.cpp` is a standalone balls-into-bins max-load simulation (used to bound μ). It is very long-running and appends to `simulation.csv`. Build it the same way: `cmake -S experiments -B build/experiments && cmake --build build/experiments` (in the MSYS2 UCRT64 shell on Windows).

## Changes made to get the code building

- `src/CMakeLists.txt`: the original pointed `CMAKE_TOOLCHAIN_FILE` at a vcpkg checkout in `src/vcpkg/`, which is not in the repository. It also set it after `project()`, where CMake ignores it. So SEAL was never found, and configuring failed with `Target "main-base" links to: SEAL::seal but the target was not found`. SEAL is now pinned to 4.7.1 and built automatically, or taken from an install with `PEPSI_USE_SYSTEM_SEAL=ON`. 4.7.1 is used instead of 4.1.2 because SEAL's MinGW (Windows GCC) build was only fixed in 4.4.1. Other changes: `set(CMAKE_CXX_FLAGS "-g")` overwrote any user flags and, without a build type, gave an unoptimized `-O0` build, so the default is now `Release`. C++17 is set explicitly, OpenMP is required, and MinGW builds are linked statically.
- Results: `client.cpp` now creates `results/`. Before, a missing folder meant the metrics were silently not written.
- Command line: long options were declared `optional_argument`, so `--client_set 2048` read the value as 0 and crashed. They are now `required_argument`.
- `client.cpp`/`server.cpp`: `1 << effective_lambda` overflowed `int` for λ ≥ 31 (`main-psi-large` uses λ = 49). It is now `1ULL << effective_lambda`.
- `experiments/compare.py` called `../build/main`, which no longer exists (it is `main-base`). Both sweep scripts now resolve paths relative to the script, add `.exe` on Windows, and report failed runs.

Tested on Windows 11 (MSYS2 UCRT64 GCC 15.1, CMake 3.31, Ninja) and Ubuntu 24.04 under WSL2 (GCC 13.3, CMake 3.28).
