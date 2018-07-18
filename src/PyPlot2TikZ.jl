__precompile__(true)
module PyPlot2TikZ
global OUTPUTGRAPHICS=true
global OUTPUTRASTER=true
output_graphics_on()= (global OUTPUTGRAPHICS=true)
output_graphics_off()=(global OUTPUTGRAPHICS=false)
output_graphics(f::Bool) = (global OUTPUTGRAPHICS = f)
output_graphics() = (return OUTPUTGRAPHICS)
output_raster_graphics(f::Bool) = (global OUTPUTRASTER = f)
output_raster_graphics() = (return OUTPUTRASTER)
# include("PyPlot/PyPlot.jl") # introduces (modified) PyPlot as a submodule to PyPlot2TikZ

# function __init__()
#   # FIXME This will throw-up a warning message because it overwrites the definition(s) of
#   #       Base.close from PyPlot.jl. Since we want to overwrite the definition, let's do
#   #       something dangerous and temporarily redirect stderr
#   stderr_orig=STDERR
#   rd, wr = redirect_stderr()
#   function Base.close(w::Integer)
#       delete!(_tikzFIGS,w)
#       ### following modified from PyPlot.close
#       pop!(PyPlot.withfig_fignums, w, w)
#       PyCall.pycall(PyPlot.plt["close"], PyCall.PyAny, w)
#       ###
#       reconcilefigures()
#   end
#   redirect_stderr(stderr_orig)
#   close(wr)
#   caught=split(readstring(rd)) # had been split(readall(rd))
#   # The method is now overwritten wherever it is included instead of in PyPlot2TikZ because __init__() is executed at runtime
#   normal=split("WARNING: Method definition close(Integer) in module PyPlot at .../PyPlot.jl overwritten in module XXX at .../PyPlotExtension.jl")
#   whatwecareabout=[1:6;8;10:12;14]
#   all(caught[whatwecareabout].==normal[whatwecareabout])||warn(join(caught[2:end]," "))
# end

import PyCall # to access all PyCall functions as PyCall.*
import PyPlot # to access all PyPlot functions as PyPlot.*
import PyPlot: setp

using LaTeXStrings
export LaTeXString, latexstring, @L_str, @L_mstr

using ColorTypes,Colors # for dealing with pcolor/other-colored plots
using FileIO # for output of PNG pcolor plots (when possible)
import FileIO: save # otherwise, problems

null=Nullable{Union{}}() # a definition that won"t be required in the future, maybe.

# PyPlot does not define getp which we need to find the properties of an object
getp(o...;k...)=PyCall.pycall(PyPlot.plt[:getp],PyCall.PyAny,o...;k...)
# If the rest of this package works, one should extend PyPlot by adding getp and :getp in the appropriate places


# A simple ultility to check if two arrays/numbers are compatibly sized
compatible{T<:Any,R<:Any,N}(a::Array{T,N},b::Array{R,N})=size(a)==size(b) # equal rank arrays, check sizes
compatible{T<:Any,R<:Any,N,M}(a::Array{T,N},b::Array{R,M})=false          # unequal rank arrays => false
compatible(a,b)=true                                                      # non-arrays => true
# A simple utility to check if a string (or an array or strings) represents one (many) simple number(s)
isnumeric(s::AbstractString)=isempty(s)||isa(parse(replace(s,"−","-")),Number) # isnumeric("3.0")≡true, isnumeric("pi")≡false
isnumeric{T<:Any}(s::Array{T})=map(isnumeric,s)


export figure,axis,axes,plot,fill_between,errorbar,text,text3D,subplot,subplots,legend
export pcolor,pcolormesh,colorbar,plot3D,contour,contourf
export gcf,gca,clf,cla,setp,getp,grid,title,xlabel,xlim,xscale,xticks,ylabel,ylim,yscale,yticks
export Figure,Axis,InAxis
export Plot,Fill2D
export Errorbar,Errorbar2D
export Annotation,Text2D,Text3D
import Base: show,write
export save,showpdf,figurestring
include("BBox.jl")
include("InAxis.jl")
include("Axis.jl")            # include InAxis before, since Axis contains an InAxis field
include("Figure.jl")          # include Axis before, since Figure contains an Axis field
include("PyPlotExtension.jl") # defines functions that act on new types and their PyPlot objects
include("Parse.jl")
include("Colors.jl")
include("PColor.jl")
include("Collect.jl")
include("TextNumbers.jl")
include("Output.jl") # was named "Output_tablesfirst.jl"
end # module
