# swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
# https://github.com/ehsanMa86/swmm5plus-capi
#
# File:    CMakeLists.txt
# Purpose: Builds SWMM5+ as a shared library with a C interface, plus the EPA SWMM library it uses.
#
# Copyright (C) 2026 Ehsan Madadi
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.21)
project(swmm5plus_capi VERSION 0.2.2
    DESCRIPTION "C interface for the SWMM5+ finite-volume hydraulic solver"
    HOMEPAGE_URL "https://github.com/ehsanMa86/swmm5plus-capi"
    LANGUAGES C Fortran)

option(S5P_BUILD_TESTS "Build the C test program" ON)
# On Windows the SWMM5+ program would share Fortran module variables with the
# DLL, which Windows does not support; Windows builds provide the library only.
if(WIN32)
    set(_s5p_exe_default OFF)
else()
    set(_s5p_exe_default ON)
endif()
option(S5P_BUILD_EXECUTABLE "Build the SWMM5+ command-line program as well" ${_s5p_exe_default})

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Memory-error checks for development and CI: AddressSanitizer for C and
# Fortran, and the gfortran run-time checks (array bounds and others). Out of
# bounds writes that the Linux and Windows allocators tolerate can abort on
# macOS; this finds them on Linux at the faulty statement.
option(S5P_SANITIZE "Build with AddressSanitizer and Fortran run-time checks (GCC)" OFF)
if(S5P_SANITIZE)
    if(NOT CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
        message(FATAL_ERROR "swmm5plus-capi: S5P_SANITIZE requires gfortran")
    endif()
    add_compile_options(-fsanitize=address -fno-omit-frame-pointer
        $<$<COMPILE_LANGUAGE:Fortran>:-fcheck=all> $<$<COMPILE_LANGUAGE:Fortran>:-fbacktrace>)
    add_link_options(-fsanitize=address)
endif()
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_Fortran_MODULE_DIRECTORY "${PROJECT_BINARY_DIR}/modules")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/bin")

include(FetchContent)
include(GNUInstallDirs)
include(cmake/SourceHooks.cmake)

# --- Upstream sources (pinned) -----------------------------------------------
# SWMM5+ (CIMM, University of Texas at Austin; public domain, Unlicense)
FetchContent_Declare(swmm5plus_upstream
    URL      https://github.com/CIMM-ORG/SWMM5plus/archive/afd44de9ea359ce298dff7aa63b0e77485ccb6b8.tar.gz
    URL_HASH SHA256=1e419cb98761641248d429c0092bf1247ecd8c7a4e3f4bd5bf5085127ff20806
    SOURCE_SUBDIR do-not-add
    DOWNLOAD_EXTRACT_TIMESTAMP ON)
# EPA SWMM 5.1.13, the version SWMM5+ is written against (public domain)
FetchContent_Declare(epaswmm_5113
    URL      https://github.com/USEPA/Stormwater-Management-Model/archive/v5.1.13.tar.gz
    URL_HASH SHA256=ab94da3bab37b02460c6f6f231e806547c0ec0355fbb647afba8d34c932f7780
    SOURCE_SUBDIR do-not-add
    DOWNLOAD_EXTRACT_TIMESTAMP ON)
# json-fortran 8.3.0 (BSD-style license), used by SWMM5+ for settings files
FetchContent_Declare(json_fortran_upstream
    URL      https://github.com/jacobwilliams/json-fortran/archive/3ab8f98209871875325c6985dd0e50085d1c82c2.tar.gz
    URL_HASH SHA256=c8d07090e332fa9b8fe90a8b2936f09cd3b408eefbe13a7124f3f1fe33a085fb
    SOURCE_SUBDIR do-not-add
    DOWNLOAD_EXTRACT_TIMESTAMP ON)
FetchContent_MakeAvailable(swmm5plus_upstream epaswmm_5113 json_fortran_upstream)

set(S5P_UPSTREAM "${swmm5plus_upstream_SOURCE_DIR}")
set(SWMMC_UPSTREAM "${epaswmm_5113_SOURCE_DIR}")
set(JSONF_UPSTREAM "${json_fortran_upstream_SOURCE_DIR}")

# --- EPA SWMM library with the SWMM5+ interface additions --------------------
set(SWMMC_DIR "${PROJECT_BINARY_DIR}/staged/swmmc")
file(REMOVE_RECURSE "${SWMMC_DIR}")
file(COPY "${SWMMC_UPSTREAM}/src/" DESTINATION "${SWMMC_DIR}")
foreach(f api.h api.c api_error.h api_error.c)
    file(COPY "${S5P_UPSTREAM}/interface/${f}" DESTINATION "${SWMMC_DIR}")
