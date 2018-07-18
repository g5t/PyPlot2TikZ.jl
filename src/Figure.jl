
type Figure
    obj::PyPlot.Figure
    # size::Nullable{Vec{2}}
    size::Nullable{NTuple{2,Float64}}
    children::Vector{Axis} # objects which contain plotting information -- multiple axes can be arranged with names, nodes, and anchors
    latexpackages::Vector{String} # puts \usepackage{} entries before \begin{document}
    tikzlibraries::Vector{String} # puts \usetikzlibrary{} entries before \begin{tikzpicture}
    tikzsettings::Vector{String}  # puts \tikzset{} entries before \begin{tikzpicture}
    plotsettings::Vector{String}  # puts \pgfplotsset{} entries before \begin{tikzpicture}
    tikzstyles::Dict{String,Any} # inserted into tikzpicture options as "/$key/.style={$(join(value),",")},"
    plotstyles::Dict{String,Any} # inserted as "/pgfplots/$key/.style={$(join(value),",")},"
    graphicstyles::Dict{String,Any} # inserted as "/pgfplots/plot graphics/$key/.style={$(join(value),",")},"
    availcolors::Dict{String,Array{Float64,1}}
    extracolors::Dict{String,Array{Float64,1}}
    colormaps::Dict{String,String}
    outputloc::String
end
Figure(o::PyPlot.Figure;
       size::Nullable{NTuple{2,Float64}}=Nullable{NTuple{2,Float64}}(),
       children::Vector{Axis}=Array{Axis}(0),
       latexpackages::Vector{String}=["fontspec","pgfplots","pgfplotstable"], # include fontspec by default to support UTF-8 in lualatex
       tikzlibraries::Vector{String}=Array{String}(0),
       tikzsettings::Vector{String}=Array{String}(0),
       plotsettings::Vector{String}=["compat=newest"],
       tikzstyles::Dict{String,Any}=Dict{String,Any}(),
       plotstyles::Dict{String,Any}=Dict{String,Any}(),
       graphicstyles::Dict{String,Any}=Dict{String,Any}(),
       availcolors::Dict{String,Array{Float64,1}}=copy(xcolors),
       extracolors::Dict{String,Array{Float64,1}}=Dict{String,Array{Float64,1}}(),
       colormaps::Dict{String,String}=Dict{String,String}(),
       outputloc::String=""
       )=Figure(o,size,children,latexpackages,tikzlibraries,tikzsettings,plotsettings,tikzstyles,plotstyles,graphicstyles,availcolors,extracolors,colormaps,outputloc)
Figure(figno::Integer;k...)=Figure(PyPlot.figure(figno);k...)
Figure(;k...)=Figure(PyPlot.figure();k...)

function showFigure(io::IO,f::Figure,compact::Bool=false)
  print(io,typeof(f))
  nc=length(f.children)
  if nc > 0
    if compact
      print(io,"{$nc}")
    else
      print(io," with $nc child"*(nc>1?"ren":""))
    end
  end
end
Base.show(io::IO,f::Figure)=showFigure(io,f,false)
Base.showcompact(io::IO,f::Figure)=showFigure(io,f,true)
