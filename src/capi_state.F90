! swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
! https://github.com/ehsanMa86/swmm5plus-capi
!
! File:    src/capi_state.F90
! Purpose: State shared between the C interface and the patched SWMM5+ sources (API mode, progress callback, errors).
!
! Copyright (C) 2026 Ehsan Madadi
!
! This program is free software: you can redistribute it and/or modify it
! under the terms of the GNU General Public License as published by the Free
! Software Foundation, either version 3 of the License, or (at your option)
! any later version.
!
! This program is distributed in the hope that it will be useful, but WITHOUT
! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
! FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
! more details.
!
! You should have received a copy of the GNU General Public License along
! with this program. If not, see <https://www.gnu.org/licenses/>.
!
! SPDX-License-Identifier: GPL-3.0-or-later
module capi_state
    !% Compiled before the SWMM5+ modules. The build adds small hooks to the
    !% SWMM5+ sources that use this module:
    !%   - utility_files: skip command-line parsing when capi_active is true,
    !%                    and manage folders and files without a shell,
    !%   - timeloop:      call capi_progress_stop once per time step,
    !%                    capi_report at every reporting time, and run
    !%                    one step at a time in step mode (s5p_step),
    !%   - interface:     load the EPA SWMM library named capi_swmmc_library.
    use iso_c_binding
    use iso_fortran_env, only: output_unit
    implicit none
    private

    public :: capi_active
    public :: capi_cancelled
    public :: capi_progress_cb
    public :: capi_progress_user
    public :: capi_error_message
    public :: capi_swmmc_library
    public :: capi_progress_stop
    public :: capi_report_cb
    public :: capi_report_user
    public :: capi_report_period
    public :: capi_report
    public :: capi_step_mode
    public :: capi_single_step
    public :: capi_loop_continues
    public :: capi_doHydrologyStepYN
    public :: capi_doHydraulicsStepYN
    public :: capi_console_capture
    public :: capi_console_release
    public :: capi_set_error
    public :: s5p_range
    public :: s5p_folder_exists
    public :: s5p_make_folder
    public :: s5p_copy_file
    public :: s5p_delete_file

    !% True while SWMM5+ is driven through the C interface.
    logical :: capi_active = .false.
    !% Set when the progress callback asked to stop.
    logical :: capi_cancelled = .false.
    type(c_funptr) :: capi_progress_cb = c_null_funptr
    type(c_ptr)    :: capi_progress_user = c_null_ptr
    character(len=1024) :: capi_error_message = ''

    !% Reporting callback (s5p_set_report_callback) and the number of
    !% reporting periods delivered so far.
    type(c_funptr) :: capi_report_cb = c_null_funptr
    type(c_ptr)    :: capi_report_user = c_null_ptr
    integer        :: capi_report_period = 0

    !% Step mode (s5p_step): timeloop_toplevel returns before the time loop,
    !% and the host runs the loop one iteration at a time. The flags of the
    !% loop that carry over from one iteration to the next are kept here.
    logical :: capi_step_mode = .false.
    logical :: capi_single_step = .false.
    logical :: capi_loop_continues = .false.
    logical :: capi_doHydrologyStepYN = .false.
    logical :: capi_doHydraulicsStepYN = .false.

    !% File name of the EPA SWMM library built next to this one.
    !% The Fortran preprocessor does not reliably predefine platform macros,
    !% so CMakeLists.txt passes S5P_WINDOWS or S5P_APPLE.
#if defined(S5P_WINDOWS) || defined(_WIN32)
    character(len=*), parameter :: capi_swmmc_library = 'swmm5plus_swmmc.dll'
#elif defined(S5P_APPLE) || defined(__APPLE__)
    character(len=*), parameter :: capi_swmmc_library = 'libswmm5plus_swmmc.dylib'
#else
    character(len=*), parameter :: capi_swmmc_library = 'libswmm5plus_swmmc.so'
#endif

    abstract interface
        function progress_fn(now, endt, user) bind(C) result(stop_flag)
            import :: c_double, c_ptr, c_int
            real(c_double), value :: now
            real(c_double), value :: endt
            type(c_ptr), value    :: user
            integer(c_int)        :: stop_flag
        end function progress_fn
        function report_fn(period, now, user) bind(C) result(stop_flag)
            import :: c_double, c_ptr, c_int
            integer(c_int), value :: period
            real(c_double), value :: now
            type(c_ptr), value    :: user
            integer(c_int)        :: stop_flag
        end function report_fn
    end interface

    !% Console redirection in src/s5p_console.c (s5p_set_console).
    interface
        subroutine c_console_capture() bind(C, name='s5p_console_capture')
        end subroutine c_console_capture
        subroutine c_console_release() bind(C, name='s5p_console_release')
        end subroutine c_console_release
    end interface

    !% Folder and file operations in src/s5p_fs.c. They replace the shell
    !% commands (mkdir, cp, rm) that SWMM5+ runs with execute_command_line.
    interface
        function c_folder_exists(path) bind(C, name='s5p_fs_folder_exists') result(rc)
            import :: c_char, c_int
            character(kind=c_char), dimension(*), intent(in) :: path
            integer(c_int) :: rc
        end function c_folder_exists
        function c_make_folder(path) bind(C, name='s5p_fs_make_folder') result(rc)
            import :: c_char, c_int
            character(kind=c_char), dimension(*), intent(in) :: path
            integer(c_int) :: rc
        end function c_make_folder
        function c_copy_file(from, to) bind(C, name='s5p_fs_copy_file') result(rc)
            import :: c_char, c_int
            character(kind=c_char), dimension(*), intent(in) :: from, to
            integer(c_int) :: rc
        end function c_copy_file
        function c_delete_file(path) bind(C, name='s5p_fs_delete_file') result(rc)
            import :: c_char, c_int
            character(kind=c_char), dimension(*), intent(in) :: path
            integer(c_int) :: rc
        end function c_delete_file
    end interface

