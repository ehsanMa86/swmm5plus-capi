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
    use timeloop, only: timeloop_toplevel, timeloop_capi_step, timeloop_capi_finish
    use finalization, only: finalize_toplevel
    use interface_, only: c_lib
    use utility, only: util_first_and_last_elem_of_link
    implicit none
    private

    public :: s5p_api_version, s5p_version, s5p_open, s5p_set_progress_callback, s5p_set_quiet
    public :: s5p_set_report_callback, s5p_set_console
    public :: s5p_initialize, s5p_run, s5p_step, s5p_finalize, s5p_close
    public :: s5p_get_count, s5p_get_name, s5p_get_value, s5p_get_values, s5p_get_times, s5p_last_error

    integer, parameter :: S5P_OK = 0
    integer, parameter :: S5P_ERR_STATE = 1
    integer, parameter :: S5P_ERR_ARGUMENT = 2
    integer, parameter :: S5P_ERR_CANCELLED = 3
    integer, parameter :: S5P_END = 5

    integer, parameter :: OBJ_NODE = 0
    integer, parameter :: OBJ_LINK = 1
    integer, parameter :: OBJ_SUBCATCH = 2
    integer, parameter :: OBJ_SYSTEM = 3

    integer, parameter :: NODE_DEPTH = 0
    integer, parameter :: NODE_HEAD = 1
    integer, parameter :: NODE_VOLUME = 2
    integer, parameter :: NODE_LATERAL_INFLOW = 3
    integer, parameter :: NODE_TOTAL_INFLOW = 4
    integer, parameter :: NODE_FLOODING = 5

    integer, parameter :: LINK_FLOW = 0
    integer, parameter :: LINK_DEPTH = 1
    integer, parameter :: LINK_VELOCITY = 2
    integer, parameter :: LINK_AREA = 3
    integer, parameter :: LINK_VOLUME = 4
    integer, parameter :: LINK_CAPACITY = 5

    integer, parameter :: SUB_RAINFALL = 0
    integer, parameter :: SUB_EVAPORATION = 1
    integer, parameter :: SUB_INFILTRATION = 2
    integer, parameter :: SUB_RUNOFF = 3
    integer, parameter :: SUB_AREA = 4

    integer, parameter :: SYS_RAINFALL = 0
    integer, parameter :: SYS_EVAPORATION = 1
    integer, parameter :: SYS_INFILTRATION = 2
    integer, parameter :: SYS_RUNOFF = 3
    integer, parameter :: SYS_LATERAL_INFLOW = 4
    integer, parameter :: SYS_FLOODING = 5
    integer, parameter :: SYS_OUTFLOW = 6
    integer, parameter :: SYS_STORAGE = 7

    integer, parameter :: STATE_CLOSED = 0
    integer, parameter :: STATE_OPEN = 1
    integer, parameter :: STATE_INITIALIZED = 2
    integer, parameter :: STATE_RAN = 3
    integer, parameter :: STATE_FINALIZED = 4
    integer, parameter :: STATE_STEPPING = 5
    integer :: state = STATE_CLOSED

    character(len=*), parameter :: SWMM5PLUS_VERSION = '1.0.3'

    !% Conversions from the SI units of SWMM5+ to the units of the input
    !% file: EPA SWMM's factors from its internal US units, divided by the
    !% factors SWMM5+ uses to convert those to SI (interface/api.h).
    real(8), parameter :: FT_TO_M = 0.3048d0
    real(8), parameter :: CF_TO_CM = 0.0283168466d0
    real(8) :: to_length = 1.0d0
    real(8) :: to_flow = 1.0d0
    real(8) :: to_volume = 1.0d0

    !% Subcatchment functions in the EPA SWMM library (src/s5p_hydrology.c).
    type(c_funptr) :: swmmc_subcatch_values = c_null_funptr
    type(c_funptr) :: swmmc_subcatch_name = c_null_funptr

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
        function c_symbol(handle, name) bind(C, name='s5p_dlsym') result(fp)
            import :: c_ptr, c_char, c_funptr
            type(c_ptr), value :: handle
            character(kind=c_char), dimension(*), intent(in) :: name
            type(c_funptr) :: fp
        end function c_symbol
        function c_console_set_mode(mode) bind(C, name='s5p_console_set_mode') result(rc)
            import :: c_int
            integer(c_int), value :: mode
            integer(c_int) :: rc
        end function c_console_set_mode
    end interface

    abstract interface
        function subcatch_values_fn(elapsed, property, values, count) bind(C) result(n)
            import :: c_double, c_int
            real(c_double), value :: elapsed
            integer(c_int), value :: property, count
            real(c_double), dimension(*) :: values
            integer(c_int) :: n
        end function subcatch_values_fn
        function subcatch_name_fn(j, buffer, length) bind(C) result(rc)
            import :: c_int, c_char
            integer(c_int), value :: j, length
            character(kind=c_char), dimension(*) :: buffer
            integer(c_int) :: rc
        end function subcatch_name_fn
        function unit_factors_fn(flow, length, volume) bind(C) result(rc)
            import :: c_double, c_int
            real(c_double), intent(out) :: flow, length, volume
            integer(c_int) :: rc
        end function unit_factors_fn
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

    logical function values_available()
        !% The network arrays exist from initialization until finalization.
        values_available = state == STATE_INITIALIZED .or. state == STATE_RAN .or. state == STATE_STEPPING
    end function values_available

    integer function object_count(object)
        !% Number of objects of a type, or -1 for an unknown type.
        integer, intent(in) :: object
        select case (object)
        case (OBJ_NODE)
            object_count = setting%SWMMinput%N_node
        case (OBJ_LINK)
            object_count = setting%SWMMinput%N_link
        case (OBJ_SUBCATCH)
            object_count = setting%SWMMinput%N_subcatch
        case (OBJ_SYSTEM)
            object_count = 1
        case default
            object_count = -1
        end select
    end function object_count

    logical function valid_property(object, property)
        integer, intent(in) :: object, property
        select case (object)
        case (OBJ_NODE)
            valid_property = property >= NODE_DEPTH .and. property <= NODE_FLOODING
        case (OBJ_LINK)
            valid_property = property >= LINK_FLOW .and. property <= LINK_CAPACITY
        case (OBJ_SUBCATCH)
            valid_property = property >= SUB_RAINFALL .and. property <= SUB_AREA
        case (OBJ_SYSTEM)
            valid_property = property >= SYS_RAINFALL .and. property <= SYS_STORAGE
        case default
            valid_property = .false.
        end select
    end function valid_property

    subroutine bind_swmmc_functions()
        !% Finds the helper functions in the EPA SWMM library that SWMM5+ has
        !% loaded, and the factors to the units of the input file.
        type(c_funptr) :: fp
        procedure(unit_factors_fn), pointer :: factors
        real(c_double) :: qcf, lcf, vcf
        swmmc_subcatch_values = c_null_funptr
        swmmc_subcatch_name = c_null_funptr
        to_length = 1.0d0
        to_flow = 1.0d0
        to_volume = 1.0d0
        if (.not. c_associated(c_lib%fileaddrx)) return
        swmmc_subcatch_values = c_symbol(c_lib%fileaddrx, 's5p_swmmc_subcatch_values' // c_null_char)
        swmmc_subcatch_name = c_symbol(c_lib%fileaddrx, 's5p_swmmc_subcatch_name' // c_null_char)
        fp = c_symbol(c_lib%fileaddrx, 's5p_swmmc_unit_factors' // c_null_char)
        if (c_associated(fp)) then
            call c_f_procpointer(fp, factors)
            if (factors(qcf, lcf, vcf) == 0) then
                to_flow = qcf / CF_TO_CM
                to_length = lcf / FT_TO_M
                to_volume = vcf / CF_TO_CM
            end if
        end if
    end subroutine bind_swmmc_functions

    integer function subcatch_values(property, values)
        !% A property of every subcatchment at the current time, from EPA SWMM.
        integer, intent(in) :: property
        real(8), intent(out) :: values(:)
        procedure(subcatch_values_fn), pointer :: fn
        integer(c_int) :: n
        values = 0.0d0
        subcatch_values = S5P_OK
        if (size(values) == 0) return
        if (.not. c_associated(swmmc_subcatch_values)) then
            subcatch_values = fail(S5P_ERR_STATE, 'subcatchment results are not available from the EPA SWMM library')
            return
        end if
        call c_f_procpointer(swmmc_subcatch_values, fn)
        n = fn(real(setting%Time%Now - setting%Time%Start, c_double), int(property, c_int), values, &
               int(size(values), c_int))
        if (n < 0) subcatch_values = fail(S5P_ERR_ARGUMENT, 'subcatchment results could not be read')
    end function subcatch_values

    real(8) function runoff_to_node(i)
        !% Runoff that subcatchments send to node i in this hydraulic step (SI).
        integer, intent(in) :: i
        integer :: mm
        runoff_to_node = 0.0d0
        if (.not. setting%Simulation%useHydrology) return
        if (.not. allocated(subcatchI)) return
        do mm = 1, setting%SWMMinput%N_subcatch
            if (subcatchI(mm, si_runoff_nodeIdx) == i) &
                runoff_to_node = runoff_to_node + subcatchR(mm, sr_RunOffRate_baseline)
        end do
    end function runoff_to_node

    logical function is_element_node(i)
        !% Junctions with three or more links and storage nodes are finite
        !% volumes; all other nodes are faces between volumes.
        integer, intent(in) :: i
        is_element_node = node%I(i, ni_node_type) == nJm .or. node%I(i, ni_node_type) == nStorage
    end function is_element_node

    real(8) function node_value(i, property)
        !% Node property in SI units. Volume nodes report their junction main
        !% element, and for the volume, like the SWMM5+ output, the sum over
        !% the junction main and its branches. Face nodes report the mean of
        !% the two sides of the face.
        integer, intent(in) :: i, property
        integer :: e, f, k, b
        real(8) :: q
        node_value = 0.0d0
        if (is_element_node(i)) then
            e = node%I(i, ni_elem_idx)
            if (e < 1) return
            select case (property)
            case (NODE_DEPTH)
                node_value = elemR(e, er_Depth)
            case (NODE_HEAD)
                node_value = elemR(e, er_Head)
                if (setting%Solver%SubtractReferenceHead) node_value = node_value + setting%Solver%ReferenceHead
            case (NODE_VOLUME)
                node_value = elemR(e, er_Volume) * real(max(1, elemI(e, ei_barrels)), 8)
                do k = 1, max_branch_per_node
                    b = e + k
                    if (elemYN(b, eYN_isDummy)) cycle
                    if (elemSI(b, esi_JB_Exists) /= oneI) cycle
                    node_value = node_value + elemR(b, er_Volume) * real(max(1, elemI(b, ei_barrels)), 8)
                end do
            case (NODE_LATERAL_INFLOW)
                node_value = elemR(e, er_FlowrateLateral)
            case (NODE_TOTAL_INFLOW)
                node_value = max(0.0d0, elemR(e, er_FlowrateLateral))
                do k = 1, max_branch_per_node
                    b = e + k
                    if (elemYN(b, eYN_isDummy)) cycle
                    if (elemSI(b, esi_JB_Exists) /= oneI) cycle
                    q = elemR(b, er_Flowrate) * real(max(1, elemI(b, ei_barrels)), 8)
                    if (elemSI(b, esi_JB_IsUpstream) == oneI) then
                        node_value = node_value + max(0.0d0, q)
                    else
                        node_value = node_value + max(0.0d0, -q)
                    end if
                end do
            case (NODE_FLOODING)
                select case (elemSI(e, esi_JM_OverflowType))
                case (OverflowWeir, OverflowOrifice, PondedWeir, PondedOrifice)
                    node_value = max(0.0d0, -elemSR(e, esr_JM_OverflowPondingRate))
                end select
            end select
        else
            f = node%I(i, ni_face_idx)
            if (f < 1) return
            select case (property)
            case (NODE_DEPTH)
                node_value = 0.5d0 * (faceR(f, fr_Depth_u) + faceR(f, fr_Depth_d))
            case (NODE_HEAD)
                node_value = 0.5d0 * (faceR(f, fr_Head_u) + faceR(f, fr_Head_d))
                if (setting%Solver%SubtractReferenceHead) node_value = node_value + setting%Solver%ReferenceHead
            case (NODE_LATERAL_INFLOW, NODE_TOTAL_INFLOW)
                !% --- external inflows (lateral, or the inflow boundary of an
                !%     upstream end) and runoff
                if (allocated(BC%flowI) .and. allocated(BC%flowR)) then
                    do b = 1, min(size(BC%flowI, 1), size(BC%flowR, 1))
                        if (BC%flowI(b, bi_node_idx) /= i) cycle
                        if (BC%flowI(b, bi_category) == BClat .or. BC%flowI(b, bi_category) == BCup) &
                            node_value = node_value + BC%flowR(b, br_value)
                    end do
                end if
                node_value = node_value + runoff_to_node(i)
                !% --- plus the flow through the face, except at an upstream end,
                !%     where that flow is the inflow boundary itself
                if (property == NODE_TOTAL_INFLOW) then
                    node_value = max(0.0d0, node_value)
                    if (node%I(i, ni_node_type) /= nBCup) node_value = node_value + abs(faceR(f, fr_Flowrate))
                end if
            end select
        end if
    end function node_value

    real(8) function link_value(i, property)
        !% Link property in SI units from the finite volumes of the link, as in
        !% the SWMM5+ output: averages of flow and area (all barrels), depth,
        !% velocity and capacity, and the sum of the volumes.
        integer, intent(in) :: i, property
        integer :: e, firstElem, lastElem, nElem
        logical :: isUp, isDn
        real(8) :: barrels, total
        link_value = 0.0d0
        firstElem = 0
        lastElem = -1
        nElem = 0
        isUp = .false.
        isDn = .false.
        call util_first_and_last_elem_of_link(i, firstElem, lastElem, nElem, isUp, isDn)
        if (firstElem < 1 .or. lastElem < firstElem) return
        total = 0.0d0
        do e = firstElem, lastElem
            barrels = real(max(1, elemI(e, ei_barrels)), 8)
            select case (property)
            case (LINK_FLOW)
                total = total + elemR(e, er_Flowrate) * barrels
            case (LINK_DEPTH)
                total = total + elemR(e, er_Depth)
            case (LINK_VELOCITY)
                total = total + elemR(e, er_Velocity)
            case (LINK_AREA)
                total = total + elemR(e, er_Area) * barrels
            case (LINK_VOLUME)
                total = total + elemR(e, er_Volume) * barrels
            case (LINK_CAPACITY)
                if (elemI(e, ei_elementType) == CC) then
                    if (elemR(e, er_FullArea) > 0.0d0) &
                        total = total + min(1.0d0, elemR(e, er_Area) / elemR(e, er_FullArea))
                else
                    total = total + elemR(e, er_Setting)
                end if
            end select
        end do
        if (property == LINK_VOLUME) then
            link_value = total
        else
            link_value = total / real(lastElem - firstElem + 1, 8)
        end if
    end function link_value

    real(8) function to_input_units(object, property, value)
        !% Converts a node or link value from SI to the units of the input file.
        integer, intent(in) :: object, property
        real(8), intent(in) :: value
        to_input_units = value
        select case (object)
        case (OBJ_NODE)
            select case (property)
            case (NODE_DEPTH, NODE_HEAD)
                to_input_units = value * to_length
            case (NODE_VOLUME)
                to_input_units = value * to_volume
            case default
                to_input_units = value * to_flow
            end select
        case (OBJ_LINK)
            select case (property)
            case (LINK_FLOW)
                to_input_units = value * to_flow
            case (LINK_DEPTH, LINK_VELOCITY)
                to_input_units = value * to_length
            case (LINK_AREA)
                to_input_units = value * to_length * to_length
            case (LINK_VOLUME)
                to_input_units = value * to_volume
            end select
        end select
    end function to_input_units

    integer function system_value(property, value)
        !% System-wide totals in the units of the input file.
        integer, intent(in) :: property
        real(8), intent(out) :: value
        real(8), allocatable :: x(:), area(:)
        integer :: i, n
        value = 0.0d0
        system_value = S5P_OK
        select case (property)
        case (SYS_RAINFALL, SYS_EVAPORATION, SYS_INFILTRATION, SYS_RUNOFF)
            n = setting%SWMMinput%N_subcatch
            if (n <= 0) return
            allocate (x(n), area(n))
            select case (property)
            case (SYS_RAINFALL)
                system_value = subcatch_values(SUB_RAINFALL, x)
            case (SYS_EVAPORATION)
                system_value = subcatch_values(SUB_EVAPORATION, x)
            case (SYS_INFILTRATION)
                system_value = subcatch_values(SUB_INFILTRATION, x)
            case default
                system_value = subcatch_values(SUB_RUNOFF, x)
            end select
            if (system_value /= S5P_OK) return
            if (property == SYS_RUNOFF) then
                value = sum(x)
            else
                system_value = subcatch_values(SUB_AREA, area)
                if (system_value /= S5P_OK) return
                if (sum(area) > 0.0d0) value = sum(x * area) / sum(area)
            end if
        case (SYS_LATERAL_INFLOW)
            do i = 1, setting%SWMMinput%N_node
                value = value + node_value(i, NODE_LATERAL_INFLOW)
            end do
            value = value * to_flow
        case (SYS_FLOODING)
            do i = 1, setting%SWMMinput%N_node
                value = value + node_value(i, NODE_FLOODING)
            end do
            value = value * to_flow
        case (SYS_OUTFLOW)
            do i = 1, setting%SWMMinput%N_node
                if (node%I(i, ni_node_type) == nBCdn) value = value + node_value(i, NODE_TOTAL_INFLOW)
            end do
            value = value * to_flow
        case (SYS_STORAGE)
            do i = 1, setting%SWMMinput%N_node
                value = value + node_value(i, NODE_VOLUME)
            end do
            do i = 1, setting%SWMMinput%N_link
                value = value + link_value(i, LINK_VOLUME)
            end do
            value = value * to_volume
        end select
    end function system_value

    integer function fill_values(object, property, out)
        !% A property of all objects of a type (arguments checked by the caller).
        integer, intent(in) :: object, property
        real(8), intent(out) :: out(:)
        integer :: i
        fill_values = S5P_OK
        select case (object)
        case (OBJ_NODE)
            do i = 1, size(out)
                out(i) = to_input_units(object, property, node_value(i, property))
            end do
        case (OBJ_LINK)
            do i = 1, size(out)
                out(i) = to_input_units(object, property, link_value(i, property))
            end do
        case (OBJ_SUBCATCH)
            fill_values = subcatch_values(property, out)
        case (OBJ_SYSTEM)
            fill_values = system_value(property, out(1))
        end select
    end function fill_values

    integer function check_query(object, property, where)
        integer, intent(in) :: object, property
        character(len=*), intent(in) :: where
        check_query = S5P_OK
        if (.not. values_available()) then
            check_query = fail(S5P_ERR_STATE, where // ': values exist from s5p_initialize until s5p_finalize')
        else if (object_count(object) < 0) then
            check_query = fail(S5P_ERR_ARGUMENT, where // ': unknown object type')
        else if (.not. valid_property(object, property)) then
            check_query = fail(S5P_ERR_ARGUMENT, where // ': unknown property')
        end if
    end function check_query

    !% --------------------------------------------------------------------
    !% Interface
    !% --------------------------------------------------------------------
    integer(c_int) function s5p_api_version() bind(C, name='s5p_api_version')
        s5p_api_version = 2
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
        capi_report_period = 0
        capi_step_mode = .false.
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

    integer(c_int) function s5p_set_report_callback(callback, user_data) &
        bind(C, name='s5p_set_report_callback')
        type(c_funptr), value :: callback
        type(c_ptr), value :: user_data
        capi_report_cb = callback
        capi_report_user = user_data
        s5p_set_report_callback = S5P_OK
    end function s5p_set_report_callback

    integer(c_int) function s5p_set_quiet(quiet) bind(C, name='s5p_set_quiet')
        integer(c_int), value :: quiet
        setting%Output%CommandLine%quietYN = (quiet /= 0)
        setting%Output%Verbose = (quiet == 0)
        s5p_set_quiet = S5P_OK
    end function s5p_set_quiet

    integer(c_int) function s5p_set_console(mode) bind(C, name='s5p_set_console')
        integer(c_int), value :: mode
        if (c_console_set_mode(mode) /= 0) then
            s5p_set_console = fail(S5P_ERR_ARGUMENT, 's5p_set_console: unknown mode')
        else
            s5p_set_console = S5P_OK
        end if
    end function s5p_set_console

    integer(c_int) function s5p_initialize() bind(C, name='s5p_initialize')
        if (state /= STATE_OPEN) then
            s5p_initialize = fail(S5P_ERR_STATE, 's5p_initialize: call s5p_open first')
            return
        end if
        call capi_console_capture()
        call initialize_toplevel()
        call bind_swmmc_functions()
        call capi_console_release()
        state = STATE_INITIALIZED
        s5p_initialize = S5P_OK
    end function s5p_initialize

    integer(c_int) function s5p_run() bind(C, name='s5p_run')
        if (state /= STATE_INITIALIZED) then
            s5p_run = fail(S5P_ERR_STATE, 's5p_run: call s5p_initialize first')
            return
        end if
        call capi_console_capture()
        capi_step_mode = .false.
        call timeloop_toplevel()
        !% --- the level SWMM5+ adds to its output when it finalizes
        if (.not. capi_cancelled) call capi_report(setting%Time%Now)
        call capi_console_release()
        state = STATE_RAN
        if (capi_cancelled) then
            s5p_run = fail(S5P_ERR_CANCELLED, 's5p_run: stopped by a callback')
        else
            s5p_run = S5P_OK
        end if
    end function s5p_run

    integer(c_int) function s5p_step(now_seconds) bind(C, name='s5p_step')
        type(c_ptr), value :: now_seconds
        real(c_double), pointer :: now
        logical :: finished
        if (capi_cancelled .and. (state == STATE_STEPPING .or. state == STATE_RAN)) then
            s5p_step = fail(S5P_ERR_CANCELLED, 's5p_step: stopped by a callback')
        else if (state == STATE_RAN) then
            s5p_step = S5P_END
        else if (state /= STATE_INITIALIZED .and. state /= STATE_STEPPING) then
            s5p_step = fail(S5P_ERR_STATE, 's5p_step: call s5p_initialize first')
            return
        else
            call capi_console_capture()
            if (state == STATE_INITIALIZED) then
                !% --- spin-up and loop set-up; returns before the time loop
                capi_step_mode = .true.
                call timeloop_toplevel()
                state = STATE_STEPPING
            end if
            call timeloop_capi_step(finished)
            if (capi_cancelled) then
                call timeloop_capi_finish()
                state = STATE_RAN
                s5p_step = fail(S5P_ERR_CANCELLED, 's5p_step: stopped by a callback')
            else if (finished) then
                call timeloop_capi_finish()
                !% --- the level SWMM5+ adds to its output when it finalizes
                call capi_report(setting%Time%Now)
                state = STATE_RAN
                s5p_step = S5P_END
            else
                s5p_step = S5P_OK
            end if
            call capi_console_release()
        end if
        if (c_associated(now_seconds)) then
            call c_f_pointer(now_seconds, now)
            now = setting%Time%Now
        end if
    end function s5p_step

    integer(c_int) function s5p_finalize() bind(C, name='s5p_finalize')
        if (state /= STATE_RAN .and. state /= STATE_STEPPING) then
            s5p_finalize = fail(S5P_ERR_STATE, 's5p_finalize: call s5p_run or s5p_step first')
            return
        end if
        call capi_console_capture()
        if (state == STATE_STEPPING) call timeloop_capi_finish()
        call finalize_toplevel()
        call capi_console_release()
        state = STATE_FINALIZED
        s5p_finalize = S5P_OK
    end function s5p_finalize

    integer(c_int) function s5p_close() bind(C, name='s5p_close')
        !% SWMM5+ keeps its data in module variables, so a second model cannot
        !% be opened in the same process; the state stays "closed for good".
        call capi_console_release()
        capi_active = .false.
        capi_progress_cb = c_null_funptr
        capi_progress_user = c_null_ptr
        capi_report_cb = c_null_funptr
        capi_report_user = c_null_ptr
        swmmc_subcatch_values = c_null_funptr
        swmmc_subcatch_name = c_null_funptr
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
        if (object_count(object) < 0) then
            s5p_get_count = fail(S5P_ERR_ARGUMENT, 's5p_get_count: unknown object type')
            return
        end if
        count = object_count(object)
        s5p_get_count = S5P_OK
    end function s5p_get_count

    integer(c_int) function s5p_get_name(object, index, buffer, length) bind(C, name='s5p_get_name')
        integer(c_int), value :: object, index
        type(c_ptr), value :: buffer
        integer(c_int), value :: length
        procedure(subcatch_name_fn), pointer :: fn
        character(kind=c_char), pointer :: out(:)
        integer :: i
        if (.not. values_available()) then
            s5p_get_name = fail(S5P_ERR_STATE, 's5p_get_name: names exist from s5p_initialize until s5p_finalize')
            return
        end if
        if (object_count(object) < 0) then
            s5p_get_name = fail(S5P_ERR_ARGUMENT, 's5p_get_name: unknown object type')
            return
        end if
        i = index + 1
        if (i < 1 .or. i > object_count(object)) then
            s5p_get_name = fail(S5P_ERR_ARGUMENT, 's5p_get_name: index out of range')
            return
        end if
        select case (object)
        case (OBJ_NODE)
            s5p_get_name = to_c(trim(node%Names(i)%str), buffer, length)
        case (OBJ_LINK)
            s5p_get_name = to_c(trim(link%Names(i)%str), buffer, length)
        case (OBJ_SUBCATCH)
            if (.not. c_associated(buffer) .or. length <= 0) then
                s5p_get_name = fail(S5P_ERR_ARGUMENT, 's5p_get_name: no buffer')
                return
            end if
            if (.not. c_associated(swmmc_subcatch_name)) then
                s5p_get_name = fail(S5P_ERR_STATE, 's5p_get_name: subcatchment names are not available')
                return
            end if
            call c_f_procpointer(swmmc_subcatch_name, fn)
            call c_f_pointer(buffer, out, [length])
            if (fn(int(index, c_int), out, length) /= 0) then
                s5p_get_name = fail(S5P_ERR_ARGUMENT, 's5p_get_name: subcatchment name not found')
            else
                s5p_get_name = S5P_OK
            end if
        case default
            s5p_get_name = to_c('System', buffer, length)
        end select
    end function s5p_get_name

    integer(c_int) function s5p_get_value(object, index, property, value) bind(C, name='s5p_get_value')
        integer(c_int), value :: object, index, property
        real(c_double), intent(out) :: value
        real(8), allocatable :: every(:)
        integer :: i, rc
        value = 0.0_c_double
        i = index + 1
        rc = check_query(object, property, 's5p_get_value')
        if (rc == S5P_OK) then
            if (i < 1 .or. i > object_count(object)) rc = fail(S5P_ERR_ARGUMENT, 's5p_get_value: index out of range')
        end if
        if (rc == S5P_OK) then
            select case (object)
            case (OBJ_NODE)
                value = to_input_units(object, property, node_value(i, property))
            case (OBJ_LINK)
                value = to_input_units(object, property, link_value(i, property))
            case default
                allocate (every(object_count(object)))
                rc = fill_values(object, property, every)
                value = every(i)
            end select
        end if
        s5p_get_value = rc
    end function s5p_get_value

    integer(c_int) function s5p_get_values(object, property, values, count) bind(C, name='s5p_get_values')
        integer(c_int), value :: object, property, count
        type(c_ptr), value :: values
        real(c_double), pointer :: out(:)
        integer :: n, rc
        rc = check_query(object, property, 's5p_get_values')
        if (rc == S5P_OK) then
            n = object_count(object)
            if (.not. c_associated(values) .or. count < n) then
                rc = fail(S5P_ERR_ARGUMENT, 's5p_get_values: the array is smaller than the number of objects')
            else if (n > 0) then
                call c_f_pointer(values, out, [n])
                rc = fill_values(object, property, out)
            end if
        end if
        s5p_get_values = rc
    end function s5p_get_values

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
