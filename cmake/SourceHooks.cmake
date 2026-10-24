# swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
# https://github.com/ehsanMa86/swmm5plus-capi
#
# File:    cmake/SourceHooks.cmake
# Purpose: Helpers that copy upstream sources into the build tree and insert the C-interface hooks.
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
#
# Upstream checkouts are never modified. Sources are copied into the build
# tree and edited there; every edit is anchored on an exact text and the
# configure step fails if an anchor is missing, so a change upstream can never
# be patched silently in the wrong place.

function(s5p_replace file anchor replacement)
    if(ARGN)
        message(FATAL_ERROR "swmm5plus-capi: s5p_replace takes one replacement string (extra arguments: ${ARGN})")
    endif()
    file(READ "${file}" content)
    string(FIND "${content}" "${anchor}" position)
    if(position EQUAL -1)
        message(FATAL_ERROR "swmm5plus-capi: anchor not found in ${file}:\n${anchor}\n"
                            "The pinned SWMM5+ version may have changed; update cmake/SourceHooks.cmake.")
    endif()
    string(REPLACE "${anchor}" "${replacement}" content "${content}")
    file(WRITE "${file}" "${content}")
endfunction()

# Adds the hooks used by the C interface to a staged copy of SWMM5+.
function(s5p_apply_hooks dir intel)
    # 0. The sources are compiled with the C preprocessor (-cpp, -fpp), which
    #    joins a line that ends in a backslash with the next one, even in a
    #    Fortran comment. In utility_files.f90 this swallowed the statement
    #    "lc = len_trim(output_path)" after a comment ending in '\', leaving
    #    lc undefined before it indexes output_path.
    s5p_no_line_splices("${dir}")

    # 1. API mode: do not read the host program's command line.
    s5p_replace("${dir}/utility/utility_files.f90"
        "    use utility_crash, only: util_crashpoint\n"
        "    use utility_crash, only: util_crashpoint\n    use capi_state, only: capi_active, &\n        s5p_folder_exists, s5p_make_folder, s5p_copy_file, s5p_delete_file\n")
    s5p_replace("${dir}/utility/utility_files.f90"
        "        do while (ii <= iargc())"
        "        if (capi_active) return\n        do while (ii <= iargc())")

    # 2. Progress and cancellation once per time step (not during spin-up).
    set(step_call "            call tl_increment_timestep_and_counters(doHydraulicsStepYN, doHydrologyStepYN, inSpinUpYN)\n")
    string(CONCAT step_hook "${step_call}"
        "            if (.not. inSpinUpYN) then\n"
        "                if (capi_progress_stop(setting%Time%Now, setting%Time%End)) exit\n"
        "            end if\n")
    s5p_replace("${dir}/timeloop/timeloop.f90" "${step_call}" "${step_hook}")
    file(READ "${dir}/timeloop/timeloop.f90" tl)
    string(FIND "${tl}" "    implicit none" implicit_pos)
    if(implicit_pos EQUAL -1)
        message(FATAL_ERROR "swmm5plus-capi: no implicit none in timeloop.f90")
    endif()
    string(SUBSTRING "${tl}" 0 ${implicit_pos} head)
    string(SUBSTRING "${tl}" ${implicit_pos} -1 tail)
    string(CONCAT capi_use "    use capi_state, only: capi_progress_stop, capi_report, capi_step_mode, &\n"
        "        capi_single_step, capi_loop_continues, capi_doHydrologyStepYN, capi_doHydraulicsStepYN\n")
    file(WRITE "${dir}/timeloop/timeloop.f90" "${head}${capi_use}${tail}")

    #    Reporting callback (interface version 2): at every time SWMM5+ stores
    #    a level of its multi-level output, with the same time, also when the
    #    output files themselves are switched off.
    s5p_replace("${dir}/timeloop/timeloop.f90"
        "            !% --- check for crash conditions\n            call util_crashstop(13978)\n"
        "            if (.not. inSpinUpYN) then\n                if (util_output_must_report()) call capi_report(setting%Time%Now)\n            end if\n            !% --- check for crash conditions\n            call util_crashstop(13978)\n")

    #    Step mode (s5p_step): timeloop_toplevel stops before the time loop and
    #    keeps the loop flags; timeloop_capi_step runs one iteration of the
    #    unchanged loop body, and timeloop_capi_finish closes the loop.
    set(loop_call "        call tl_outerloop (doHydrologyStepYN, doHydraulicsStepYN, .false., .false.)\n")
    string(CONCAT loop_hook
        "        if (capi_step_mode) then\n"
        "            capi_doHydrologyStepYN  = doHydrologyStepYN\n"
        "            capi_doHydraulicsStepYN = doHydraulicsStepYN\n"
        "            capi_loop_continues     = .false.\n"
        "            return\n"
        "        end if\n"
        "${loop_call}")
    s5p_replace("${dir}/timeloop/timeloop.f90" "${loop_call}" "${loop_hook}")
    s5p_replace("${dir}/timeloop/timeloop.f90"
        "        thisStep = 1\n"
        "        if (.not. capi_loop_continues) thisStep = 1\n")
    s5p_replace("${dir}/timeloop/timeloop.f90"
        "        end do  !% --- end of time loop\n"
        "            if (capi_single_step) exit\n        end do  !% --- end of time loop\n")
    s5p_replace("${dir}/timeloop/timeloop.f90"
        "    public  :: timeloop_toplevel\n"
        "    public  :: timeloop_toplevel\n    public  :: timeloop_capi_step, timeloop_capi_finish\n")
    string(CONCAT step_procs
        "    subroutine timeloop_capi_step (finished)\n"
        "        !% Runs one iteration of the time loop (s5p_step); timeloop_toplevel\n"
        "        !% must have been called in step mode first.\n"
        "        logical, intent(out) :: finished\n"
        "        finished = (setting%Time%Now > setting%Time%End - setting%Time%DtTol)\n"
        "        if (finished) return\n"
        "        capi_single_step = .true.\n"
        "        call tl_outerloop (capi_doHydrologyStepYN, capi_doHydraulicsStepYN, .false., .false.)\n"
        "        capi_single_step    = .false.\n"
        "        capi_loop_continues = .true.\n"
        "        finished = (setting%Time%Now > setting%Time%End - setting%Time%DtTol)\n"
        "    end subroutine timeloop_capi_step\n"
        "\n"
        "    subroutine timeloop_capi_finish ()\n"
        "        !% Closes a time loop run with timeloop_capi_step, as the end of\n"
        "        !% timeloop_toplevel does.\n"
        "        integer(kind=8) :: cval, crate, cmax\n"
        "        sync all\n"
        "        if (this_image() == 1) then\n"
        "            call system_clock(count=cval,count_rate=crate,count_max=cmax)\n"
        "            setting%Time%WallClock%TimeMarchEnd = cval\n"
        "        end if\n"
        "    end subroutine timeloop_capi_finish\n"
        "\n"
        "end module timeloop")
    s5p_replace("${dir}/timeloop/timeloop.f90" "end module timeloop" "${step_procs}")

    #    Upstream bug (all compilers): a subcatchment that drains to an
    #    upstream end, a dead end or an outfall is connected to the first
    #    conduit element next to the node, which is checked by element type.
    #    The connection was made while the network is defined, before the
    #    initial conditions assign the element types, so every such model
    #    stopped with "USER CONFIGURATION ERROR ... diagnostic elements". It is
    #    made after the initial conditions instead; nothing in between uses it.
    s5p_replace("${dir}/initialization/initialization.f90"
        "                call init_subcatchment_elements()\n"
        "                !% (connected after the initial conditions)\n")
    s5p_replace("${dir}/initialization/initialization.f90"
        "        call util_crashstop(4429873)\n"
        "        call util_crashstop(4429873)\n        if (setting%Simulation%useHydrology) then\n            call init_subcatchment_elements()\n            call util_crashstop(4429874)\n        end if\n")
    #    Upstream bug (all compilers): the search for [PROFILES] opens the input
    #    file and returns without closing it when a model has no profiles. The
    #    file stays open until the process ends; on Windows it then cannot be
    #    deleted or replaced, so the temporary input file of a host program is
    #    left behind.
    s5p_replace("${dir}/initialization/initialization.f90"
        "            print *, \"... no profiles found\"\n            return\n"
        "            print *, \"... no profiles found\"\n            close (thisUnit)\n            return\n")

    # 3. Portable library loading, with a platform-specific library name.
    s5p_replace("${dir}/interface/interface.f90"
        "\"/libswmm5.so\""
        "\"/\" // trim(capi_swmmc_library)")
    s5p_replace("${dir}/interface/interface.f90"
        "    use c_library\n"
        "    use c_library\n    use capi_state, only: capi_swmmc_library\n")
    foreach(fn dlopen dlsym dlclose)
        s5p_replace("${dir}/interface/c_library.f90"
            "bind(c, name=\"${fn}\")"
            "bind(c, name=\"s5p_${fn}\")")
    endforeach()

    # 4. Upstream bug (all compilers): the time-step limiter for inflow
    #    boundaries masks a WHERE over the BC elements with the depth of *all*
    #    elements. The shapes differ, so the assignment writes past the end of
    #    the BC-sized arrays and corrupts the heap. The intended array is the
    #    depth of the elements downstream of each BC face (BCelemIdx).
    file(READ "${dir}/timeloop/timeloop.f90" tl)
    string(REGEX REPLACE "(BCInflowSmallDepth\\)[ \t&\r\n.a-z]*)\\(elemR\\(:,er_Depth\\)"
                         "\\1(elemR(BCelemIdx,er_Depth)" fixed "${tl}")
    if(fixed STREQUAL tl)
        message(FATAL_ERROR "swmm5plus-capi: BC inflow limiter not found in timeloop.f90")
    endif()
    file(WRITE "${dir}/timeloop/timeloop.f90" "${fixed}")

    #    Upstream bug (all compilers): the static-output header copies N+1
    #    names and units into N slots, writing one element past the end.
    foreach(kind Names Units)
        s5p_replace("${dir}/main/output.f90"
            "(output_static_type${kind}_elemR(1:N_Out_static_TypeElem+1))"
            "(output_static_type${kind}_elemR(1:N_Out_static_TypeElem))")
    endforeach()
    #    Upstream bug (all compilers): the static output of a node's elements
    #    copies N+1 rows of output_static_elemR into dset_data, which has N
    #    rows. gfortran takes the loop extent from the right-hand side and
    #    writes one value past the end of dset_data. The array sizes are
    #    multiples of 16 bytes, so glibc and Windows leave slack after the
    #    block, but the macOS allocator packs blocks without slack and the
    #    write damages its neighbour ("Heap corruption detected").
    s5p_replace("${dir}/main/output.f90"
        "output_static_elemR(first_elem_idx:first_elem_idx+N_node_elem,"
        "output_static_elemR(first_elem_idx:first_elem_idx+N_node_elem-1,")

    # 5. Standard Fortran: one component reference uses the DEC "." separator,
    #    which only Intel compilers accept.
    s5p_replace("${dir}/definitions/define_settings.f90"
        "setting%Output%Report.TimeInterval"
        "setting%Output%Report%TimeInterval")

    # 6. No shell commands. SWMM5+ runs mkdir, cp and rm with
    #    execute_command_line; Windows has no cp or rm, and its mkdir reads
    #    "/name" as an option. Each call becomes a call to the portable
    #    functions in src/s5p_fs.c, and folder tests use them instead of the
    #    Intel extension INQUIRE(DIRECTORY=).
    s5p_no_shell_commands("${dir}/utility/utility_files.f90")
    #    Absolute paths: SWMM5+ recognises only paths that start with "/".
    #    Windows paths such as "C:/model" are absolute too.
    s5p_replace("${dir}/utility/utility_files.f90"
        "        elseif (input_path(:1) .eq. '/') then"
        "        elseif (input_path(:1) .eq. '/' .or. input_path(2:2) .eq. ':') then")
    s5p_replace("${dir}/utility/utility_files.f90"
        "if (thisfolder(:1) == '/') then"
        "if (thisfolder(:1) == '/' .or. thisfolder(2:2) == ':') then")

    # 7. IFPORT is an Intel Fortran module; the functions SWMM5+ uses from it
    #    (getcwd, iargc, getarg) are also GNU extensions.
    if(NOT intel)
        s5p_replace("${dir}/initialization/initialization.f90" "    use IFPORT\n" "")
        s5p_replace("${dir}/utility/utility_files.f90" "    use ifport\n" "")
        s5p_portable_fortran("${dir}")
    endif()