endforeach()
foreach(pair "add_to_controls.c;controls.c" "add_to_funcs.h;funcs.h" "add_to_lid.c;lid.c" "add_to_lid.h;lid.h")
    list(GET pair 0 from)
    list(GET pair 1 to)
    file(READ "${S5P_UPSTREAM}/interface/${from}" extra)
    file(APPEND "${SWMMC_DIR}/${to}" "${extra}")
endforeach()
# api.c (from SWMM5+) calls the POSIX mkdir(path, mode) in an unused export
# function; Windows provides _mkdir(path).
s5p_replace("${SWMMC_DIR}/api.c" "#include <unistd.h>\n"
    "#include <unistd.h>\n#if defined(_WIN32)\n#include <direct.h>\n#define mkdir(path, mode) _mkdir(path)\n#endif\n")
file(GLOB SWMMC_SOURCES "${SWMMC_DIR}/*.c")
list(FILTER SWMMC_SOURCES EXCLUDE REGEX "/main\\.c$")
# Subcatchment results and unit factors for the C interface (version 2).
list(APPEND SWMMC_SOURCES "${PROJECT_SOURCE_DIR}/src/s5p_hydrology.c")
add_library(swmm5plus_swmmc SHARED ${SWMMC_SOURCES})
target_include_directories(swmm5plus_swmmc PRIVATE "${SWMMC_DIR}")
# EPA SWMM 5.1 and the SWMM5+ additions predate C23, where "int f()" means a
# function without arguments (the default of GCC 15 and later).
set_target_properties(swmm5plus_swmmc PROPERTIES C_STANDARD 11 C_EXTENSIONS ON)
target_compile_options(swmm5plus_swmmc PRIVATE $<$<C_COMPILER_ID:GNU,Clang,AppleClang,IntelLLVM>:-fcommon -w>)
# No fused multiply-add: on ARM64 (Apple silicon) the compilers fuse a*b+c by
# default, so expressions such as FTTOM(z) - FTTOM(z) in api.c leave a rounding
# residue (e.g. an outfall initial depth of -2e-15 m, which SWMM5+ rejects).
# This keeps results identical to x86-64, where FMA is not used by default.
target_compile_options(swmm5plus_swmmc PRIVATE $<$<C_COMPILER_ID:GNU,Clang,AppleClang>:-ffp-contract=off>)
if(UNIX)
    target_link_libraries(swmm5plus_swmmc PRIVATE m)
endif()
if(WIN32)
    set_target_properties(swmm5plus_swmmc PROPERTIES PREFIX "")
endif()

# --- SWMM5+ Fortran sources with the C-interface hooks -----------------------
set(S5P_DIR "${PROJECT_BINARY_DIR}/staged/swmm5plus")
file(REMOVE_RECURSE "${S5P_DIR}")
foreach(sub definitions geometry initialization interface main special_elements timeloop utility)
    file(COPY "${S5P_UPSTREAM}/${sub}/" DESTINATION "${S5P_DIR}/${sub}" FILES_MATCHING PATTERN "*.f90")
endforeach()
string(COMPARE EQUAL "${CMAKE_Fortran_COMPILER_ID}" "IntelLLVM" _ifx)
string(COMPARE EQUAL "${CMAKE_Fortran_COMPILER_ID}" "Intel" _ifort)
if(_ifx OR _ifort)
    set(S5P_INTEL ON)
else()
    set(S5P_INTEL OFF)
endif()
s5p_apply_hooks("${S5P_DIR}" ${S5P_INTEL})

file(GLOB_RECURSE S5P_FORTRAN "${S5P_DIR}/*.f90")
list(FILTER S5P_FORTRAN EXCLUDE REGEX "/main/main\\.f90$")
set(JSON_FORTRAN_SOURCES
    "${JSONF_UPSTREAM}/src/json_kinds.F90"
    "${JSONF_UPSTREAM}/src/json_parameters.F90"
    "${JSONF_UPSTREAM}/src/json_string_utilities.F90"
    "${JSONF_UPSTREAM}/src/json_value_module.F90"
    "${JSONF_UPSTREAM}/src/json_file_module.F90"
    "${JSONF_UPSTREAM}/src/json_module.F90")

