export collectoptions,collectoptions!
# The tree made up of a Figure object, it's children Axis objects, and their
# children should at some point be parsed by calling pgfparse on the top-level
# figure. After pgfparse is finished, each object in the tree will contain a
# filled options field describing the axes options for each Axis and the style
# of each InAxis object.

# Now we must pass through the tree again and collect all options Dicts into
# a single Vector{Dict} which we can then utilize to build-up top-level styles.

function collectoptions(f::Figure)
    pgfopt=Array{Dict{String,Any}}(0)
    tkzopt=copy(pgfopt)
    grpopt=copy(pgfopt)
    for a in f.children
        collectoptions!(a,pgfopt,tkzopt,grpopt)
    end
    return pgfopt,tkzopt,grpopt
end
function collectoptions!(a::Axis,pgfopt::Array{Dict{String,Any}},tkzopt::Array{Dict{String,Any}},grpopt::Array{Dict{String,Any}})
    # It's probably not worthwhile pulling together axis options:
    #any(copt.==a.options)||(push!(copt,a.options)) # uncomment this line if we change our minds
    for p in a.children
        collectoptions!(p,pgfopt,tkzopt,grpopt)
    end
    return pgfopt,tkzopt,grpopt
end
# annotations (e.g., \text()) enter the axis through \node[options] ..., which can use tikz styles
function collectoptions!(a::Annotation,pgfopt::Array{Dict{String,Any}},tkzopt::Array{Dict{String,Any}},grpopt::Array{Dict{String,Any}})
    any(tkzopt.==a.options)||(push!(tkzopt,a.options))
    return pgfopt,tkzopt,grpopt
end
# ColoredSurfaces (pcolor, surf) *might* enter the axis through \addplot[options] *or* \addplot graphics[options]
# the latter of which has to use /pgfplots/plot graphics/ styles
# other InAxis objects enter through \addplot[options] ..., which has to use pgfplots styles
function collectoptions!(a::InAxis,pgfopt::Array{Dict{String,Any}},tkzopt::Array{Dict{String,Any}},grpopt::Array{Dict{String,Any}})
    if get(a.options,"use_png",false)||get(a.options,"use_pdf",false)
        any(grpopt.==a.options)||(push!(grpopt,a.options))
    else
        any(pgfopt.==a.options)||(push!(pgfopt,a.options))
    end
    return pgfopt,tkzopt,grpopt
end

function setstyles!(f::Figure)
    plotstyles,tikzstyles,graphicstyles= collectoptions(f) # plotstyles and tikzstyles are unique arrays of all available styles in the figure
    if isempty(f.plotstyles)&& !isempty(plotstyles)
        for i=1:length(plotstyles); f.plotstyles["pgfplotstyle$i"]=plotstyles[i]; end
    elseif !isempty(plotstyles)
        new=trues(size(plotstyles))
        for (name,style) in f.plotstyles; new[style.==plotstyles]=false; end
        newps=plotstyles[new]
        if !isempty(newps)
            no=length(f.plotstyles)
            for i=1:length(newps); f.plotstyles["pgfplotstyle$(i+no)"]=newps[i]; end
        end
    end
    if isempty(f.tikzstyles)&& !isempty(tikzstyles)
        for i=1:length(tikzstyles); f.tikzstyles["tikzstyle$i"]=tikzstyles[i]; end
    elseif !isempty(tikzstyles)
        new=trues(size(tikzstyles))
        for (name,style) in f.tikzstyles; new[style.==tikzstyles]=false; end
        newts=tikzstyles[new]
        if !isempty(newts)
            no=length(f.tikzstyles)
            for i=1:length(newts); f.tikzstyles["tikzstyle$(i+no)"]=newts[i]; end
        end
    end
    if isempty(f.graphicstyles)&& !isempty(graphicstyles)
        for i=1:length(graphicstyles); f.graphicstyles["pgfgraphicstyle$i"]=graphicstyles[i]; end
    elseif !isempty(graphicstyles)
        new=trues(size(graphicstyles))
        for (name,style) in f.graphicstyles; new[style.==graphicstyles]=false; end
        newps=graphicstyles[new]
        if !isempty(newps)
            no=length(f.graphicstyles)
            for i=1:length(newps); f.graphicstyles["pgfgraphicstyle$(i+no)"]=newps[i]; end
        end
    end
