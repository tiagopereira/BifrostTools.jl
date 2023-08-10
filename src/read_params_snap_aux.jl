

function br_read_params(file_name::String)
  f = open(file_name, "r")
  l = readlines(f)
  l = [strip(i) for i in l if !isempty(strip(i))] # remove empty str
  l = [strip(i) for i in l if (i[1] != ';')]
  l = [replace(i, "'" => "\"") for i in l]
  l = [split(i, '=') for i in l] # remove lines which starts with ';'
  params = Dict{String,Any}()
  for x in l
    key = strip(x[1])
    val = eval(Meta.parse(x[2]))
    params[key] = val
  end
  return params
end

"""
    get_snapsize_and_numvars(
        params::Dict{String,Any},
    )
Returns snapsize (nx, ny, nz), number of primary variables and number of
auxiliary variables, given the snapshot-parameters.
"""
function get_snapsize_and_numvars(
    params::Dict{String,Any},
    )
    if params["do_mhd"] == 1
        numvars = 8
    else
        numvars = 5
    end
    numauxvars = length(split(params["aux"]))
    snapsize = params["mx"], params["my"], params["mz"]
    return snapsize, numvars, numauxvars
end

"""
    br_load_snapdata(
        expname::String,
        snap   ::Int,
        expdir ::String,
        )

Reads Bifrost *.snap binary file as an Array in dimension: (mx,my,mz,nvar).
Takes experiment name, experiment directory, and snap number as arguments.
Returns `snapdata` (the data) and `params` (the snap parameters).
Assumes single floating point precision by default.

Variables of `snapdata`:

        snapdata[:,:,:,1] : r, density
        snapdata[:,:,:,2] : px, x-component of momentum 
        snapdata[:,:,:,3] : py, y-component of momentum 
        snapdata[:,:,:,4] : pz, z-component of momentum 
        snapdata[:,:,:,5] : e, energy
    
        if params["do_mhd"] == 1 # numvars = 8, otherwise numvars = 5
            snapdata[:,:,:,6] : bx, x-component of magnetic field 
            snapdata[:,:,:,7] : by, y-component of magnetic field 
            snapdata[:,:,:,8] : bz, z-component of magnetic field 

Warning:
    variables in code units.ts
"""
function br_load_snapdata(
    expname  ::String,
    snap     ::Int,
    expdir   ::String,
    precision::DataType=Float32
    )
    datadims = 4 # 3 spatial dimensions and 1 variable dimension
    # Parse filenames
    basename = string(expdir, "/", expname, "_$snap")
    idl_filename = string(basename, ".idl")
    snap_filename = string(basename, ".snap")
    params = br_read_params(idl_filename)
    
    snapsize, numvars, _ = get_snapsize_and_numvars(params)

    file = open(snap_filename)
    # Use Julia standard-library memory-mapping to extract file values
    snapdata = mmap(file, Array{precision, 4}, (snapsize..., numvars))
    close(file)
    return snapdata, params
end # function br_load_snapdata

"""
    br_load_snapdata(
        file_name::String,
        params   ::Dict{String,Any}
        )

Reads Bifrost *.snap binary file as an Array in dimension: (mx,my,mz,nvar).
Takes the snap-filename and its paramters as arguments. Returns `snapdata`
(the data). Assumes single floating point precision by default.

Variables of `snapdata`:

        snapdata[:,:,:,1] : r, density
        snapdata[:,:,:,2] : px, x-component of momentum 
        snapdata[:,:,:,3] : py, y-component of momentum 
        snapdata[:,:,:,4] : pz, z-component of momentum 
        snapdata[:,:,:,5] : e, energy
    
        if params["do_mhd"] == 1 # numvars = 8, otherwise numvars = 5
            snapdata[:,:,:,6] : bx, x-component of magnetic field 
            snapdata[:,:,:,7] : by, y-component of magnetic field 
            snapdata[:,:,:,8] : bz, z-component of magnetic field 

Warning:
    variables in code units.
"""
function br_load_snapdata(
    file_name::String,
    params   ::Dict{String,Any},
    precision::DataType=Float32
    )
    datadims = 4 # 3 spatial dimensions and 1 variable dimension
    
    snapsize, numvars, _ = get_snapsize_and_numvars(params)

    file = open(file_name)
    # Use Julia standard-library memory-mapping to extract file values
    snapdata = mmap(file, Array{precision, datadims}, (snapsize..., numvars))
    close(file)
    return snapdata
