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
    !% Compiled before the SWMM5+ modules. The build adds three small hooks to
    !% the SWMM5+ sources that use this module:
    !%   - utility_files: skip command-line parsing when capi_active is true,
    !%   - timeloop:      call capi_progress_stop once per time step,
    !%   - interface:     load the EPA SWMM library named capi_swmmc_library.
    use iso_c_binding
    implicit none
    private

    public :: capi_active
    public :: capi_cancelled
    public :: capi_progress_cb
    public :: capi_progress_user
    public :: capi_error_message
    public :: capi_swmmc_library
    public :: capi_progress_stop
    public :: capi_set_error
    public :: s5p_range

    !% True while SWMM5+ is driven through the C interface.
    logical :: capi_active = .false.
    !% Set when the progress callback asked to stop.
    logical :: capi_cancelled = .false.
    type(c_funptr) :: capi_progress_cb = c_null_funptr
    type(c_ptr)    :: capi_progress_user = c_null_ptr
    character(len=1024) :: capi_error_message = ''

    !% File name of the EPA SWMM library built next to this one.
#if defined(_WIN32)
    character(len=*), parameter :: capi_swmmc_library = 'swmm5plus_swmmc.dll'
#elif defined(__APPLE__)
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
    end interface

contains

    logical function capi_progress_stop(now, endt)
        !% Reports progress to the host and returns true when it asks to stop.
        real(8), intent(in) :: now, endt
        procedure(progress_fn), pointer :: fp
        capi_progress_stop = .false.
        if (.not. c_associated(capi_progress_cb)) return
        call c_f_procpointer(capi_progress_cb, fp)
        if (fp(real(now, c_double), real(endt, c_double), capi_progress_user) /= 0) then
            capi_cancelled = .true.
            capi_progress_stop = .true.
        end if
    end function capi_progress_stop

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

end module capi_state
