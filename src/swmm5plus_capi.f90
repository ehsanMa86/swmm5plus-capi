! swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
! https://github.com/ehsanMa86/swmm5plus-capi
!
! File:    src/swmm5plus_capi.f90
! Purpose: Fortran bind(C) implementation of the SWMM5+ C interface declared in include/swmm5plus.h.
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
module swmm5plus_capi
    use iso_c_binding
    use capi_state
    use define_settings, only: setting
    use define_globals
    use define_indexes
    use define_keys
    use initialization, only: initialize_toplevel
    use timeloop, only: timeloop_toplevel
    use finalization, only: finalize_toplevel
    use utility, only: util_first_and_last_elem_of_link
    implicit none
    private

    public :: s5p_api_version, s5p_version, s5p_open, s5p_set_progress_callback, s5p_set_quiet
    public :: s5p_initialize, s5p_run, s5p_finalize, s5p_close
    public :: s5p_get_count, s5p_get_name, s5p_get_value, s5p_get_times, s5p_last_error

    integer, parameter :: S5P_OK = 0
    integer, parameter :: S5P_ERR_STATE = 1
    integer, parameter :: S5P_ERR_ARGUMENT = 2
    integer, parameter :: S5P_ERR_CANCELLED = 3

    integer, parameter :: STATE_CLOSED = 0
    integer, parameter :: STATE_OPEN = 1
    integer, parameter :: STATE_INITIALIZED = 2
    integer, parameter :: STATE_RAN = 3
    integer, parameter :: STATE_FINALIZED = 4
    integer :: state = STATE_CLOSED

    character(len=*), parameter :: SWMM5PLUS_VERSION = '1.0.3'

    interface
        function c_strlen(s) bind(C, name='strlen') result(n)
            import :: c_ptr, c_size_t
            type(c_ptr), value :: s
            integer(c_size_t) :: n
        end function c_strlen
        function c_absolute_path(path, out, length) bind(C, name='s5p_absolute_path') result(rc)
            import :: c_ptr, c_char, c_int
            type(c_ptr), value :: path
            character(kind=c_char), dimension(*) :: out
            integer(c_int), value :: length
            integer(c_int) :: rc
        end function c_absolute_path
    end interface