endfunction()

# Removes backslashes at the end of lines in the staged Fortran sources.
# Free-form Fortran has no backslash continuation, so such a backslash can only
# end a comment; removing it keeps the preprocessor from joining the next line.
function(s5p_no_line_splices dir)
    file(GLOB_RECURSE sources "${dir}/*.f90")
    foreach(f IN LISTS sources)
        file(READ "${f}" content)
        string(REGEX REPLACE "\\\\([ \t]*\r?\n)" "\\1" fixed "${content}")
        if(NOT fixed STREQUAL content)
            file(WRITE "${f}" "${fixed}")
        endif()
    endforeach()
endfunction()

# Replaces the shell commands and folder tests in utility_files.f90.
function(s5p_no_shell_commands f)
    file(READ "${f}" content)
    # mkdir with a status and message: three calls, each over two lines.
    set(mkdir_re "call execute_command_line \\(\\('mkdir '//trim\\(([A-Za-z0-9_%]+)\\)\\),[ \t]*&[ \t\r]*\n[ \t]*(cmdstat|exitstat)=istat, cmdmsg=cmsg\\)")
    string(REGEX MATCHALL "${mkdir_re}" found "${content}")
    list(LENGTH found count)
    if(NOT count EQUAL 3)
        message(FATAL_ERROR "swmm5plus-capi: expected 3 mkdir commands with a status in ${f}, found ${count}")
    endif()
    string(REGEX REPLACE "${mkdir_re}" "call s5p_make_folder(trim(\\1), istat, cmsg)" content "${content}")
    file(WRITE "${f}" "${content}")

    s5p_replace("${f}" "call execute_command_line( ('mkdir '//trim(newfolder)) )"
                       "call s5p_make_folder(trim(newfolder))")
    s5p_replace("${f}" "call execute_command_line (('cp '//trim(setting%File%inp_file)//' '//trim(newfilename)))"
                       "call s5p_copy_file(trim(setting%File%inp_file), trim(newfilename))")
    s5p_replace("${f}" "call execute_command_line (('rm '//setting%File%inp_file))"
                       "call s5p_delete_file(setting%File%inp_file)")

    s5p_replace("${f}" "inquire (DIRECTORY=trim(setting%File%output_timestamp_subfolder),EXIST=isfolder)"
                       "isfolder = s5p_folder_exists(trim(setting%File%output_timestamp_subfolder))")
    s5p_replace("${f}" "inquire(DIRECTORY=newfolder,EXIST=doesexist)"
                       "doesexist = s5p_folder_exists(trim(newfolder))")
    s5p_replace("${f}" "inquire (DIRECTORY=trim(thisfolder),EXIST=folder_exist)"
                       "folder_exist = s5p_folder_exists(trim(thisfolder))")

    # Nothing may be left that starts a shell.
    file(STRINGS "${f}" remaining REGEX "^[ \t]*call[ \t]+execute_command_line")
    if(remaining)
        message(FATAL_ERROR "swmm5plus-capi: shell commands left in ${f}:\n${remaining}\n"
                            "Update s5p_no_shell_commands in cmake/SourceHooks.cmake.")
    endif()