end # function br_load_snapdata

"""
    br_load_auxdata(
        file_name::String,
        params   ::Dict{String,Any}
    )
Reads Bifrost *.aux binary file using memory-mapping. The returned
`auxdata` array will have dimensions (mx,my,mz,nvars) where nvars is the
number of aux-variables. Assumes single floating point precision by default.
"""
function br_load_auxdata(
    file_name::String,
    params   ::Dict{String,Any},
    precision::DataType=Float32
    )
    datadims = 4
    snapsize, _, numauxvars = get_snapsize_and_numvars(params)
    if numauxvars == 0
        return
    else 
        file = open(file_name)
        # Use Julia standard-library memory-mapping to extract file values
        auxdata = mmap(file, Array{precision, datadims},
                       (snapsize..., numauxvars)
                       )
        close(file)
        return auxdata
    end
end # function br_load_auxdata

"""
    get_variable_offset_in_file(
        precision::DataType,
        snapsize::Tuple{Integer, Integer, Integer},
        varnr   ::Integer
        )
Given the precision and size of a snapshot, find the offset for reading the
variable with index `varnr` directly from file. Offset given in number of bytes.
"""
function get_variable_offset_in_file(
    precision::DataType,
    snapsize::Tuple{Integer, Integer, Integer},
    varnr   ::Integer
    )
    if precision == Float32
        bytes_per_value = 4
    elseif precision == Float64
        bytes_per_value = 8
    end 
    values_per_variable = snapsize[1]*snapsize[2]*snapsize[3]
    offset = bytes_per_value*values_per_variable*(varnr - 1)
    return offset
end

"""
    get_snapvarnr(
        variable::String,
        upperlimit::Integer=8
        )
Given a primary `variable` (in string format), return its index in a Bifrost
snapshot.
"""
function get_snapvarnr(
    variable::String,
    upperlimit::Integer=8
    )
    if variable == "r"
        varnr = 1
    elseif variable == "px"
        varnr = 2
    elseif variable == "py"
        varnr = 3
    elseif variable == "pz"
        varnr = 4
    elseif variable == "e"
        varnr = 5
    elseif variable == "bx"
        varnr = 6
    elseif variable == "by"
        varnr = 7
    elseif variable == "bz"
        varnr = 8
    else
        error("Variable name not known.")
    end
    # In case one tries to get magnetic field with do_mhd = false
    if varnr > upperlimit
        error("Variable number exceeding number of available variables.")
    end 
    return varnr
end # function find_snapvarnr

"""
    get_auxvarnr(
        params::Dict{String,Any},
        auxvar::String
        )
Given the snapshot `params` and an auxiliary variable (in string format), return
its index in the ".aux"-array.
"""
function get_auxvarnr(
    params::Dict{String,Any},
    auxvar::String
    )
    indexes = findall(x -> x == auxvar, split(params["aux"]))
    if length(indexes) > 1
        error("Multiple matches for given aux variable name.")
    elseif length(indexes) == 0
        error("Auxiliary variable not found in file.")
    end
    return indexes[1]
end

"""
    br_load_snapvariable(
        file_name::String,
        params   ::Dict{String,Any},
        variable ::String,
        precision::DataType=Float32
        )
Reads a single `variable` of the Bifrost snapshot `file_name`.
Assumes single floating point precision as default.
The available variables are: 
    "r":  density
    "px": x-component of momentum
    "py": y-component of momentum
    "pz": z-component of momentum
    "e":  energy

   if params["do_mhd"] == true
    "bx": x-component of magnetic field
    "by": y-component of magnetic field
    "bz": z-component of magnetic field
"""
function br_load_snapvariable(
    file_name::String,
    params   ::Dict{String,Any},
    variable ::String,
    precision::DataType=Float32
    )
    datadims = 3 # 3 spatial dimensions and 1 variable dimension

    snapsize, numvars = get_snapsize_and_numvars(params)
    # Get variable number/position in snapdata from argument.
    varnr = get_snapvarnr(variable)

    # Calculate offset in file
    offset = get_variable_offset_in_file(precision, snapsize, varnr)

    file = open(file_name)
    # Use Julia standard-library memory-mapping to extract file values
    snapvariable = mmap(file, Array{precision, datadims}, snapsize, offset)
    close(file)
    return snapvariable
end # function br_load_snapvariable

