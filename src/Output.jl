# We have functions to parse option Dict{String,Any} objects into tikz/pgfplots option style strings
# We now need functions that pull together the whole thing
#   a function to write the preamble (including required packages and libraries, plus possibly extra latex functions
#   a function to start and end the document, which calls:
#       a function to start and end the tikzpicture, defining the styles in its options, which calls:
#           a function which writes all axes and their options, which calls:
#               a function which writes each axis contents, which calls:
#                   one of a set of functions which writes the plot/annotation information

# Maybe this is worthwhile? (Modified from the TikZPictures.jl module)
function Base.show(io::IO, ::MIME"image/svg+xml", f::Figure)
    filename=Base.tempname()*".svg"
    save(f,filename) # should make only the file tmpname().svg (deleting intermediate files)
    s = String(read(filename))
    t = time_ns()::UInt64 # the time in nanoseconds (since [some-time] mod 5.8 years)
    s = replace(s, "glyph", "glyph-$t-")
    s = replace(s, "\"clip", "\"clip-$t-")
    s = replace(s, "#clip", "#clip-$t-")
    s = replace(s, "\"image", "\"image-$t-")
    s = replace(s, "#image", "#image-$t-")
    s = replace(s, "linearGradient id=\"linear", "linearGradient id=\"linear-$t-")
    s = replace(s, "#linear", "#linear-$t-")
    s = replace(s, "image id=\"", "image style=\"image-rendering: pixelated;\" id=\"")
    print(io, s)
    rm(filename)
end
function showpdf(f::Figure)
    filename=Base.tempname()*".pdf"
    save(f,filename)
    ret=success(`zathura $filename`)
    ret ? ( rm(filename) )  : error("Problem displaying $filename.")
end
function save(f::Figure,filename::String)
    (d,fn)=splitdir(filename)
    isempty(d) && (d=pwd();)
    if !isdir(d)
        try mkpath(d)
        catch prob
            if prob.prefix=="mkdir"&&prob.errnum==13
                error("The path specified in $filename must be accessible to ",ENV["USER"])
            else
                rethrow(prob)
            end
        end
    end
    #f.outputdir=d # we need to stash this in case we need to (directly) write PNGs