# --- HDF5 (Fortran), used by SWMM5+ for its output files ----------------------
find_package(HDF5 CONFIG QUIET COMPONENTS Fortran static)
if(NOT HDF5_FOUND)
    find_package(HDF5 CONFIG QUIET COMPONENTS Fortran shared)
endif()
set(S5P_HDF5 "")
foreach(candidate hdf5::hdf5_fortran-static hdf5_fortran-static hdf5::hdf5_fortran-shared hdf5_fortran-shared)
    if(NOT S5P_HDF5 AND TARGET ${candidate})
        set(S5P_HDF5 ${candidate})
    endif()
endforeach()
if(S5P_HDF5)
    message(STATUS "swmm5plus-capi: using HDF5 target ${S5P_HDF5}")
else()
    find_package(HDF5 REQUIRED COMPONENTS Fortran)
    set(S5P_HDF5 ${HDF5_Fortran_LIBRARIES})
    include_directories(${HDF5_Fortran_INCLUDE_DIRS} ${HDF5_INCLUDE_DIRS})
endif()

# --- Fortran flags -------------------------------------------------------------
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    # -ffp-contract=off: no fused multiply-add on ARM64, as for the EPA SWMM library.
    set(S5P_FFLAGS -fcoarray=single -ffree-line-length-none -fno-range-check -cpp -ffp-contract=off)
elseif(S5P_INTEL)
    set(S5P_FFLAGS -coarray=single -fpp)
else()
    set(S5P_FFLAGS "")
endif()

add_library(swmm5plus_capi SHARED
    src/capi_state.F90
    src/swmm5plus_capi.f90
    src/s5p_console.c
    src/s5p_dl.c
    src/s5p_fs.c
    src/s5p_runtime.c
    ${JSON_FORTRAN_SOURCES}
    ${S5P_FORTRAN})
target_include_directories(swmm5plus_capi
    PUBLIC  "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>" "$<INSTALL_INTERFACE:include>"
    PRIVATE "${JSONF_UPSTREAM}/src")
target_compile_options(swmm5plus_capi PRIVATE $<$<COMPILE_LANGUAGE:Fortran>:${S5P_FFLAGS}>)
target_compile_definitions(swmm5plus_capi PRIVATE SWMM5PLUS_CAPI_BUILD
    $<$<PLATFORM_ID:Windows>:S5P_WINDOWS> $<$<PLATFORM_ID:Darwin>:S5P_APPLE>)
target_link_libraries(swmm5plus_capi PRIVATE ${S5P_HDF5} ${CMAKE_DL_LIBS})
# Intel Fortran: the coarray runtime must be linked as well as compiled for,
# otherwise the Fortran runtime in the library leaves its coarray symbols
# undefined and programs linking the library fail.
if(S5P_INTEL)
    target_link_options(swmm5plus_capi PRIVATE -coarray=single)
    # Starts the Intel Fortran runtime when a C program loads the library (src/s5p_runtime.c).
    target_compile_definitions(swmm5plus_capi PRIVATE S5P_INTEL_FORTRAN)
endif()
add_dependencies(swmm5plus_capi swmm5plus_swmmc)
if(WIN32)
    set_target_properties(swmm5plus_capi PROPERTIES PREFIX "")
    # The C API is implemented in Fortran (bind(C)), so its functions carry no
    # dllexport attribute. Export exactly the functions declared in the public
    # header through a module-definition file.
    file(STRINGS "${PROJECT_SOURCE_DIR}/include/swmm5plus.h" _s5p_decls REGEX "^S5P_API ")
    set(_s5p_def "LIBRARY swmm5plus_capi\nEXPORTS\n")
    foreach(_decl IN LISTS _s5p_decls)
        if(_decl MATCHES "(s5p_[a-z0-9_]+)\\(")
            string(APPEND _s5p_def "    ${CMAKE_MATCH_1}\n")
        endif()
    endforeach()
    file(WRITE "${PROJECT_BINARY_DIR}/swmm5plus_capi.def" "${_s5p_def}")
    target_sources(swmm5plus_capi PRIVATE "${PROJECT_BINARY_DIR}/swmm5plus_capi.def")
endif()
# With MinGW, link the GCC, Fortran and threads runtimes into the libraries.
# Host applications built with another MinGW release load their own copies of
# libgcc_s_seh-1.dll and libwinpthread-1.dll, and Windows reuses a DLL that is
# already loaded under the same name, so separate runtime DLLs could clash.
if(MINGW)
    target_link_options(swmm5plus_capi PRIVATE -static)
    target_link_options(swmm5plus_swmmc PRIVATE -static)