"""
    br_load_snapvariable(
        expname ::String,
        snap    ::Vector{T} where {T<:Integer},
        expdir  ::String,
        variable::String,
        precision::DataType=Float32
        )
Reads a single primary `variable` of one or multiple Bifrost snapshots.
Takes the snapshot-numbers in the vector `snap`.
Assumes single floating point precision as default.
The available variables are: 
    "r":  density
    "px": x-component of momentum
    "py": y-component of momentum
    "pz": z-component of momentum
    "e":  energy

   if params["do_mhd"] == true
    "bx": x-component of magnetic field
    "by": y-component of magnetic field
    "bz": z-component of magnetic field
"""
function br_load_snapvariable(
    expname ::String,
    snap    ::Vector{T} where {T<:Integer},
    expdir  ::String,
    variable::String,
    precision::DataType=Float32
    )
    datadims = 3 # 3 spatial dimensions and 1 variable dimension

    # Parse filenames
    basename = string(expdir, "/", expname, "_$(snap[1])")
    idl_filename  = string(basename, ".idl")
    params = br_read_params(idl_filename)

    snapsize, numvars = get_snapsize_and_numvars(params)

    # Get variable number/position in snapdata from argument.
    varnr = get_snapvarnr(variable)

    # Calculate offset in file
    offset = get_variable_offset_in_file(precision, snapsize, varnr)

    # Loop through all snapshots and load variable
    numsnaps = length(snap)
    snapvariable = zeros(precision, snapsize..., numsnaps)
    for i = 1:numsnaps
        isnap = "_$(snap[i])"
        basename = string(expdir, "/", expname, isnap)
        snap_filename = string(basename, ".snap")
        file = open(snap_filename)
        # Use Julia standard-library memory-mapping to extract file values
        snapvariable[:,:,:,i] = mmap(file,
                                     Array{precision, datadims},
                                     snapsize,
                                     offset)
        close(file)
    end
    return snapvariable
end # function br_load_snapvariable

"""
    br_load_auxvariable(
        file_name::String,
        params   ::Dict{String,Any},
        auxvar   ::String,
        precision::DataType=Float32
        )
Reads a single auxiliary variable from a Bifrost ".aux"-file `file_name`. The
snapshot parameters must be given together with a string for the aux-variable,
`auxvar`. Assumes single floating point precision as default.
"""
function br_load_auxvariable(
    file_name::String,
    params   ::Dict{String,Any},
    auxvar   ::String,
    precision::DataType=Float32
    )
    datadims = 3
    snapsize, _, numauxvars = get_snapsize_and_numvars(params)
    auxvarnr = get_auxvarnr(params, auxvar)
    # Load file and auxvariable
    file = open(file_name)
    offset = get_variable_offset_in_file(precision, snapsize, auxvarnr)
    # Use Julia standard-library memory-mapping to extract file values
    auxdata = mmap(file, Array{precision, datadims}, snapsize, offset)
    close(file)
    return auxdata
end # function br_load_auxdata

"""
    br_load_auxvariable(
        expname ::String,
        snap    ::Vector{T} where {T<:Integer},
        expdir  ::String,
        auxvar  ::String,
        precision::DataType=Float32
        )
Reads a single axiliary variable (`auxvar`) of one or multiple Bifrost
snapshots. Takes the snapshot-numbers in the vector `snap`.
Assumes single floating point precision as default.
"""
function br_load_auxvariable(
    expname ::String,
    snap    ::Vector{T} where {T<:Integer},
    expdir  ::String,
    auxvar  ::String,
    precision::DataType=Float32
    )
    datadims = 3

    # Parse filenames
    basename = string(expdir, "/", expname, "_$(snap[1])")
    idl_filename  = string(basename, ".idl")
    params = br_read_params(idl_filename)

    snapsize, _, numauxvars = get_snapsize_and_numvars(params)
    auxvarnr = get_auxvarnr(params, auxvar)
    # Calculate offset in file
    offset = get_variable_offset_in_file(precision, snapsize, auxvarnr)

    # Loop through all snapshots and load variable
    numsnaps = length(snap)
    auxvariable = zeros(precision, snapsize..., numsnaps)
    for i = 1:numsnaps
        isnap = "_$(snap[i])"
        basename = string(expdir, "/", expname, isnap)
        aux_filename = string(basename, ".aux")
        file = open(aux_filename)
        # Use Julia standard-library memory-mapping to extract file values
        auxvariable[:,:,:,i] = mmap(file,
                                    Array{precision, datadims},
                                    snapsize,
                                    offset)
        close(file)
    end
    return auxvariable
end