end
function resetstyles!(f::Figure)
    f.plotstyles=Dict{String,Any}()
    f.tikzstyles=Dict{String,Any}()
    f.graphicstyles=Dict{String,Any}()
    setstyles!(f::Figure)
end


# when it comes time to create the pgfplots LaTeX file, we will need to convert
# the options Dicts into pgfplots/tikz styles
export options2style
function pgfformatkeyvalue(d::Dict{String,Any},k::String)
    val= isa(d[k],Dict) ? options2style(d[k]) : d[k]
    return true===val?"$k,":"$k=$val," # if the value is a literal true we don't need to include =$val
end
function handlekeyvalue!(s::IO,d::Dict{String,Any},k::String)
    out=haskey(d,k)
    out && ( print(s,pgfformatkeyvalue(d,k)) )
    return out
end
# the next two functions might be unused
function pgfformatvalue(d::Dict{String,Any},k::String)
    val=isa(d[k],Dict) ? options2style(d[k]) : "$(d[k])"
    return "$val,"
end
function handlevalue!(s::IO,d::Dict{String,Any},k::String)
    out=haskey(d,k)
    out && ( print(s,pgfformatvalue(d,k)) )
    return out
end



function options2style(opt::Array{Dict{String,Any}})
    sty=Array{String}(length(opt))
    for i=1:length(opt)
        sty[i]=options2style(opt[i])
    end
end
function axisoptions2style(opt::Dict{String,Any})
    io=IOBuffer();
    thisopt=copy(opt)
    specialkeys=["#label","#mode","#min","#max","#tick","#ticklabels","#ticklabel style","scaled # ticks","minor #tick"]
    for N in ["x","y","z"], tk in [replace(sk,r"#",N) for sk in specialkeys]
        handlekeyvalue!(io,thisopt,tk) && (delete!(thisopt,tk);print(io,"\n"))
    end
    for k in keys(thisopt); handlekeyvalue!(io,thisopt,k); end
    return String(take!(io))
end
function options2style(opt::Dict{String,Any},left='{',right='}')
    io=IOBuffer(); print(io,left)
    thisopt=copy(opt)
    # I don't know how to deal with the visible key yet, so kill it:
    delete!(thisopt,"visible")
    delete!(thisopt,"use_png") # cut-out the png flag
    delete!(thisopt,"use_pdf")
    haserrormark=false
    if haskey(thisopt,"errormark") # this requires special handling, for simplicity it must be handled last:
        errormark=copy(thisopt["errormark"])
        delete!(thisopt,"errormark")
        isempty(errormark)||(haserrormark=true)
    end
    # the color key to pgfplots/tikz overrides draw and fill, so it must be first if present
    k="color"; handlekeyvalue!(io,thisopt,k) && (delete!(thisopt,k) )
    # any remaining non error bar keys are order independent
    for k in keys(thisopt); handlekeyvalue!(io,thisopt,k); end # no need to remove keys here
    # finally handle errobar mark options if they're present:
    if haserrormark
        print(io,"error bars/.cd,") # go to the error bars directory to avoid prepending error bars/ on everything
        for k in keys(errormark)
            ismatch(r"mark",k) && ( print(io,"error ") ) # mark= and mark options= should be error mark= and error mark options=
            handlekeyvalue!(io,errormark,k)
        end
        print(io,"/tikz/.cd") # go back to the root to play nicely
    end
    print(io,right)
    return String(take!(io))
end


function getstyle(f::Figure,ia)
    style=""; notfound=true
    opt=copy(ia.options)
    # remove flags which don't get output:
    #delete!.(opt,["use_pdf","use_png"]) # the options dictionary in the figure will still contain (at least) use_pdf!
                 for (name,options) in f.plotstyles;    options==opt && (style=name; notfound=false; break); end
    notfound && (for (name,options) in f.graphicstyles; options==opt && (style=name; notfound=false; break); end)
    notfound && (for (name,options) in f.tikzstyles;    options==opt && (style=name; notfound=false; break); end)
    #notfound && (warn("getstyle could not find the named options matching $opt !");style=options2style(ia.options,' ',' '))
    notfound && info("getstyle could not find named options matching $(options2style(opt))")
    return notfound ? options2style(ia.options,' ',' ') : style
end
