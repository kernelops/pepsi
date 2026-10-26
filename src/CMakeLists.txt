cmake_minimum_required(VERSION 3.22)

project(pepsi VERSION 1.0 LANGUAGES CXX)

if(MSVC)
    message(FATAL_ERROR
        "MSVC is not supported: the code uses <getopt.h> and OpenMP 3 (collapse). "
        "On Windows, build with MSYS2 UCRT64 GCC (see README.md).")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Default to an optimized build (use RelWithDebInfo or Debug for debugging).
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# -----------------------------------------------------------------------------
# Microsoft SEAL
#
# By default the pinned release below is downloaded and built together with
# this project, so every machine uses the same SEAL version. To use an installed
# SEAL (>= 4.0) instead, configure with -DPEPSI_USE_SYSTEM_SEAL=ON, e.g. with
# vcpkg: -DCMAKE_TOOLCHAIN_FILE=<vcpkg>/scripts/buildsystems/vcpkg.cmake
# -----------------------------------------------------------------------------
option(PEPSI_USE_SYSTEM_SEAL "Use an installed Microsoft SEAL instead of downloading the pinned release" OFF)

if(PEPSI_USE_SYSTEM_SEAL)
    find_package(SEAL REQUIRED CONFIG)
    if(SEAL_VERSION VERSION_LESS 4.0)
        message(FATAL_ERROR "Found Microsoft SEAL ${SEAL_VERSION}, but 4.0 or newer is required.")
    endif()
    message(STATUS "Microsoft SEAL: using installed version ${SEAL_VERSION}")
else()
    set(PEPSI_SEAL_VERSION 4.7.1)
    message(STATUS "Microsoft SEAL: using pinned release ${PEPSI_SEAL_VERSION}")

    include(FetchContent)
    if(POLICY CMP0135)
        cmake_policy(SET CMP0135 NEW)
    endif()
    # Same release archive (and hash) as the vcpkg "seal" port.
    FetchContent_Declare(seal
        URL      https://github.com/microsoft/SEAL/archive/refs/tags/v${PEPSI_SEAL_VERSION}.tar.gz
        URL_HASH SHA256=49dfc5eed8274c1aaa7cb7ccfea9ec448f8896ce9305db949e27d89f4f752931
    )
    # Build only the C++ library. SEAL's remaining defaults (Microsoft GSL, zlib
    # and zstd compression, no Intel HEXL) match the vcpkg port's defaults, so
    # the measured communication sizes use the same serialization settings.
    set(SEAL_BUILD_EXAMPLES OFF CACHE BOOL "Build SEAL examples")
    set(SEAL_BUILD_TESTS    OFF CACHE BOOL "Build SEAL tests")
    set(SEAL_BUILD_BENCH    OFF CACHE BOOL "Build SEAL benchmarks")
    set(SEAL_BUILD_SEAL_C   OFF CACHE BOOL "Build the SEAL C wrapper")
    FetchContent_MakeAvailable(seal)
endif()

find_package(OpenMP REQUIRED COMPONENTS CXX)

# -----------------------------------------------------------------------------
# Executables
# -----------------------------------------------------------------------------
set(PEPSI_COMMON_SOURCES server.cpp client.cpp utils.cpp)

foreach(app IN ITEMS main-base main2 main-psi main-psi-large)
    add_executable(${app} ${app}.cpp ${PEPSI_COMMON_SOURCES})
    if(MINGW)
        # Self-contained .exe files that run without the MinGW runtime DLLs
        # (libstdc++, libgomp, winpthread) on PATH. OpenMP::OpenMP_CXX would link
        # libgomp's DLL import library by full path, so pass -fopenmp to the
        # linker instead and let -static pick libgomp.a.
        target_compile_options(${app} PRIVATE ${OpenMP_CXX_FLAGS})
        target_link_options(${app} PRIVATE ${OpenMP_CXX_FLAGS} -static)
        target_link_libraries(${app} PRIVATE SEAL::seal)
    else()
        target_link_libraries(${app} PRIVATE SEAL::seal OpenMP::OpenMP_CXX)
    endif()
endforeach()
