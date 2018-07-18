# extend the PyPlot functions to act on InAxis, Axis, and Figure types
for f in (:setp,:getp)
    for t in (:InAxis,:Axis,:Figure)
        @eval $f(a::$t,o...;k...)=$f(a.obj,o...;k...)
    end
end
for f in (:grid,:title,:xlabel,:xlim,:xscale,:xticks,:ylabel,:ylim,:yscale,:yticks)
    @eval import PyPlot: $f
    @eval $f(a::Axis,o...;k...)=$f(a.obj,o...;k...)
end



global _tikzFIGS=Dict{Integer,Figure}(); # Global variable necessary for gcf to work
function reconcilefigures()
    # PyPlot.jl relies on matplotlib to keep track of open figures.
    # There doesn't appear to be a way to hook-into a figure-close function to
    # force removal of a figure from _tikzFIGS.
    # If we don't reconcile the matplotlib open figures against _tikzFIGS
    # we could end up accessing freed memory, which would be bad.
    # This function performs the reconcilliation
    pfnos=PyPlot.get_fignums()
    isempty(pfnos)||(pcfno=PyPlot.gcf()[:number]) # we'll need to reset the current figure number!
    for f in pfnos
        haskey(_tikzFIGS,f) || ( _tikzFIGS[f]=Figure(PyPlot.figure(f)) ) # add the figure to our list if we're missing it
        if _tikzFIGS[f].obj != PyPlot.figure(f) # we closed the figure and PyPlot opened a new one with the same number
            _tikzFIGS[f]=Figure(PyPlot.figure(f)) # so reset the Figure object
            #warn("Figure objects don't match for figure $(f)!")
        end
    end
    isempty(pfnos)|| PyPlot.figure(pcfno) # reset the selected figure to avoid strangeness
    tfnos=sort(collect(keys(_tikzFIGS)))
    if !compatible(pfnos,tfnos)||!all(tfnos.==pfnos)
        for tf in keys(_tikzFIGS)
            any(pfnos.==tf)||( delete!(_tikzFIGS,tf) )
        end
    end
end
function isopen(f::Figure)
    # ensure our figure list matches the open figures
    reconcilefigures()
    # if the passed figure is in the updated list, it's open
    for (n,x) in _tikzFIGS; x==f && (return true); end
    # otherwise it's closed
    return false
end
function gcf()
    cf=PyPlot.gcf() # use the PyPlot gcf to ensure we pick the most-recently active figure window
    reconcilefigures()
    isempty(_tikzFIGS) && (return figure() )
    for (k,v) in _tikzFIGS; v.obj==cf && ( return v ); end
    warn("This statement should be unreachable. Something has gone wrong.")
end
function gca()
    fig=gcf()
    isempty(fig.children) && ( return axes() )
    ca=PyPlot.gca() # use the PyPlot gca to ensure we pick the right one
    for a in fig.children; a.obj==ca && ( return a ); end
end

figure(fig::Figure)=figure(fig.obj[:number])
function figure(figno::Integer)
    haskey(_tikzFIGS,figno)||( _tikzFIGS[figno]=Figure(figno) )
    PyPlot.figure(figno) # force the passed figure number to be the current figure
    return _tikzFIGS[figno] # return the figure object
end
function figure()
    reconcilefigures() # make sure our list of figures matches matplotlib.pyplot's
    isempty(_tikzFIGS) && (return figure(1)) # shortcut in the case of no existing figures
    fignos=sort(collect(keys(_tikzFIGS))) # all figure numbers
    missing=findfirst(fignos.!=1:length(fignos)) # e.g., [1,2,4,100].!=[1,2,3,4] returns [false,false,true,true]
    return figure(missing>0?missing:length(fignos)+1)
end
# there are three forms of PyPlot.axes
# one which takes an axis object and sets it as the current axis
# this requires looking through all figures and their axes to find the right one
function axes(axis::Axis)
    found=false
    for (figno,fig) in _tikzFIGS
        for a in fig.children;
            a.obj==axis.obj && (PyPlot.axes(a.obj);found=true;break)
        end
        found&&(break)
    end
end
# and two which create new axis objects (let the Axis constructor handle that)
axes{T<:Real}(pos::Vector{T})=( fig=gcf(); push!(fig.children,Axis(pos)) ) # pos is a normalized position within the figure pane
# without arguments axes kills all existing axes in the figure and creates a new default axis
function axes()
    fig=gcf()
    fig.children=[Axis()]
    #push!(fig.children,Axis())
    return fig.children[end]
end
# let's add our own extra forms:
axes(fig::Figure)=isempty(fig.children)?push!(fig.children,Axis()):fig.children[end]

function axis{T<:Real}(lims::Vector{T}=[0,1,0,1])
    # if no axis exists in the current figure, create one -- otherwise return the current axis
    # here we depart from PyPlot functionality which returns the axis limits, not the axis object
    axs=gca()
    setp(axs;xlim=lims[1:2],ylim=lims[3:4])
    return [getp(axs,:xlim)...;getp(axs,:ylim)...]
end


# figure closing. XXX close(Integer) moved to __init__()
Base.close(f::Figure) = (close(f.obj[:number]);reconcilefigures())
function Base.close(w::Symbol)
    if :all==w
        global _tikzFIGS=Dict{Integer,Figure}()
        ### following modified from PyPlot.close
        PyCall.pycall(PyPlot.plt["close"], PyCall.PyAny, w)
        ###
        reconcilefigures()
    end