contains

    logical function capi_progress_stop(now, endt)
        !% Reports progress to the host and returns true when it asks to stop,
        !% or when the reporting callback asked to stop during this step.
        real(8), intent(in) :: now, endt
        procedure(progress_fn), pointer :: fp
        integer(c_int) :: rc
        capi_progress_stop = capi_cancelled
        if (capi_cancelled .or. .not. c_associated(capi_progress_cb)) return
        call c_f_procpointer(capi_progress_cb, fp)
        call capi_console_release()
        rc = fp(real(now, c_double), real(endt, c_double), capi_progress_user)
        call capi_console_capture()
        if (rc /= 0) then
            capi_cancelled = .true.
            capi_progress_stop = .true.
        end if
    end function capi_progress_stop

    subroutine capi_report(now)
        !% Delivers a reporting period to the host. A non-zero return value
        !% stops the run at the end of the current step.
        real(8), intent(in) :: now
        procedure(report_fn), pointer :: fp
        integer(c_int) :: rc
        if (c_associated(capi_report_cb)) then
            call c_f_procpointer(capi_report_cb, fp)
            call capi_console_release()
            rc = fp(int(capi_report_period, c_int), real(now, c_double), capi_report_user)
            call capi_console_capture()
            if (rc /= 0) capi_cancelled = .true.
        end if
        capi_report_period = capi_report_period + 1
    end subroutine capi_report

    subroutine capi_console_capture()
        !% Sends standard output where s5p_set_console asked, while SWMM5+ runs.
        flush (output_unit)
        call c_console_capture()
    end subroutine capi_console_capture

    subroutine capi_console_release()
        !% Gives standard output back to the host.
        flush (output_unit)
        call c_console_release()
    end subroutine capi_console_release

    subroutine capi_set_error(message)
        character(len=*), intent(in) :: message
        capi_error_message = message
    end subroutine capi_set_error

    pure function s5p_range(first, last) result(values)
        !% Standard replacement for the Intel range constructor (/ first : last /).
        integer, intent(in) :: first, last
        integer, allocatable :: values(:)
        integer :: k
        allocate (values(max(0, last - first + 1)))
        do k = 1, size(values)
            values(k) = first + k - 1
        end do
    end function s5p_range

    logical function s5p_folder_exists(path)
        !% Standard replacement for the Intel extension INQUIRE(DIRECTORY=).
        character(len=*), intent(in) :: path
        s5p_folder_exists = c_folder_exists(trim(path) // c_null_char) /= 0
    end function s5p_folder_exists

    subroutine s5p_make_folder(path, istat, cmsg)
        !% Replaces "mkdir path" run through the shell; also creates missing
        !% parent folders. istat is 0 on success, as with cmdstat/exitstat.
        character(len=*), intent(in) :: path
        integer, intent(out), optional :: istat
        character(len=*), intent(inout), optional :: cmsg
        integer(c_int) :: rc
        rc = c_make_folder(trim(path) // c_null_char)
        if (present(istat)) istat = int(rc)
        if (present(cmsg) .and. rc /= 0) write (cmsg, '(A,I0,A)') 'cannot create the folder (system error ', rc, ')'
    end subroutine s5p_make_folder

    subroutine s5p_copy_file(from, to)
        !% Replaces "cp from to" run through the shell.
        character(len=*), intent(in) :: from, to
        integer(c_int) :: rc
        rc = c_copy_file(trim(from) // c_null_char, trim(to) // c_null_char)
        if (rc /= 0) write (*, '(A,I0,A)') 'WARNING: could not copy ' // trim(from) // ' (system error ', rc, ')'
    end subroutine s5p_copy_file

    subroutine s5p_delete_file(path)
        !% Replaces "rm path" run through the shell.
        character(len=*), intent(in) :: path
        integer(c_int) :: rc
        rc = c_delete_file(trim(path) // c_null_char)
    end subroutine s5p_delete_file

end module capi_state
