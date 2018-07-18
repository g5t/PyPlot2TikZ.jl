# Especially in the case of errorbars, matplotlib does not keep all of the
# useful information for translating its plots into pgfplots format. For this
# reason it is worthwhile to create new types to hold the missing information
# in addition to the plot PyObject(s)
abstract type InAxis end
abstract type Plot <: InAxis end # Plot objects just need \addplot[options] coordinates/table
type Points2D{T<:Real} <: Plot
    x::AbstractArray{T,1}
    y::AbstractArray{T,1}
    obj::PyCall.PyObject
    options::Dict{String,Any}
end
type Points3D{T<:Real}<:Plot
    x::AbstractArray{T,1}
    y::AbstractArray{T,1}
    z::AbstractArray{T,1}
    obj::PyCall.PyObject
    options::Dict{String,Any}
end
type Fill2D{T<:Real} <: Plot
    x::AbstractArray{T,1}
    yl::AbstractArray{T,1}
    yu::AbstractArray{T,1}
    obj::Any
    options::Dict{String,Any}
end
abstract type ColoredSurfaces <: InAxis end
abstract type PColors{T,N} <: ColoredSurfaces end
type PColor{T<:Real,N}<:PColors{T,N}
    x::AbstractArray{T,N}
    y::AbstractArray{T,N}
    z::AbstractArray{T,2}
    obj::PyCall.PyObject
    options::Dict{String,Any}
end
type PColorMesh{T<:Real,N}<:PColors{T,N}
    x::AbstractArray{T,N}
    y::AbstractArray{T,N}
    z::AbstractArray{T,2}
    obj::PyCall.PyObject
    options::Dict{String,Any}
end
type Surf{T<:Real,N}<:ColoredSurfaces
    x::AbstractArray{T,N}
    y::AbstractArray{T,N}
    z::AbstractArray{T,2}
    obj::PyCall.PyObject
    options::Dict{String,Any}
end
type Contour{T<:Real,N}<:ColoredSurfaces
    x::AbstractArray{T,N}
    y::AbstractArray{T,N}
    z::AbstractArray{T,2}
    obj::PyCall.PyObject
    options::Dict{String,Any}
end
abstract type Errorbar <: InAxis end # objects which need \addplot[options] plot [errorbar options] coordinates/table
type Errorbar2D{T<:Real,N,M} <: Errorbar
    x::AbstractArray{T,1}
    dx::AbstractArray{T,N}
    y::AbstractArray{T,1}
    dy::AbstractArray{T,M}
    obj::Any
    options::Dict{String,Any}
end
# some functions to differentiate between symmetric/asymmetric errorbars in x and y
hasxerrorbars(a::Errorbar2D)=any(x->abs(x)>0, a.dx) # any(abs.(a.dx).>0)
hasyerrorbars(a::Errorbar2D)=any(x->abs(x)>0, a.dy) # any(abs.(a.dy).>0)
issymmetricx{T<:Real,M}(a::Errorbar2D{T,1,M})=true
issymmetricx{T<:Real,M}(a::Errorbar2D{T,2,M})=false
issymmetricy{T<:Real,N}(a::Errorbar2D{T,N,1})=true
issymmetricy{T<:Real,N}(a::Errorbar2D{T,N,2})=false

Base.isempty(a::Points2D)=0==length(a.x)||0==length(a.y)||all(isnan,a.x)||all(isnan,a.y)
Base.isempty(a::Points3D)=0==length(a.x)||0==length(a.y)||0==length(a.z)||all(isnan,a.x)||all(isnan,a.y)||all(isnan,a.z)
Base.isempty(a::Fill2D)  =0==length(a.x)||0==length(a.yu)||0==length(a.yl)||all(isnan,a.x)||all(isnan,a.yu)||all(isnan,a.yl)
Base.isempty(a::ColoredSurfaces)=0==length(a.x)||0==length(a.y)||0==length(a.z)||all(isnan,a.x)||all(isnan,a.y)||all(isnan,a.z)
Base.isempty(a::Errorbar2D)=0==length(a.x)||0==length(a.y)||all(isnan,a.x)||all(isnan,a.y)

# It may also prove useful to overload annotation commands:
abstract type Annotation <: InAxis end# objects which need \node[options] ...
type Text2D{T<:Real} <: Annotation # created by text(x,y,t;kwds)
    x::T
    y::T
    t::String
    obj::PyCall.PyObject
    options::Dict{String,Any}
end
# there's also PyPlot.text2D which appears to draw on 3D axes -- not sure if it should be implemented
type Text3D{T<:Real} <: Annotation # created by text3D(x,y,z,t;kwds)
    x::T
    y::T
    z::T
    t::String
    obj::PyCall.PyObject
    options::Dict{String,Any}
end

# for the above defined types, auto-populate an empty options Dict if it wasn't supplied
for p in (:Points2D,:Points3D,:Fill2D,:PColor,:PColorMesh,:Surf,:Contour,:Errorbar2D,:Text2D,:Text3D)
    @eval $p(o...;options::Dict{String,Any}=Dict{String,Any}())=$p(o...,options)
end

# PyPlot equivalent plotting routines, utilizing pyplot for live display
#plot{T<:Real}(x::AbstractArray{T,1},y::AbstractArray{T,1};k...)=push!(gca().children, Points2D{T}(x,y,PyPlot.plot(x,y;k...)))
#fill_between{T<:Real}(x::AbstractArray{T,1},yl::AbstractArray{T,1},yu::AbstractArray{T,1};k...)=push!(gca().children, Fill2D{T}(x,yl,yu,PyPlot.fill_between(x,yl,yu;k...)))
#errorbar{T<:Real,N,M}(x::AbstractArray{T,1},y::AbstractArray{T,1};xerr::Array{T,N}=0*x,yerr::Array{T,M}=0*y,k...)=push!(gca().children, Errorbar2D(x,xerr,y,yerr,PyPlot.errorbar(x,y;xerr=xerr,yerr=yerr,k...)))
#text{T<:Real}(x::T,y::T,t::String;k...)=push!(gca().children, Text2D(x,y,t,PyPlot.text(x,y,t;k...)))
#text3D{T<:Real}(x::T,y::T,z::T,t::String;k...)=push!(gca().children, Text2D(x,y,z,t,PyPlot.text(x,y,z,t;k...)))