#    Base.iswritable(d)||(error("The location $d must be writable for ",ENV["USER"]," in order to produce output."))
    (bn,ext)=splitext(fn) # use the builtin split extension function; (basename,extension_including_dot)
    # if ".svg" == ext # temporary(?) workaround to SVG figures interpolating pixel data
    #     figure(f) # make sure the passed figure is the current figure for savefig
    #     PyPlot.savefig(filename)
    #     return
    # end
    if ".svg" == ext && output_raster_graphics()
        output_raster_graphics(false) # we can't use raster graphics with (eventual) SVG creation)
        pgfparse(f) # and as a result we have to re-parse the figure
        output_raster_graphics(true) # switch the flag back in case other output is desired
    end

    f.outputloc=bn # stash for potential use with png, dat, pdf subfiles
    # we need to write out the TeX file no matter what to avoid overloading the julia argument list for pipeline
    fid=open(joinpath(d,bn*".tex"),"w"); write(fid,f); close(fid)
    # If a tex file was requested, we're done so return
    ".tex"==ext && return
    # otherwise pipe the file contents to lualatex for processing
    finished=success(`lualatex --output-directory=$d --jobname=$bn $(joinpath(d,bn)).tex`);
    if !finished
        loglines=readlines(joinpath(d,bn*".log"))
        errllocs=find(map(x->ismatch(r"^!",x),loglines))
        errllocs=vec(errllocs.+[0,1]')
        errllocs=errllocs[errllocs.<=length(loglines)]::Array{eltype(errllocs)}
        print_with_color(:yellow,"Error with lualatex::\n",loglines[errllocs]...)
        return
    end
    # cairo_options=Dict(".ps"=>"-ps")
    cairo_options=Dict(".png"=>"-png -singlefile -transp",
                       ".jpg"=>"-jpeg -singlefile -transp",
                       ".tif"=>"-tiff -singlefile -transp",
                       ".ps" =>"-ps",
                       ".svg"=>"-svg")
                       # cairo can also produce eps files, but there seems to be a problem with their format.
    if haskey(cairo_options,ext)
        pdffile=joinpath(d,bn*".pdf")
        co=cairo_options[ext]
        # use pdftocairo to create the requested filetype
        #info("Will now run `pdftocairo $pdffile $(cairo_options[ext])`")
        finished=success(`pdftocairo $pdffile $co`)
        finished || warn("Failed to create $filename from $pdffile, with pdftocairo options $co")
    end
    # since we've gotten this far without running into errors, discard some files:
    rm(joinpath(d,bn*".log"))
    rm(joinpath(d,bn*".aux"))
    rm(joinpath(d,bn*".tex"))
    for i=1:_GRAPHIC_NUMBER_, x in (".png",".dat",".pdf")
        tmp = joinpath(d,bn*graphicnumberpad(i)*x)
        isfile(tmp) && rm(tmp)
    end
    ".pdf"==ext || (rm(joinpath(d,bn*".pdf"))) # and only keep the pdf if it was requested
    # finally, ensure that the requested file exists
    isfile(filename)||error("Something went wrong and $filename was not created!")
    return
end
function figurestring(f::Figure)
    io=IOBuffer();
    Base.write(io,f)
    return String(take!(io))
end
alloptionsempty(f::Figure)=all(map(x->isempty(x.options),f.children))||all(map(alloptionsempty,f.children))
alloptionsempty(a::Axis)=all(map(x->isempty(x.options),a.children))
global _TABLE_NUMBER_=0
#newtablename()="\\table"*text_number(global _TABLE_NUMBER_+=1)
function newtablename()
    global _TABLE_NUMBER_+=1
    gettablename()
end
gettablename()="\\table"*text_number(_TABLE_NUMBER_)
resettablename()=global _TABLE_NUMBER_=0
zeropad(a::Real,b::Int)= ( n=a>0?round(Int,floor(log10(a)))+1:1; b-=n; (b>0?"$("0"^b)":"")*"$a" )
graphicnumberpad(a::Real)=zeropad(a,3)
global _GRAPHIC_NUMBER_=0
function newgraphicnumber()
    global _GRAPHIC_NUMBER_+=1
    getgraphicnumber()
end
getgraphicnumber()  =graphicnumberpad(_GRAPHIC_NUMBER_)
resetgraphicnumber()=global _GRAPHIC_NUMBER_=0

function writecolors(io::IO,f::Figure)
    for (name,cv) in f.extracolors
        length(cv)==3 && ( println(io,"\\definecolor{",name,"}{rgb}{$(cv[1]),$(cv[2]),$(cv[3])}") )
        length(cv)==4 && ( println(io,"\\definecolor{",name,"}{cmyk}{$(cv[1]),$(cv[2]),$(cv[3]),$(cv[4])}") )
    end
end
function writeplotdata(io::IO,iotables::IO,f::Figure,ia::Text2D)
    println(io,"at (axis cs:",ia.x,",",ia.y,") {",ia.t,"};")
end
# TODO implement other annotation types
function writedatatable{A<:AbstractString,T<:Real}(io::IO,colnames::Vector{A},data::Matrix{T})
    println(io,"\t",join(colnames,"\t"))
    for i=1:size(data,1)
        println(io,"\t",join(data[i,:],"\t"))
    end
end
# function writepatchtable(io::IO,N::Integer,M::Integer,data::Matrix{T}) where T<:Real
#     ind=vcat(vec([sub2ind((N+1,M+1),[i;i+1;i+1;i],[j;j;j+1;j+1])' for i=1:N,j=1:M])...)
#     # now write actual data
#     for i=1:N*M
#         isfinite(data[i])&&println(io,"\t",join(ind[i,:],"\t"),"\t",data[i])
#     end
# end
function writepatchtable(io::IO,N::Integer,M::Integer,data::Matrix{T}) where T<:Real
    (dN,dM)=size(data)
    if N==dN+1 && M==dM+1
        ind=vcat(vec([sub2ind((N,M),[i;i+1;i+1;i],[j;j;j+1;j+1])' for i=1:dN,j=1:dM]-1)...)
        # now write actual data
        for i=1:dN*dM
            isfinite(data[i])&&println(io,"\t",join(ind[i,:],"\t"),"\t",data[i])
        end
    elseif N==dN && M==dM
        ind=vcat(vec([sub2ind((N,M),[i;i+1;i+1;i],[j;j;j+1;j+1])' for i=1:N-1,j=1:M-1]-1)...)
        # now write actual data
        for i=1:(N-1)*(M-1)
            idx=sub2ind((N,M),ind2sub((N-1,M-1),i)...)
            isfinite(data[idx])&&println(io,"\t",join(ind[i,:],"\t"),"\t",data[idx])
        end
    else
        error("PyPlot2TikZ.writepatchtable can not yet handle x,y of size ($N,$M) with z of size ($dN,$dM)")
    end
end
function cutoutnonfinite(ind::Matrix,x::Matrix,y::Matrix)
    badind = find(.!(isfinite.(vec(x)).&isfinite.(vec(y))))-1 # linear (zero-indexed) indicies with NaN/infinite x or y values
    badrow = vec(any(hcat([vec(any(ind.==j,2)) for j in badind]...),2))  # rows of the ind matrix containing these bad indicies
    #newind = ind[.!badrow,:] # just the rows without the bad indicies
    newind = copy(ind)
    for b in reverse(sort(badind)) # go from highest to lowest bad indicies
        newind[newind.>b]-=1 # subtract one from every index greater than the bad one
    end
    # construct # [...; xi1 xi2 xi3 xi4 yi1 yi2 yi3 yi4 zi; ...]
    allxy = hcat(x[ind+1],y[ind+1]) # +1 to get back to julia indexing
    badi = vec(any(.!isfinite,allxy,2)) # rows of ind, elements of z that shouldn't be output

    return (newind,badi)
end
function writepatchtable(io::IO,x::Matrix,y::Matrix,data::Matrix{T}) where T<:Real
    (N,M)=size(x)
    @assert size(y)==(N,M)
    (dN,dM)=size(data)
    if N==dN+1 && M==dM+1
        ind=vcat(vec([sub2ind((N,M),[i;i+1;i+1;i],[j;j;j+1;j+1])' for i=1:dN,j=1:dM]-1)...)
        outind,badi=cutoutnonfinite(ind,x,y)
        # now write actual data
        for i=1:dN*dM
            !badi[i]&&isfinite(data[i])&&println(io,"\t",join(outind[i,:],"\t"),"\t",data[i])
        end
    elseif N==dN && M==dM
        ind=vcat(vec([sub2ind((N,M),[i;i+1;i+1;i],[j;j;j+1;j+1])' for i=1:N-1,j=1:M-1]-1)...)
        outind,badi=cutoutnonfinite(ind,x,y)
        # now write actual data
        for i=1:(N-1)*(M-1)
            idx=sub2ind((N,M),ind2sub((N-1,M-1),i)...)
            !badi[i]&&isfinite(data[idx])&&println(io,"\t",join(outind[i,:],"\t"),"\t",data[idx])
        end
    else
        error("PyPlot2TikZ.writepatchtable can not yet handle x,y of size ($N,$M) with z of size ($dN,$dM)")
    end
end
function writeplotdata(io::IO,iotables::IO,f::Figure,ia::Points2D)
    # fieldnames are ia.x ia.y
    (all(isnan,ia.x)||all(isnan,ia.y))&&(return)
    tablename=newtablename()
    println(iotables,"\\pgfplotstableread{")
    writedatatable(iotables,["x","y"],hcat(ia.x,ia.y))
    println(iotables,"}{$tablename}")
    println(io,"table [x=x,y=y] {$tablename};")
end
function writeplotdata(io::IO,iotables::IO,f::Figure,ia::Fill2D)
    # fieldnames are ia.x, ia.yl, ia.yu
    (all(isnan,ia.x)||all(isnan,ia.yl)||all(isnan,ia.yu))&&(return)
    # the area which will be filled is defined by (ia.x,ia.yu) on the top and (ia.x,ia.yl) on the bottom
    tablename=newtablename()
    println(iotables,"\\pgfplotstableread{")
    writedatatable(iotables,["x","y"],hcat(vcat(ia.x,reverse(ia.x)),vcat(ia.yl,reverse(ia.yu))))
    println(iotables,"}{$tablename}")
    println(io,"table [x=x,y=y] {$tablename};")
end
function writeplotdata(io::IO,iotables::IO,f::Figure,ia::Errorbar2D)
    # fieldnames are ia.x, ia.dx, ia.y, ia.dy; dx is a 2xN matrix and dy is a vector
    tablevec=["x=x"]
    colnames=[  "x"]
    data    = ia.x
    if hasxerrorbars(ia)
        sx=issymmetricx(ia)
        tablevec= vcat(tablevec,sx?"x error=dx":["x error minus=dx-","x error plus=dx+"])
        colnames= vcat(colnames,sx?        "dx":[              "dx-",             "dx+"])
        data    = hcat(data,    sx?      ia.dx :                                ia.dx')
    end
    push!(tablevec,"y=y")
    push!(colnames,  "y")
    data=hcat(data,ia.y)
    if hasyerrorbars(ia)
        sy=issymmetricy(ia)
        tablevec= vcat(tablevec,sy?"y error=dy":["y error minus=dy-","y error plus=dy+"])
        colnames= vcat(colnames,sy?        "dy":[              "dy-",             "dy+"])
        data    = hcat(data,    sy?      ia.dy :                                ia.dy')
    end
    tablename=newtablename()
    println(iotables,"\\pgfplotstableread{")
    writedatatable(iotables,colnames,data)
    println(iotables,"}{$tablename}")
    println(io,"table [",join(tablevec,","),"]{$tablename};")
end
# function writeplotdata(io::IO,iotables::IO,f::Figure,ia::PColors{T,N}) where {T,N}
#     tablename=newtablename()
#     println(iotables,"\\pgfplotstableread{")
#     writepatchtable(iotables,ia.z)
#     println(iotables,"}{",tablename,"patches}")
#     println(iotables,"\\pgfplotstableread{")
#     (X,Y) = N==2 ? (vec(ia.x),vec(ia.y)) : N==1 ? ndgridvecs(ia.x,ia.y) : error("Only N==1 or N==2 supported!")
#     writedatatable(iotables,["x","y"],hcat(X,Y))
#     println(iotables,"}{",tablename,"vertices}")
#     print(io,"patch table with point meta={",tablename,"patches}] ")
#     println(io,"table {",tablename,"vertices};")
# end
function writeplotdata(io::IO,iotables::IO,f::Figure,ia::PColors{T,N}) where {T,N}
    (x,y) = N==2 ? (ia.x,ia.y) : N==1 ? ndgrid(ia.x,ia.y) : error("Only N==1 or N==2 supported!")
    XY = hcat(vec(x),vec(y))
    any(!isfinite,XY) && (XY=XY[.!vec(any(!isfinite,XY,2)),:]) # remove NaN/Inf values from XY if present
    # sadly, pgfplots forces the patch table to be either in a separate file or inline
    # ultimately inline is probably better, but it is very messy
    patchpath=f.outputloc*newgraphicnumber()".dat"
    iopatch=open(patchpath,"w")
    # writepatchtable(iopatch,size(x,1),size(y,2),ia.z);
    writepatchtable(iopatch,x,y,ia.z); # incase x or y contains NaN values
    close(iopatch)
    (outdir,patchname)=splitdir(patchpath)

    tablename=newtablename()
    println(iotables,"\\pgfplotstableread{")

    writedatatable(iotables,["x","y"],XY)
    println(iotables,"}{",tablename,"}")
    print(io,",patch table with point meta={",patchname,"}] ")
    println(io,"table {",tablename,"};")
end
function writepcolorpng(io::IO,f::Figure,ia::PColors)
    filepath=f.outputloc*newgraphicnumber()
    save(filepath*".png",pcolor2pngdata(ia)) # uses FileIO's save
    return filepath
end
function writepcolorpdf(io::IO,f::Figure,ax::Axis,ia::PColors)
    figure(f) # make sure the passed figure is the current figure for savefig
    filepath=f.outputloc*newgraphicnumber()
    # We'll use matplotlib's ability to save to PDF files direclty,
    # but need to do some math to get the borders right
    extent=ax.obj[:get_window_extent]()[:transformed]( f.obj[:dpi_scale_trans][:inverted]() )
    xax=getp(ax,"xaxis")
    yax=getp(ax,"yaxis")
    # check if the axes and axis frame is turned on
    xvisible= getp(xax,"visible")
    yvisible= getp(yax,"visible")
    frame_on= getp(ax,"frame_on")
    # we also need to check if an x or y grid is on using a private variable :/
    xgridmaj=xax[:_gridOnMajor]
    xgridmin=xax[:_gridOnMinor]
    ygridmaj=yax[:_gridOnMajor]
    ygridmin=yax[:_gridOnMinor]
    # pgfplots will handle drawing the axes, so turn them off (if they're on)
    xvisible && setp(xax,"visible",false)
    yvisible && setp(yax,"visible",false)
    frame_on && setp(ax,"frame_on",false)
    xgridmaj && (xax[:_gridOnMajor]=false)
    xgridmin && (xax[:_gridOnMinor]=false)
    ygridmaj && (yax[:_gridOnMajor]=false)
    ygridmin && (yax[:_gridOnMinor]=false)
    # we need to set edge colors for the individual patches. hopefully this doesn't mess up anything outside of writing out the picture
    # isempty(getp(ia,"edgecolor")) && setp(ia,"edgecolor","face") # getp(ia,"edgecolor") throws a segmentation fault from numpy.jl
    setp(ia,"edgecolor","face")
    # now actually write the PDF
    PyPlot.savefig(filepath*".pdf",format="pdf",bbox_inches=extent,transparent=true)
    # and set things back the way they were (if we can)
    frame_on && setp(ax,"frame_on",true)
    yvisible && setp(getp(ax,"yaxis"),"visible",true)
    xvisible && setp(getp(ax,"xaxis"),"visible",true)
    xgridmaj && (xax[:_gridOnMajor]=true)
    xgridmin && (xax[:_gridOnMinor]=true)
    ygridmaj && (yax[:_gridOnMajor]=true)
    ygridmin && (yax[:_gridOnMinor]=true)
    return filepath
end
# InAxis types have their options in either f.tikzstyles (Annotations) of f.plotstyles (Plots)
# If we find the Dict value with that is equivalent to ia.options then the key is the style name
function writeplot(io::IO,iotables::IO,f::Figure,a::Axis,ia::Annotation)
    isempty(ia.options) ? print(io,"\\node ") : print(io,"\\node[",getstyle(f,ia),"]")
    writeplotdata(io,iotables,f,ia)
end
# Plot type writing
function writeplot(io::IO,iotables::IO,f::Figure,a::Axis,ia::Union{Plot,Errorbar})
    isempty(ia)&&(return) # write nothing for lines with all-nan values
    isempty(ia.options) ? print(io,"\t\\addplot ") : print(io,"\t\\addplot[",getstyle(f,ia),"]")
    writeplotdata(io,iotables,f,ia)
end
function writeplot(io::IO,iotables::IO,f::Figure,a::Axis,ia::PColors)
    style=getstyle(f,ia)
    if get(ia.options,"use_png",false) # set to true while parsing if the data is monotonic in x an y
        println(io,"\t\\addplot graphics[",style,"] {",writepcolorpng(io,f,ia),"};")
    elseif get(ia.options,"use_pdf",false)
        println(io,"\t\\addplot graphics[",style,"] {",writepcolorpdf(io,f,a,ia),"};")
    else # we can't use a PNG and need to use patches instead
        print(io,"\t\\addplot[",style) # the remaining part of the style is put in by writeplotdata
        writeplotdata(io,iotables,f,ia) # modifies ia.options XXX???
    end
end

function writeaxis(io::IO,iotables::IO,f::Figure,a::Axis)
    anyopts = !isnull(a.name)
    anyopts|= !isempty(a.options)
    anyopts|= !isnull(a.at)
    anyopts|= !isempty(a.extraaxisoptions)
    if !anyopts
        println(io,"\\begin{axis}")
    else
        println(io,"\\begin{axis}[%")
        isnull(a.name)             ||( println(io,"name=",get(a.name,"theaxis"),",")  )
        isempty(a.options)         ||( println(io, axisoptions2style(a.options)) )
        isnull(a.at)               ||( println(io,"at=",get(a.at),",anchor=",get(a.anchor,"north west"),",") )
        isempty(a.extraaxisoptions)||( println(io,join(a.extraaxisoptions,",\n"),",") )
        println(io,"]")
    end
    for i=1:length(a.children)
        writeplot(io,iotables,f,a,a.children[i])
    end
    println(io,"\\end{axis}")
end


function writedocument(io::IO,f::Figure)
    println(io,"\\RequirePackage{luatex85}") # FIXME this is necessary thanks to the standalone package being out-of-date
    println(io,"\\documentclass{standalone}")
    isempty(f.latexpackages)||( println(io,"\\usepackage{"    ,join(f.latexpackages,","),"}") )
    isempty(f.tikzlibraries)||( println(io,"\\usetikzlibrary{",join(f.tikzlibraries,","),"}") )
    isempty(f.tikzsettings) ||( println(io,"\\tikzset{"       ,join(f.tikzsettings ,","),"}") )
    isempty(f.plotsettings) ||( println(io,"\\pgfplotsset{"   ,join(f.plotsettings ,","),"}") )
    isempty(f.colormaps)|| (for k in keys(f.colormaps); println(io,"\\pgfplotsset{colormap={$k}{$(f.colormaps[k])}}"); end) #force pre-loading the colormaps
    # TODO add something like f.extralatexcommands to be inserted here
    isempty(f.extracolors)  ||( writecolors(io,f) )

    # define and insert figure width and figure height (for relative axis scaling)
    size=isnull(f.size)?(225.0,337.0):get(f.size).*72.0 # size *should* be in inches, latex likes points best
    println(io,"\\newlength{\\figw}\\setlength{\\figw}{$(size[1])pt}")
    println(io,"\\newlength{\\figh}\\setlength{\\figh}{$(size[2])pt}")

    # We want to use tables, which need to be defined before the tikzpicture environment
    # (or at least by its preamble, which is not what we want)
    # But we also want to see the interesting figure-drawing commands at the top of the file
    # so that everything is easily accessible when we open the document in a text editor.
    # The only solution (without writing two files) is to define a new command that contains
    # the entire pgfplots tikzpicture, then define all of our tables, then start the document and
    # execute our new figure command. The last line of the file then could be
    # \begin{document}\theactualfigure\end{document}
    println(io,"\\newcommand{\\theactualfigure}{%")

    # tables get inserted separately from the figure, so we need two new IOBuffers
    iotables=IOBuffer();
    iofigure=IOBuffer()
    if  isempty(f.tikzstyles)&&isempty(f.plotstyles)&&isempty(f.graphicstyles)
        println(iofigure,"\\begin{tikzpicture}")
    else
        println(iofigure,"\\begin{tikzpicture}[%")
        for (name,options) in f.tikzstyles; println(iofigure,             name,"/.style=",options2style(options),","); end
        for (name,options) in f.plotstyles; println(iofigure,"/pgfplots/",name,"/.style=",options2style(options),","); end
        for (name,options) in f.graphicstyles; println(iofigure,"/pgfplots/plot graphics/",name,"/.style=",options2style(options),","); end
        println(iofigure,"]")
    end
    resettablename()
    resetgraphicnumber()
    for i=1:length(f.children)
        writeaxis(iofigure,iotables,f,f.children[i])
    end
    print(iofigure,"\\end{tikzpicture}")

    # we now have the tikzpicture commands and tables in two buffers
    # - finish making our new figure command
    # - the write out the tables and begin/end document commands
    println(io,String(take!(iofigure)))
    println(io,"} % end of \\theactualfigure command")

    println(io,"\\begin{document}")
    # then write any extra tikz commands (say, a caption), i.e., writetikz TODO

    # now inser the tables
    print(io,String(take!(iotables)))
    # and put in the figure command
    println(io,"\\theactualfigure{}")
    # and end the document
    println(io,"\\end{document}")
end
function Base.write(io::IO,f::Figure)
    # we don't want to overwrite option structures in case the user modified them by hand
    # it seems unlikely that no objects have options, so only reparse if that's the case
    alloptionsempty(f) && ( pgfparse(f) )
    resetstyles!(f) # ensure all styles are up to date
    writedocument(io,f)
end