endfunction()

# Replaces the first "/)" after @anchor with "/), [n,2])" and opens a reshape
# at the anchor, turning a rank-1 constructor into a valid rank-2 initializer.
function(s5p_reshape_initializer file anchor rows)
    file(READ "${file}" content)
    string(FIND "${content}" "${anchor}" pos)
    if(pos EQUAL -1)
        message(FATAL_ERROR "swmm5plus-capi: anchor not found in ${file}:\n${anchor}")
    endif()
    string(LENGTH "${anchor}" alen)
    math(EXPR after "${pos} + ${alen}")
    string(SUBSTRING "${content}" 0 ${pos} head)
    string(SUBSTRING "${content}" ${after} -1 tail)
    string(FIND "${tail}" "/)" close)
    string(SUBSTRING "${tail}" 0 ${close} body)
    math(EXPR rest "${close} + 2")
    string(SUBSTRING "${tail}" ${rest} -1 remainder)
    string(REPLACE "= (/" "= reshape((/" opened "${anchor}")
    file(WRITE "${file}" "${head}${opened}${body}/), [${rows},2])${remainder}")
endfunction()

# Standard-Fortran equivalents of Intel extensions, applied for other compilers.
# Each edit keeps the behaviour of the Intel build.
function(s5p_portable_fortran dir)
    # Range array constructors (/ a : b /)
    set(f "${dir}/utility/utility_allocate.f90")
    s5p_replace("${f}" "    use define_globals\n" "    use define_globals\n    use capi_state, only: s5p_range\n")
    foreach(col subcatchI subcatchR)
        s5p_replace("${f}" "(/Ncol_${col} +1 : Ncol_${col}  +N_subcatch_runon /)"
                           "s5p_range(Ncol_${col} + 1, Ncol_${col} + N_subcatch_runon)")
    endforeach()
    # A logical assigned to the real array (Intel converts it to zero); also
    # initialise the logical array that was clearly intended.
    s5p_replace("${f}" "        subcatchR(:,:) = nullvalueL\n"
                       "        subcatchR(:,:) = 0.0d0\n        subcatchYN(:,:) = nullvalueL\n")

    # Logical comparison
    s5p_replace("${dir}/timeloop/adjust.f90" "where (elemYN(thisP,eYNcol) == eYNvalue)"
                                             "where (elemYN(thisP,eYNcol) .eqv. eYNvalue)")


    # KIND argument must be an integer
    s5p_replace("${dir}/initialization/discretization.f90" "real(min_elem_per_link,real(8))"
                                                          "real(min_elem_per_link,8)")
    s5p_replace("${dir}/special_elements/orifice_elements.f90" "real(FlowDirection,real(8))"
                                                              "real(FlowDirection,8)")

    # Range constructor and integers used as logicals (Intel treats odd
    # integers as true; "success" only takes the values 0 and 1)
    set(f "${dir}/special_elements/control_hydraulics.f90")
    s5p_replace("${f}" "    use define_globals\n" "    use define_globals\n    use capi_state, only: s5p_range\n")
    s5p_replace("${f}" "(/ 1:N_ActionPoint /)" "s5p_range(1, N_ActionPoint)")
    s5p_replace("${f}" "if (success) then" "if (success /= 0) then")
    s5p_replace("${f}" "if ((success) .and. (rr < nRules-1))" "if ((success /= 0) .and. (rr < nRules-1))")
    s5p_replace("${f}" "if (success) kIdx = kIdx +1" "if (success /= 0) kIdx = kIdx +1")

    # Boundary-condition arrays are not allocated when a model has no head or
    # flow boundaries; writing to them is undefined behaviour that the Intel
    # build happens to tolerate.
    s5p_replace("${dir}/utility/utility_key_default.f90"
        "        BC%headI(:,keylist) = undefinedKey\n        BC%flowI(:,keylist) = undefinedKey\n"
        "        if (allocated(BC%headI)) BC%headI(:,keylist) = undefinedKey\n        if (allocated(BC%flowI)) BC%flowI(:,keylist) = undefinedKey\n")

    # FSEEK is a function in Intel's IFPORT and a subroutine in gfortran
    s5p_replace("${dir}/initialization/initialization.f90"
        "ierror = fseek(thisUnit, file_loc, 0)"
        "call fseek(thisUnit, file_loc, 0, ierror)")

    # DEC "." component separators
    s5p_replace("${dir}/initialization/ic_lowlevel.f90"
        "setting.Simulation.AllowReverseGradientInitialConditionsTF"
        "setting%Simulation%AllowReverseGradientInitialConditionsTF")

    # Logical values compared with integers or with .eq.
    s5p_replace("${dir}/main/output.f90" "else if(isFV .eq. .false. .and. FeatureType .eq. NodeOut) then"
                                         "else if((.not. isFV) .and. FeatureType .eq. NodeOut) then")
    s5p_replace("${dir}/timeloop/junction_lowlevel.f90" "if (bFixYN(kk) .ne. zeroI) then"
                                                        "if (bFixYN(kk)) then")

    # Rank-2 tables initialised from rank-1 constructors
    set(f "${dir}/special_elements/roadway_weir_elements.f90")
    foreach(table "4;Cd_LowPaved" "8;Cd_LowGravel" "2;Cd_HighPaved" "2;Cd_HighGravel" "9;Sf_Paved" "12;Sf_Gravel")
        list(GET table 0 rows)
        list(GET table 1 name)
        s5p_reshape_initializer("${f}" "dimension(${rows},2) :: ${name} = (/" ${rows})
    endforeach()
endfunction()
