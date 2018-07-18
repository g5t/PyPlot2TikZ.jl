# Functions to pull the color information from pcolor/pcolormesh
pcolor2pngdata(a::PColorMesh)=reshape_color(extract_color_2D(a.obj),a.x ,a.y ) # Who decided that pcolormesh
pcolor2pngdata(a::PColor)    =reshape_color(extract_color_2D(a.obj),a.x',a.y') # and pcolor should store their color data differently?
function extract_color_2D(o::PyPlot.PyObject)
    #isempty(getp(o,"edgecolor")) || warn("Specified edgecolor(s) which PyPlot2TikZ can not handle. Please extend.")
    fcmat = getp(o,"facecolor")
    @assert ndims(fcmat)==2
    cdim=size(fcmat,2)
    @assert 5>cdim>2 "Expected RGB or RGBA values in \"facecolor\" but got something with $cdim entries"
    cvec=[ RGBA(fcmat[i,:]...) for i=1:size(fcmat,1) ]
    return cvec
end
function extract_color_3D(o::PyPlot.PyObject)
    #isempty(getp(o,"edgecolor")) || warn("Specified edgecolor(s) which PyPlot2TikZ can not handle. Please extend.")
    fcvec = getp(o,"facecolor")
    @assert ndims(fcvec)==1
    cdim=length(fcvec[1])
    @assert all(map(length,fcvec).==cdim) "All facecolors are not of the the same type"
    @assert 5>cdim>2 "Expected RGB or RGBA values in \"facecolor\" but got something with $cdim entries"
    cvec=[ RGBA(x...) for x in fcvec ]
    return cvec
end
reshape_color(c::Vector,x::AbstractVector,y::AbstractVector)=reshape_color(c,length(c),length(x),length(y))
function reshape_color(c::Vector,x::AbstractArray{T,2},y::AbstractArray{T,2}) where T
    @assert size(x)==size(y)
    reshape_color(c,length(c),size(x)...)
end
reshape_color(c::Vector,z::AbstractArray{T,2}) where T = reshape_color(c,length(c),size(z)...)
function reshape_color(c::Vector,lc::Integer,lx::Integer,ly::Integer)
    lc > 0 || (return reshape(c,0,0)) # two checks to ensure we
    lc > 1 || (return reshape(c,1,1)) # don't end up with negative lengths
    lx*ly==lc && (return reshape(c,lx,ly))
    (lx-1)*(ly-1) == lc && (return flipdim(reshape(c,lx-1,ly-1),1))
    # pcolor and pcolormesh *should* only have as many colors as (lx-1)*(ly-1) or lx*ly
    # but it seems sometimes there is an extra value that getp returns
    reshape_color(c[1:lc-1],lc-1,lx,ly)
end

# A PColor object contains x and y values, with color information in the PyObject
# Typically the x and y values are monotonic but there is no such restriction.
# If they *are* monotonic, we can save the color data as a PNG and then
# load it into the pgfplot using "\addplot graphics [...]"
ismonotonic(a::PColor)=ismonotonic(a.x)&&ismonotonic(a.y)
ismonotonic(a::Range) = true # by definition
ismonotonic(v::AbstractVector{T}) where {T<:AbstractFloat} = std(diff(v)) < eps(T)
function ismonotonic(v::AbstractVector)
    d=diff(v); m=mean(d)
    sum(abs,d)==m*length(d)
end
function ismonotonic(v::AbstractArray{T,2}) where {T<:AbstractFloat}
    δ=eps(T)
    std(diff(v,1))<δ && std(diff(v,2))<δ # one is likely exactly zero
end
saddz(a,x,y)=0==sum(abs,diff(diff(a,x),y))
ismonotonic(v::AbstractArray{T,2}) where T = saddz(v,1,1)&&saddz(v,2,2)&&saddz(v,1,2)