# we must ensure there is a TikzPlots Axis *before* calling the PyPlot routine, so ca=gca() must be first
function plot(x::AbstractArray{T,1},y::AbstractArray{R,1};k...) where {T<:Real,R<:Real}
    (x,y)=promote(x,y)
    ca=gca()
    out=Points2D(x,y,PyPlot.plot(x,y;k...)[1]) # TODO implement plot(x1,y1,x2,y2,...) ?XXX?XXX?
    push!(ca.children,out)
    return out
end
function fill_between(x::AbstractArray{T,1},yl::AbstractArray{R,1},yu::AbstractArray{S,1};k...) where {T<:Real,R<:Real,S<:Real}
  (x,yl,yu)=promote(x,yl,yu)
    ca=gca()
    out=Fill2D(x,yl,yu,PyPlot.fill_between(x,yl,yu;k...))
    push!(ca.children, out)
    return out
end
function errorbar(x::AbstractArray{T,1},y::AbstractArray{R,1};xerr::AbstractArray{T,N}=0*x,yerr::AbstractArray{R,M}=0*y,k...) where {T<:Real,R<:Real,N,M}
  (x,y,xerr,yerr)=promote(x,y,xerr,yerr)
    ca=gca()
    out=Errorbar2D( x,xerr,y,yerr, PyPlot.errorbar(x,y;xerr=xerr,yerr=yerr,k...) )
    push!(ca.children, out)
    return out
end
function text(x::T,y::R,t::String;k...) where {T<:Real,R<:Real}
  (x,y)=promote(x,y)
    ca=gca()
    out=Text2D(x,y,t,PyPlot.text(x,y,t;k...))
    push!(ca.children, out)
    return out
end
function text3D(x::T,y::R,z::S,t::String;k...) where {T<:Real,R<:Real,S<:Real}
  (x,y,z)=promote(x,y,z)
    ca=gca()
    out=Text2D(x,y,z,t,PyPlot.text(x,y,z,t;k...))
    push!(ca.children, out)
    return out
end

function plot3D(x::AbstractArray{T,1},y::AbstractArray{R,1},z::AbstractArray{S,1};k...) where {T<:Real,R<:Real,S<:Real}
    (x,y,z)=promote(x,y,z)
    ca=gca()
    out=Plot3D(x,y,z,PyPlot.plot3D(x,y,z;k...))
    push!(ca.children,out)
    return out
end

function pcolormesh(x::AbstractArray{T,N},y::AbstractArray{R,N},z::AbstractArray{S,2};k...) where {T<:Real,R<:Real,S<:Real,N}
    if any(!isfinite,x)||any(!isfinite,y)
        #info("matplotlib.pyplot.pcolormesh can no longer handle NaN/Inf x,y values. Using pcolor instead.")
        return pcolor(x,y,z;k...)
    end
    (x,y,z)=promote(x,y,z)
    ca=gca()
    out=PColorMesh(x,y,z,PyPlot.pcolormesh(x,y,z;k...))
    push!(ca.children,out)
    return out
end
function pcolor(x::AbstractArray{T,N},y::AbstractArray{R,N},z::AbstractArray{S,2};k...) where {T<:Real,R<:Real,S<:Real,N}
    (x,y,z)=promote(x,y,z)
    ca=gca()
    out=PColor(x,y,z,PyPlot.pcolor(x,y,z;k...))
    push!(ca.children,out)
    return out
end
function surf(x::AbstractArray{T,N},y::AbstractArray{R,N},z::AbstractArray{S,2};k...) where {T<:Real,R<:Real,S<:Real,N}
  (x,y,z)=promote(x,y,z)
    ca=gca()
    out=Surf(x,y,z,PyPlot.surf(x,y,z;k...))
    push!(ca.children,out)
    return out
end
function contour(x::AbstractArray{T,N},y::AbstractArray{R,N},z::AbstractArray{S,2};k...) where {T<:Real,R<:Real,S<:Real,N}
  (x,y,z)=promote(x,y,z)
  ca=gca()
  out=Contour(x,y,z,PyPlot.contour(x,y,z;k...))
  push!(ca.children,out)
  return out
end
function contourf(x::AbstractArray{T,N},y::AbstractArray{R,N},z::AbstractArray{S,2};k...) where {T<:Real,R<:Real,S<:Real,N}
  (x,y,z)=promote(x,y,z)
  ca=gca()
  out=Contour(x,y,z,PyPlot.contourf(x,y,z;k...))
  push!(ca.children,out)
  return out
end

Base.getindex(a::Errorbar,i...)=Base.getindex(a.obj,i...)


function showInAxis(io::IO,a::Annotation,c::Bool=false)
  println(io,typeof(a))
end
function showInAxis(io::IO,a::InAxis,compact::Bool=false)
  print(io,typeof(a))
  npts=length(a.x) # all InAxis objects have a field x, but it only makes sense for non-Annotation types
  if npts>0
    if compact
      print(io,"{$npts}")
    else
      print(io," with $npts point"*(npts>1?"s":""))
    end
  end
end
Base.show(io::IO,a::InAxis)=showInAxis(io,a,false)
Base.showcompact(io::IO,a::InAxis)=showInAxis(io,a,true)