end
Base.close(w::AbstractString)=close(Symbol(w))



# axis and figure clearing
cla()=(cf=gcf(); pos=findfirst(cf.children.==gca()); PyPlot.cla(); cf.children[pos].children=Array{InAxis}(0);)
clf()=(cf=gcf(); PyPlot.clf(); cf.children=Array{Axis}(0); )




# subplot is like MATLAB's subplot and returns an axis with size smaller than a whole figure
# we need to ensure that any time an axis is created, that it gets added to the figure object children list
function subplot(o...;k...)
    fig=gcf() # the PyPlot2TikZ Figure object
    push!(fig.children,Axis(PyPlot.subplot(o...;k...))) # hope that the new subplot doesn't kill existing axes
    return fig.children[end]
end

gridname(i::Integer,j::Integer)=@sprintf("ax%d_%d",j,i)
function gridanchor(i::Integer,j::Integer,x::Bool,y::Bool)
    1==i==j && ( return Nullable{Anchor}() )
    if x&&y
        anc="north west"
    elseif x
        anc=1==j?"left of north west":"north"
    elseif y
        anc=1==i?"above north west":"west"
    else
        anc="outer north west"
    end
    return Nullable(Anchor(anc))
end
function gridat(i::Integer,j::Integer,x::Bool,y::Bool)
    1==i==j && ( return Nullable{At}() )
    if !xor(x,y)||x # (x,y) = (true,true), (false,false) or (true,false)
        who=1==j?gridname(i-1,j):gridname(i,j-1)
    else # (false,true)
        who=1==i?gridname(i,j-1):gridname(i-1,j)
    end
    if !xor(x,y)
        anc=1==j?"north east":"south west"
    elseif x
        anc=1==j?"right of north east":"south"
    elseif y
        anc=1==i?"below south west":"east"
    end
    !x&&!y && (anc="outer "*anc) # prepend "outer" for no-shared-axes
    return Nullable(At(who,anc))
end
function gridextraoptions(imo::Integer,vmj::Integer,x::Bool,y::Bool)
    opt=["scale only axis"]
    0<vmj && x && push!(opt,"xticklabels={}")
    0<imo && y && push!(opt,"yticklabels={}")
    return opt
end


# Another useful matplotlib function is `subplots` which sets up an array of axes objects in
# a newly created figure.
function subplots(vert::Integer,horz::Integer;sharex=false,sharey=false,k...)
    (1>vert||1>horz)&&(error("subplots: both size specifications must be positive and finite."))
    # PyPlot will add a new figure when subplots is called, to know which number is added
    # we must first capture the list of open figures
    before_figlist=PyPlot.get_fignums()
    (pf,paxs)=PyPlot.subplots(vert,horz;sharex=sharex,sharey=sharey,k...)
    # and then, after calling subplots, get the updated list
    after_figlist=PyPlot.get_fignums()
    figno=after_figlist[findfirst(map(x->all(x.!=before_figlist),after_figlist))]
    fig=Figure(pf) #create a PyPlot2TikZ figure
    _tikzFIGS[figno]=fig
    # add in the axes, including names, anchors, and at information
    isa(sharex,Bool)||(sharex="col"==sharex)
    isa(sharey,Bool)||(sharey="row"==sharey)
    sx=sharex; sy=sharey
    hf=horz>1; vf=vert>1
    if hf||vf
        if hf&&vf
            ax=Array{Axis}(horz,vert)
            for i=1:horz,j=1:vert
                ax[i,j]=Axis(paxs[j,i],name=Nullable(gridname(i,j)),anchor=gridanchor(i,j,sx,sy),at=gridat(i,j,sx,sy),extraaxisoptions=gridextraoptions(i-1,vert-j,sx,sy))
            end
        elseif hf # vert=1
            ax=Array{Axis}(horz)
            for i=1:horz
                ax[i]=Axis(paxs[i],name=Nullable(gridname(i,1)),anchor=gridanchor(i,1,sx,sy),at=gridat(i,1,sx,sy),extraaxisoptions=gridextraoptions(i-1,0,sx,sy))
            end
        else # horz=1
            ax=Array{Axis}(vert)
            for j=1:vert
                ax[j]=Axis(paxs[j],name=Nullable(gridname(1,j)),anchor=gridanchor(1,j,sx,sy),at=gridat(1,j,sx,sy),extraaxisoptions=gridextraoptions(0,vert-j,sx,sy))
            end
        end
        axs=ax[:]
    else
        ax=Axis(paxs)
        axs=[ax]
    end
    fig.children=axs
    return (fig,ax)
end



# We need to also extend legend. FIXME configure this to actually do something for the figure/axis legend
function legend{T<:InAxis}(v::Array{T},o...;k...)
    objs=map(x->x.obj,v)
    PyPlot.legend(objs,o...;k...)
end
legend(o...;k...)=PyPlot.legend(o...;k...) # TODO FIXME XXX this punt is bad form!

#FIXME some more hackery
function colorbar{T<:InAxis}(a::T,o...;k...)
    PyPlot.colorbar(a.obj,o...;k...)
end
colorbar(o...;k...)=PyPlot.colorbar(o...;k...)