contains

    !% --------------------------------------------------------------------
    !% Helpers
    !% --------------------------------------------------------------------
    function from_c(p) result(s)
        type(c_ptr), intent(in) :: p
        character(len=:), allocatable :: s
        character(kind=c_char), pointer :: chars(:)
        integer :: n, i
        n = int(c_strlen(p))
        allocate (character(len=n) :: s)
        if (n == 0) return
        call c_f_pointer(p, chars, [n])
        do i = 1, n
            s(i:i) = chars(i)
        end do
    end function from_c

    function absolute_from_c(p) result(s)
        !% Absolute path of a C string; SWMM5+ mishandles relative paths.
        type(c_ptr), intent(in) :: p
        character(len=:), allocatable :: s
        character(kind=c_char) :: buffer(4096)
        integer :: i
        if (c_absolute_path(p, buffer, int(size(buffer), c_int)) /= 0) then
            s = from_c(p)
            return
        end if
        i = 0
        do while (i < size(buffer))
            if (buffer(i + 1) == c_null_char) exit
            i = i + 1
        end do
        allocate (character(len=i) :: s)
        do i = 1, len(s)
            s(i:i) = buffer(i)
        end do
    end function absolute_from_c

    integer(c_int) function to_c(text, buffer, length)
        character(len=*), intent(in) :: text
        type(c_ptr), intent(in) :: buffer
        integer(c_int), intent(in) :: length
        character(kind=c_char), pointer :: out(:)
        integer :: m, i
        to_c = S5P_OK
        if (.not. c_associated(buffer) .or. length <= 0) then
            to_c = S5P_ERR_ARGUMENT
            return
        end if
        call c_f_pointer(buffer, out, [length])
        m = min(len_trim(text), length - 1)
        do i = 1, m
            out(i) = text(i:i)
        end do
        out(m + 1) = c_null_char
    end function to_c

    integer(c_int) function fail(code, message)
        integer, intent(in) :: code
        character(len=*), intent(in) :: message
        call capi_set_error(message)
        fail = code
    end function fail

    function parent_folder(path) result(folder)
        character(len=*), intent(in) :: path
        character(len=:), allocatable :: folder
        integer :: k
        k = max(scan(path, '/', back=.true.), scan(path, '\', back=.true.))
        if (k > 1) then
            folder = path(1:k - 1)
        else
            folder = '.'
        end if
    end function parent_folder

    !% --------------------------------------------------------------------
    !% Interface
    !% --------------------------------------------------------------------
    integer(c_int) function s5p_api_version() bind(C, name='s5p_api_version')
        s5p_api_version = 1
    end function s5p_api_version

    integer(c_int) function s5p_version(buffer, length) bind(C, name='s5p_version')
        type(c_ptr), value :: buffer
        integer(c_int), value :: length
        s5p_version = to_c(SWMM5PLUS_VERSION, buffer, length)
    end function s5p_version

    integer(c_int) function s5p_open(inp_file, output_dir, settings_file, swmm_library_dir) &
        bind(C, name='s5p_open')
        type(c_ptr), value :: inp_file, output_dir, settings_file, swmm_library_dir
        character(len=:), allocatable :: inp
        if (state /= STATE_CLOSED) then
            s5p_open = fail(S5P_ERR_STATE, 's5p_open: a model is already open in this process')
            return
        end if
        if (.not. c_associated(inp_file)) then
            s5p_open = fail(S5P_ERR_ARGUMENT, 's5p_open: the input file name is required')
            return
        end if
        inp = absolute_from_c(inp_file)
        capi_active = .true.
        capi_cancelled = .false.
        capi_error_message = ''
        setting%File%inp_file = inp
        setting%File%project_folder = parent_folder(inp)
        if (c_associated(output_dir)) setting%File%output_folder = absolute_from_c(output_dir)
        if (c_associated(settings_file)) setting%File%setting_file = absolute_from_c(settings_file)
        if (c_associated(swmm_library_dir)) setting%File%library_folder = absolute_from_c(swmm_library_dir)
        state = STATE_OPEN
        s5p_open = S5P_OK
    end function s5p_open

    integer(c_int) function s5p_set_progress_callback(callback, user_data) &
        bind(C, name='s5p_set_progress_callback')
        type(c_funptr), value :: callback
        type(c_ptr), value :: user_data
        capi_progress_cb = callback
        capi_progress_user = user_data
        s5p_set_progress_callback = S5P_OK
    end function s5p_set_progress_callback

    integer(c_int) function s5p_set_quiet(quiet) bind(C, name='s5p_set_quiet')
        integer(c_int), value :: quiet
        setting%Output%CommandLine%quietYN = (quiet /= 0)
        setting%Output%Verbose = (quiet == 0)
        s5p_set_quiet = S5P_OK
    end function s5p_set_quiet

    integer(c_int) function s5p_initialize() bind(C, name='s5p_initialize')
        if (state /= STATE_OPEN) then
            s5p_initialize = fail(S5P_ERR_STATE, 's5p_initialize: call s5p_open first')
            return
        end if
        call initialize_toplevel()
        state = STATE_INITIALIZED
        s5p_initialize = S5P_OK
    end function s5p_initialize

    integer(c_int) function s5p_run() bind(C, name='s5p_run')
        if (state /= STATE_INITIALIZED) then
            s5p_run = fail(S5P_ERR_STATE, 's5p_run: call s5p_initialize first')
            return
        end if
        call timeloop_toplevel()
        state = STATE_RAN
        if (capi_cancelled) then
            s5p_run = fail(S5P_ERR_CANCELLED, 's5p_run: stopped by the progress callback')
        else
            s5p_run = S5P_OK
        end if
    end function s5p_run

    integer(c_int) function s5p_finalize() bind(C, name='s5p_finalize')
        if (state /= STATE_RAN) then
            s5p_finalize = fail(S5P_ERR_STATE, 's5p_finalize: call s5p_run first')
            return
        end if
        call finalize_toplevel()
        state = STATE_FINALIZED
        s5p_finalize = S5P_OK
    end function s5p_finalize

    integer(c_int) function s5p_close() bind(C, name='s5p_close')
        !% SWMM5+ keeps its data in module variables, so a second model cannot
        !% be opened in the same process; the state stays "closed for good".
        capi_active = .false.
        capi_progress_cb = c_null_funptr
        capi_progress_user = c_null_ptr
        if (state /= STATE_CLOSED) state = -1
        s5p_close = S5P_OK
    end function s5p_close

    integer(c_int) function s5p_get_count(object, count) bind(C, name='s5p_get_count')
        integer(c_int), value :: object
        integer(c_int), intent(out) :: count
        count = 0
        if (state < STATE_INITIALIZED) then
            s5p_get_count = fail(S5P_ERR_STATE, 's5p_get_count: call s5p_initialize first')
            return
        end if
        select case (object)
        case (0)
            count = setting%SWMMinput%N_node
        case (1)
            count = setting%SWMMinput%N_link
        case default
            s5p_get_count = fail(S5P_ERR_ARGUMENT, 's5p_get_count: unknown object type')
            return
        end select
        s5p_get_count = S5P_OK
    end function s5p_get_count

    integer(c_int) function s5p_get_name(object, index, buffer, length) bind(C, name='s5p_get_name')
        integer(c_int), value :: object, index
        type(c_ptr), value :: buffer
        integer(c_int), value :: length
        integer :: i
        if (state < STATE_INITIALIZED) then
            s5p_get_name = fail(S5P_ERR_STATE, 's5p_get_name: call s5p_initialize first')
            return
        end if
        i = index + 1
        select case (object)
        case (0)
            if (i < 1 .or. i > setting%SWMMinput%N_node) then
                s5p_get_name = fail(S5P_ERR_ARGUMENT, 's5p_get_name: node index out of range')
                return
            end if
            s5p_get_name = to_c(trim(node%Names(i)%str), buffer, length)
        case (1)
            if (i < 1 .or. i > setting%SWMMinput%N_link) then
                s5p_get_name = fail(S5P_ERR_ARGUMENT, 's5p_get_name: link index out of range')
                return
            end if
            s5p_get_name = to_c(trim(link%Names(i)%str), buffer, length)
        case default
            s5p_get_name = fail(S5P_ERR_ARGUMENT, 's5p_get_name: unknown object type')
        end select
    end function s5p_get_name

    integer(c_int) function s5p_get_value(object, index, property, value) bind(C, name='s5p_get_value')
        integer(c_int), value :: object, index, property
        real(c_double), intent(out) :: value
        integer :: i, e, f, firstElem, lastElem, nElem
        logical :: isUp, isDn
        value = 0.0_c_double
        if (state < STATE_INITIALIZED) then
            s5p_get_value = fail(S5P_ERR_STATE, 's5p_get_value: call s5p_initialize first')
            return
        end if
        i = index + 1
        s5p_get_value = S5P_OK
        select case (object)
        case (0)
            if (i < 1 .or. i > setting%SWMMinput%N_node) then
                s5p_get_value = fail(S5P_ERR_ARGUMENT, 's5p_get_value: node index out of range')
                return
            end if
            if (node%I(i, ni_node_type) == nJ2) then
                !% two-link junctions are faces between finite volumes
                f = node%I(i, ni_face_idx)
                if (f < 1) return
                select case (property)
                case (0)
                    value = faceR(f, fr_Depth_d)
                case (1)
                    value = faceR(f, fr_Head_d)
                case default
                    s5p_get_value = fail(S5P_ERR_ARGUMENT, 's5p_get_value: unknown node property')
                end select
            else
                e = node%I(i, ni_elem_idx)
                if (e < 1) return
                select case (property)
                case (0)
                    value = elemR(e, er_Depth)
                case (1)
                    value = elemR(e, er_Head)
                case default
                    s5p_get_value = fail(S5P_ERR_ARGUMENT, 's5p_get_value: unknown node property')
                end select
            end if
        case (1)
            if (i < 1 .or. i > setting%SWMMinput%N_link) then
                s5p_get_value = fail(S5P_ERR_ARGUMENT, 's5p_get_value: link index out of range')
                return
            end if
            firstElem = 0
            lastElem = -1
            nElem = 0
            isUp = .false.
            isDn = .false.
            call util_first_and_last_elem_of_link(i, firstElem, lastElem, nElem, isUp, isDn)
            if (firstElem < 1 .or. lastElem < firstElem) return
            select case (property)
            case (0)
                value = sum(elemR(firstElem:lastElem, er_Flowrate)) / real(lastElem - firstElem + 1, 8)
            case (1)
                value = sum(elemR(firstElem:lastElem, er_Depth)) / real(lastElem - firstElem + 1, 8)
            case (2)
                value = sum(elemR(firstElem:lastElem, er_Velocity)) / real(lastElem - firstElem + 1, 8)
            case (3)
                value = sum(elemR(firstElem:lastElem, er_Area)) / real(lastElem - firstElem + 1, 8)
            case default
                s5p_get_value = fail(S5P_ERR_ARGUMENT, 's5p_get_value: unknown link property')
            end select
        case default
            s5p_get_value = fail(S5P_ERR_ARGUMENT, 's5p_get_value: unknown object type')
        end select
    end function s5p_get_value

    integer(c_int) function s5p_get_times(start_s, end_s, report_s) bind(C, name='s5p_get_times')
        real(c_double), intent(out) :: start_s, end_s, report_s
        start_s = setting%Time%Start
        end_s = setting%Time%End
        report_s = setting%Output%Report%TimeInterval
        if (state < STATE_INITIALIZED) then
            s5p_get_times = fail(S5P_ERR_STATE, 's5p_get_times: call s5p_initialize first')
            return
        end if
        s5p_get_times = S5P_OK
    end function s5p_get_times

    integer(c_int) function s5p_last_error(buffer, length) bind(C, name='s5p_last_error')
        type(c_ptr), value :: buffer
        integer(c_int), value :: length
        s5p_last_error = to_c(trim(capi_error_message), buffer, length)
    end function s5p_last_error

end module swmm5plus_capi
