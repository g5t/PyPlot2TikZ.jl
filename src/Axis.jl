prepend{T<:AbstractString}(a::String,b::Array{T})=map(x->a*x,b)
has{T<:AbstractString}(a::Array{T},b::String)=a[map(x->contains(x,b),a)]
# The anchor is a tikz/pgf positioning mechanism. pgfplots supports 35 anchor
# positions around each axis.
function validateAnchor(a::String)
    # the valid PGFplots anchors are listed on Page 314 of pgfplots.pdf
    local inner=["north west","north","north east","west","center","east","south west","south","south east"]
    local outer=prepend("outer ",inner)
    local mixed=[prepend("above ",has(inner,"north")); prepend("left of ",has(inner,"west")); prepend("right of ",has(inner,"east")); prepend("below ",has(inner,"south"))]
    local origin=["above origin","left of origin","origin","right of origin","below origin"]
    local validanchors=[inner;outer;mixed;origin]
    local match=findfirst(lowercase(a).==validanchors)
    return match>0 ? validanchors[match] : validanchors[1]
end
#The Anchor type is immutable since it must be validated against the 35-defined anchors.
immutable Anchor
    anchor::String
    Anchor(a::String)=new(validateAnchor(a))
end


showanchor(io::IO,an::Anchor,compact::Bool=false)=compact?Base.print(io,an.anchor):Base.print(io,an.anchor)
Base.show(io::IO,an::Anchor)=showanchor(io,an,false)
Base.showcompact(io::IO,an::Anchor)=showanchor(io,an,true)

# The at key of a pgfplot axis allows for the positioning of the axis' anchor
# at a specified place. pgfplots is extremely flexible in this regard and
# allows for "absolute" (page-based) positioning, relative (other-axis-based)
# positioning, and calculations of positions that combine absolute and/or
# relative positioning with constants (via turing complete complexity?)
# As implemented in this module, only relative (calculation-free) positioning
# is supported, however one could extend the module if so desired.
# The typical syntax for the axis option is:
# at={reference_axis.reference_axis_anchor}, anchor=this_axis_anchor
# The At type holds the name and anchor-name of the reference object.
type At
    name::String
    anchor::Anchor
end
At(name::String,anchor::String="north west")=At(name,Anchor(anchor))
showat(io::IO,an::At,compact::Bool=false)=compact?Base.print(io,"(",an.name,".",an.anchor,")"):Base.print(io,"(",an.name,".",an.anchor,")")
Base.show(io::IO,an::At)=showat(io,an,false)
Base.showcompact(io::IO,an::At)=showat(io,an,true)

"""
The `Axis` object contains a `matplotlib` axis object (accessible through
`PyPlot`, which utilizes `PyCall`), a list of its `InAxis` object children,
a name `String` which can be `null`, an `Anchor` which can be `null`,
an `At` object for relative axis positioning which can be `null`, a `Dict`
of axis options, and a `Vector{String}` for user-defined extra axis options.

If `at` is defined, `anchor` should be as well.
The `options` field can be populated via a call to `pgfparse` and, possibly,
tweaked by hand. The `extraaxisoptions` field is reserved exclusively for
hand entry of options that will be inserted into the `pgfplots` axis options
list without error checking.
"""
type Axis
    #figure::Figure # the figure object to which this axis object belongs
    obj::PyCall.PyObject
    children::Vector{InAxis}
    name::Nullable{String} # name=$name -- allowing another object to refer to this one
    anchor::Nullable{Anchor} # anchor=$anchor,
    at::Nullable{At}
    options::Dict{String,Any}
    extraaxisoptions::Vector{String} # inserted as join(extraaxisoptions,",\n")
end
Axis(o::PyCall.PyObject;
     children::Vector{InAxis}=Array{InAxis}(0),
     name::Nullable{String}=Nullable{String}(),
     anchor::Nullable{Anchor}=Nullable{Anchor}(),
     at::Nullable{At}=Nullable{At}(),
     options::Dict{String,Any}=Dict{String,Any}(),
     extraaxisoptions::Vector{String}=Array{String}(0)
     )=Axis(o,children,name,anchor,at,options,extraaxisoptions)
Axis{T<:AbstractFloat}(pos::Vector{T};k...)=Axis(PyPlot.axes(pos);k...)
Axis(;k...)=Axis(PyPlot.axes();k...)

function showAxis(io::IO,a::Axis,compact::Bool=false)
  print(io,typeof(a))
  nc=length(a.children)
  nm=get(a.name,"")
  if nc > 0
    if compact
      print(io,"{")
      isempty(nm)||print(io,nm*":")
      print(io,"$nc}")
    else
      isempty(nm)||print(io," ",nm)
      print(" with $nc child"*(nc>1?"ren":""))
    end
  elseif !isempty(nm)
    if compact
      print(io,"{"*nm*"}")
    else
      print(io, nm)
    end
  end
end
Base.show(io::IO,a::Axis)=showAxis(io,a,false)
Base.showcompact(io::IO,a::Axis)=showAxis(io,a,true)
