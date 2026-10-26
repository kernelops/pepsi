<#
.SYNOPSIS
    Builds PEPSI natively on Windows with MSYS2 (UCRT64 GCC), CMake and Ninja.

.DESCRIPTION
    Compiles with g++ from MSYS2's UCRT64 environment. CMake (>= 3.22) and Ninja are
    taken from MSYS2 UCRT64, from PATH, or from the copies bundled with Visual Studio,
    in that order. The first configure downloads and builds the pinned Microsoft SEAL
    release, so it needs internet access once and takes a few minutes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1 -Clean -BuildType RelWithDebInfo
#>
[CmdletBinding()]
param(
    [string]$Msys2Root = 'C:\msys64',
    [string]$BuildDir,
    [ValidateSet('Release', 'RelWithDebInfo', 'Debug')]
    [string]$BuildType = 'Release',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $BuildDir) { $BuildDir = Join-Path $repoRoot 'build' }
$minCMake = [version]'3.22.0'

function Get-VsBundledTool([string]$relativePath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return @() }
    $found = @()
    foreach ($vs in (& $vswhere -all -sort -products * -property installationPath)) {
        $candidate = Join-Path $vs $relativePath
        if (Test-Path $candidate) { $found += $candidate }
    }
    return $found
}

function Get-PathTool([string]$name) {
    $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return @($cmd.Source) }
    return @()
}

function Get-CMakeVersion([string]$exe) {
    $line = & $exe --version 2>$null | Select-Object -First 1
    if ($line -match '(\d+)\.(\d+)\.(\d+)') { return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    return $null
}

# --- Compiler: MSYS2 UCRT64 GCC ----------------------------------------------
$ucrtBin = Join-Path $Msys2Root 'ucrt64\bin'
$gcc = Join-Path $ucrtBin 'gcc.exe'
$gxx = Join-Path $ucrtBin 'g++.exe'
if (-not (Test-Path $gxx)) {
    throw "g++ not found in $ucrtBin. Install MSYS2 (https://www.msys2.org) and, in the 'MSYS2 UCRT64' shell, run:`n  pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja"
}
# g++ needs its own runtime DLLs at compile time, so UCRT64 goes first on PATH (this process only).
$env:PATH = "$ucrtBin;$env:PATH"

# --- CMake --------------------------------------------------------------------
$cmake = $null
$cmakeCandidates = @(
    (Join-Path $ucrtBin 'cmake.exe')
    (Get-PathTool 'cmake')
    (Get-VsBundledTool 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
) | Where-Object { $_ }
foreach ($candidate in $cmakeCandidates) {
    if (-not (Test-Path $candidate)) { continue }
    $version = Get-CMakeVersion $candidate
    if ($version -and $version -ge $minCMake) { $cmake = $candidate; break }
}
if (-not $cmake) {
    throw "CMake >= $minCMake not found. In the 'MSYS2 UCRT64' shell run: pacman -S --needed mingw-w64-ucrt-x86_64-cmake"
}

# --- Ninja --------------------------------------------------------------------
$ninja = $null
$ninjaCandidates = @(
    (Join-Path $ucrtBin 'ninja.exe')
    (Get-PathTool 'ninja')
    (Get-VsBundledTool 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe')
) | Where-Object { $_ }
foreach ($candidate in $ninjaCandidates) {
    if (Test-Path $candidate) { $ninja = $candidate; break }
}
if (-not $ninja) {
    throw "Ninja not found. In the 'MSYS2 UCRT64' shell run: pacman -S --needed mingw-w64-ucrt-x86_64-ninja"
}

Write-Host "g++   : $gxx ($((& $gxx -dumpfullversion).Trim()))"
Write-Host "cmake : $cmake ($(Get-CMakeVersion $cmake))"
Write-Host "ninja : $ninja ($((& $ninja --version).Trim()))"
Write-Host "build : $BuildDir ($BuildType)"

if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host "Removing $BuildDir"
    Remove-Item -Recurse -Force $BuildDir
}

# --- Configure and build ------------------------------------------------------
& $cmake -S (Join-Path $repoRoot 'src') -B $BuildDir -G Ninja `
    "-DCMAKE_BUILD_TYPE=$BuildType" `
    "-DCMAKE_C_COMPILER=$($gcc -replace '\\', '/')" `
    "-DCMAKE_CXX_COMPILER=$($gxx -replace '\\', '/')" `
    "-DCMAKE_MAKE_PROGRAM=$($ninja -replace '\\', '/')"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed (exit code $LASTEXITCODE). If you switched generators or compilers, re-run with -Clean." }

& $cmake --build $BuildDir --parallel
if ($LASTEXITCODE -ne 0) { throw "Build failed (exit code $LASTEXITCODE)." }

Write-Host ''
Write-Host 'Built executables:'
Get-ChildItem -Path $BuildDir -Filter 'main*.exe' | ForEach-Object { Write-Host "  $($_.FullName)" }