endif()
if(APPLE)
    set_target_properties(swmm5plus_capi swmm5plus_swmmc PROPERTIES INSTALL_RPATH "@loader_path")
elseif(UNIX)
    set_target_properties(swmm5plus_capi swmm5plus_swmmc PROPERTIES INSTALL_RPATH "\$ORIGIN")
endif()

if(S5P_BUILD_EXECUTABLE)
    add_executable(swmm5plus "${S5P_DIR}/main/main.f90")
    target_compile_options(swmm5plus PRIVATE ${S5P_FFLAGS})
    if(S5P_INTEL)
        target_link_options(swmm5plus PRIVATE -coarray=single)
    endif()
    target_link_libraries(swmm5plus PRIVATE swmm5plus_capi ${S5P_HDF5})
endif()

if(S5P_BUILD_TESTS)
    enable_testing()
    add_executable(s5p_test tests/test_capi.c)
    target_link_libraries(s5p_test PRIVATE swmm5plus_capi)
    add_test(NAME capi-run
        COMMAND s5p_test "${PROJECT_SOURCE_DIR}/tests/data/extran4.inp" "${PROJECT_BINARY_DIR}/test-output"
                "$<TARGET_FILE_DIR:swmm5plus_swmmc>")
    # SWMM5+ ends the process with STOP (exit code 0) on input errors, so the
    # test passes only when the program prints its final summary line.
    # The full 8-hour run takes 6 to 8 minutes on a desktop computer and can take
    # several times longer on shared CI runners.
    set_tests_properties(capi-run PROPERTIES TIMEOUT 3600
        PASS_REGULAR_EXPRESSION "time steps, peak link flow [0-9]"
        FAIL_REGULAR_EXPRESSION "crash point|USER CONFIGURATION ERROR|CODE ERROR")
    # Interface version 2 on a short model with subcatchments: the whole run,
    # host-driven stepping, and a stop requested by the reporting callback.
    # Everything SWMM5+ prints is discarded (s5p_set_console), so its texts
    # must not appear, while the test's own output from a callback must.
    add_executable(s5p_api_test tests/test_api.c)
    target_link_libraries(s5p_api_test PRIVATE swmm5plus_capi)
    if(UNIX)
        target_link_libraries(s5p_api_test PRIVATE m)
    endif()
    set(_s5p_api_fail "FAILED|crash point|USER CONFIGURATION ERROR|CODE ERROR|Retrieving project data|SWMM5\\+ finished")
    foreach(mode run step cancel)
        add_test(NAME capi-api-${mode}
            COMMAND s5p_api_test ${mode} "${PROJECT_SOURCE_DIR}/tests/data/catchments.inp"
                    "${PROJECT_BINARY_DIR}/test-output-${mode}" "$<TARGET_FILE_DIR:swmm5plus_swmmc>")
        set_tests_properties(capi-api-${mode} PROPERTIES TIMEOUT 1800
            PASS_REGULAR_EXPRESSION "report callback output is visible.*interface version 2 test passed"
            FAIL_REGULAR_EXPRESSION "${_s5p_api_fail}")
        if(S5P_SANITIZE)
            set_tests_properties(capi-api-${mode} PROPERTIES
                ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0:halt_on_error=1;GFORTRAN_UNBUFFERED_ALL=1"
                FAIL_REGULAR_EXPRESSION "${_s5p_api_fail}|AddressSanitizer|Fortran runtime error")
        endif()
    endforeach()
    if(S5P_SANITIZE)
        # SWMM5+ leaves its module arrays allocated at exit; report memory
        # errors only, and fail on Fortran run-time errors as well. The checks
        # make the run about three times slower.
        set_tests_properties(capi-run PROPERTIES TIMEOUT 10800
            ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0:halt_on_error=1;GFORTRAN_UNBUFFERED_ALL=1"
            FAIL_REGULAR_EXPRESSION "crash point|USER CONFIGURATION ERROR|CODE ERROR|AddressSanitizer|Fortran runtime error")
    endif()
endif()

install(TARGETS swmm5plus_capi swmm5plus_swmmc
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}")
install(FILES include/swmm5plus.h DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}")
install(FILES LICENSE README.md THIRD_PARTY_NOTICES.md DESTINATION "${CMAKE_INSTALL_DOCDIR}")