function makepgfcolormap(cm::PyPlot.ColorMap)
    levels=0:cm[:N]-1 #
    colors=cm.(levels) # should return Array{NTuple{4,Float64},1}
    # there are additional colors in the map which can be
    # accessed with cm(cm[:_i_under]), cm(cm[:_i_over]) and cm(cm[:_i_bad]) but
    # unless if we figure out how to deal with under and over range values in
    # pgfplots this doesn't help much
    @assert all(5.>map(length,colors).>2) "ColorMap contains non-RGB/RGBA values?"
    pgfmap=join(["rgb=("*join(c[1:3],",")*")" for c in colors]," ") # the part that goes into \pgfplotsset{colormap={::NAME::}{::PGFMAP::}}
end

function isbrewercolormap(f::Figure,name::AbstractString)
    brewer=["BuGn","BuPu","GnBu","OrRd","PuBu","PuBuGn","PuRd","RdPu","YlGn",
            "YlGnBu","YlOrBr","YlOrRd","Blues","Greens","Greys","Oranges","Purples",
            "Reds","BrBG","PiYG","PRGn","RdGy","PuOr","RdBu","RdYlBu","RdYlGn","Spectral",
            "Accent","Dark2","Paired","Pasetel","Set1","Set3","Pastel2","Set2"]
    cblibrary="pgfplots.colorbrewer"
    if any(brewer.==name) # we need to ensure the pgfplots library colorbrewer is loaded
        any(f.tikzlibraries.==cblibrary)||push!(f.tikzlibraries,cblibrary)
        return true
    end
    return false
end
function isextrapgfcolormap(f::Figure,name::AbstractString)
    extras=["autumn","blend","bright","bone","cold","copper","copper2","earth",
            "hsv","hsv2","jet","pastel","pink","sepia","spring","summer","temp",
            "thermal","winter"]
    cmlibrary="pgfplots.colormaps"
    if any(extras.==name)
        any(f.tikzlibraries.==cmlibrary)||push!(f.tikzlibraries,cmlibrary)
        return true
    end
    return false
end

function getpgfcolormap(f::Figure,a::PColor)
    # pgfplots colormaps which do not require any additional loading
    mpl=Dict((("viridis","viridis"),("hot","hot2"),("gray","blackwhite"),("cool","cool"),("summer","greenyellow"),("autumn","redyellow")))
    cm=getp(a,:cmap)
    name=cm[:name]
    haskey(mpl,name) && (return mpl[name])
    isbrewercolormap(f,name) && (return name)
    # isextrapgfcolormap(f,name) && (return name) # at least "jet" from pgplots.colormaps does not work with lualatex
    # the colormap isn't predefined in PGF or ColorBrewer, so we can make our own.
    name=getpgfcolormap(f,name,makepgfcolormap(cm))
    return name
end
function getpgfcolormap(f::Figure,name::AbstractString,map::AbstractString)
    haskey(f.colormaps,name)&&f.colormaps[name]==map ? name : addpgfcolormap(f,name,map)
end
function addpgfcolormap(f::Figure,name::AbstractString,map::AbstractString)
    i=0; nn=name
    while haskey(f.colormaps,nn)
        f.colormaps[nn]==map && (return nn)
        nn=name*textnumber(i+=1)
    end
    # at this point there is no key `nn` in colormaps
    f.colormaps[nn]=map
    return nn
end

ndgrid(v::AbstractVector) = copy(v)
function ndgrid(v1::AbstractVector, v2::AbstractVector)
    m, n = length(v1), length(v2)
    v1 = reshape(v1, m, 1)
    v2 = reshape(v2, 1, n)
    (repmat(v1, 1, n), repmat(v2, m, 1))
end
function ndgrid_fill(a, v, s, snext)
    for j = 1:length(a)
        a[j] = v[div(rem(j-1, snext), s)+1]
    end
end
function ndgrid(vs::AbstractVector...)
    n = length(vs)
    sz = map(length, vs)
    out = ntuple(i->Array{eltype(vs[i])}(sz),n)
    s = 1
    for i=1:n
        a = out[i]::Array
        v = vs[i]
        snext = s*size(a,i)
        ndgrid_fill(a, v, s, snext)
        s = snext
    end
    out
end
ndgridvecs(vs::AbstractVector...)=map(vec,ndgrid(vs...))
