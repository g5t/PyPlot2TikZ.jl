export pgfparse

function pgfparsetext_parts(a::PyCall.PyObject)
    text=getp(a,:text) # get the internal text
    color=getp(a,:color)
    position=[getp(a,:position)...]
    rotation=getp(a,:rotation)
    alpha=isa(getp(a,:alpha),Void)?1.:getp(a,:alpha)
    (text,color,position,rotation,alpha)
end
# Here is where we can go through a Figure object passing by every child axis
# and every child plot in order to pull together style definitions, necessary
# packages, etc.
# Borrow inspiration from matplotlib2tikz.py
function pgfparse(f::Figure)
    #figobj=f.obj #there doesn"t seem to be anything worth pulling from the figure object
    isopen(f)||(warn("The passed figure is closed in matplotlib. Parsing a closed figure might be bad."))
    isnull(f.size)&&( f.size=Nullable{NTuple{2,Float64}}( (getp(f.obj,"figwidth"),getp(f.obj,"figheight")) ) ) # the current size of the figure (in inches?)
    for a in f.children
        pgfparse(f,a)
    end
end
### Axis Parsing
function pgfparseticklabels(f::Figure,ax::Axis,v::Array{Any,1},xyz::String)
    t=Array{String}(length(v))
    c=Array{Any}(length(v))
    p=Array{Float64}(length(v),2)
    r=Array{Float64}(length(v))
    a=Array{Float64}(length(v))
    for i=1:length(v); (t[i],c[i],p[i,:],r[i],a[i])=pgfparsetext_parts(v[i]); end
    # now decide if options are the same for all
    cc=length(unique(c))==1
    cp=size(unique(p,1),1)==1
    cr=length(unique(r))==1
    ca=length(unique(a))==1
    style=Dict{String,Any}()
    cc && "black"!=pgfparsecolor(f,c[1]) && ( style["draw"]=pgfparsecolor(f,c[1]) )
    #cp && ( XXX deal with the position being shifted XXX )
    # information to help (eventually) implement this:
    #   The position key stores a relative-to-axis-size position of the tick label.
    #   For x axes, only the second value matters with position[2]=0 placing the tick at ymin
    #   and position[2]=1 placing it at ymax. For y axes only position[1] matters.
    #   PGFplots could implement this as some `yshift` key with a value calculated
    #   from the difference between, e.g., the current axis north and south anchors.
    #   At the moment the utility of this seems dubious, so I say ignore it.
    cr && 360>abs(r[1])>0 && ( style["rotate"]=r[1] )
    ca && ( 0<=a[1]<1 && ( style["opacity"]=a[1] ) )
    isempty(style)||(ax.options[xyz*" tick label style"]=style)
    # now deal with individual styles
    if !cc
        for i=1:length(v)
            "black"!=pgfparsecolor(f,c[i]) && (t[i]="\\textcolor{"*pgfparsecolor(f,c[i])*"}{"*t[i]*"}")
        end
    end
    # how do I rotate an individual tick label?
    # what about apply opacity to one tick label?
    return "{"*join(t,",")*"}"
end
function pgfparseaxislabel(f::Figure,ax::Axis,l::PyCall.PyObject,xyz::String,nr::Number)
    (t,c,p,r,a)=pgfparsetext_parts(l)
    style=Dict{String,Any}()
    "black"!=pgfparsecolor(f,c) && (style["draw"]=pgfparsecolor(f,c))
    # FIXME still not sure how to deal with position information
    360>abs(r-nr)>0 && (style["rotate"]=r-nr) # only rotate if non-zero and non-360
    1>a>=0 && (style["opacity"]=a)
    isempty(style)||(ax.options[xyz*" label style"]=style)
    return "{"*t*"}"
end
function mode(v::Vector{T}) where T
  d=Dict{T,typeof(1)}()
  for x in v; haskey(d,x)?d[x]+=1:d[x]=1; end
  k=collect(keys(d))
  return k[indmax(values(d))]
end
function pgfparseaxisline(f::Figure,a::Axis,xyz::String,nr::Number,b::PyCall.PyObject)
    # axis view limits
    lim=getp(b,:view_interval); a.options[xyz*"min"]=minimum(lim); a.options[xyz*"max"]=maximum(lim)

    # matplotlib and pgfplots disagree on automatic tick locations.
    # The mpl defaults look fine in a PyPlot window, but less so in a pgfplots figure.
    # Only set the axis options {x,y,z}tick and {x,y,z}ticklabels of the labels are
    # more than just simple numbers:
    mplticks=false # TODO implement a way to override this and go with mpl's behavior
    tl=getp(b,:majorticklocs)
    tt=getp(b,:majorticklabels)
    if "log"==getp(b,:scale)
        a.options[xyz*"mode"]="log"
        # log scaling introduces LaTeX math-mode ticks, which are difficult to deal with
        # so let pgfplots figure out where to put ticks
    elseif isempty(tl) || ( !all( x->isnumeric(getp(x,:text)),tt ) )
        # major tick labels
        a.options[xyz*"ticklabels"]=pgfparseticklabels(f,a,tt,xyz)
        mplticks=true # if we've set custom labels we need to use the Matplotlib tick locations too
    end
    # tick locations
    # a.options[xyz*"tick"]=isempty(tl)?"\\empty":"{"*join([@sprintf("%g",x) for x in tl],",")*"}" # "{}" produces automatic major ticks
    a.options[xyz*"tick"]=isempty(tl)? "\\empty" : mplticks? "{"*join([@sprintf("%g",x) for x in tl],",")*"}" : "{}"
    # check to see if we need to turn off tick scaling
    tsteps=diff(tl)
    any(iszero,tsteps) && filter!(!iszero,tsteps) # zero size steps will give -Inf for the power of their significance
    # the negative power of the most precise digit of the step size between ticks along the axis is given by:
    tpow=eltype(tsteps)<:Integer?0: mode(ceil.(Integer,log10.(denominator.(rationalize.(Int32,abs.(tsteps))))))
    # (if the step sizes are integer we can skip setting a precision *and* rationalize isn't defined for Int
    if tpow>0
        a.options["scaled "*xyz*" ticks"]=false
        a.options[xyz*"ticklabel style"]="{/pgf/number format/.cd,fixed,zerofill,precision=$tpow,/tikz/.cd}"
    end
    mtl=getp(b,:minorticklocs)
    isempty(mtl)||(a.options["minor "*xyz*"tick"]="{"*join([@sprintf("%g",x) for x in mtl],",")*"}") # or no minor ticks
    # pgfplots does not (appear to) support minor tick labels, but they could be implemented via extra axis ticks
    # axis label
    isempty(getp(b,:label_text))||( a.options[xyz*"label"]=pgfparseaxislabel(f,a,getp(b,:label),xyz,nr) )
end
function pgfparse(f::Figure,a::Axis)
    obj=a.obj
    bbox=BBox(getp(obj,"position")) # the axis bounding box contains its relative position and size
    w=width(bbox); h=height(bbox)
    1>=w>=0 && (a.options["width"]="$w\\figw")
    1>=h>=0 && (a.options["height"]="$h\\figh")
    getp(obj,:visible) || (a.options["visible"]=false) # if an axis isn't visible -- don't draw it (TODO implement checking for this key later)
    # axis transparancy
    !isa(getp(obj,:alpha),Void) && 1>getp(obj,:alpha)>=0 && (a.options["opacity"]=getp(obj,:alpha))
    # axis scaling ratio (overrides height?) # don't turn this on, it's not usually useful (and might cause too-big-number errors in latex)
    #1!=getp(obj,:data_ratio)&&(a.options["unit vector ratio"]="$(getp(obj,:data_ratio)) 1")
    # which axis lines to draw TODO figure out the remaining options
    getp(obj,:frame_on)&&(a.options["axis lines"]="box")
    # axis title
    isempty(getp(obj,:title))||(a.options["title"]="{"*getp(obj,:title)*"}")
    # axes
    pgfparseaxisline(f,a,"x",0.0,getp(obj,:xaxis))
    pgfparseaxisline(f,a,"y",90.,getp(obj,:yaxis))
    # if present, the zaxis object is a child of ax (the first one?) but is not accessible via getp(ax,:zaxis)
    # TODO implement z-axis information somehow?

    # now go through all of the axis children
    for ia in a.children
        pgfparse(f,a,ia)
    end
end

### InAxis parsing
function pgfparse(f::Figure,ax::Axis,ia::Text2D)
    obj=ia.obj
    (t,c,p,r,a)=pgfparsetext_parts(obj)
    "black"!=pgfparsecolor(f,c) && (ia.options["draw"]=pgfparsecolor(f,c))
    # FIXME still not sure how to deal with extra position information
    360>abs(r)>0 && (ia.options["anchor"]="north west";ia.options["rotate"]=r) # anchor=north west, seems consistent with matplotlib behavior
    1>a>=0 && (ia.options["opacity"]=a)
end

# MatPlotLib PyPlot markers are partially detailed at http://matplotlib.org/examples/lines_bars_and_markers/marker_reference.html
# PGFplots covers markers in the manual, pg. 161 and linked pages
function pgfparsemark(f::Figure,a::Axis,opts::Dict{String,Any},obj::PyPlot.PyObject)
    fillstyle=getp(obj,:fillstyle)
    marker=getp(obj,:marker)
    markeredgecolor=getp(obj,:markeredgecolor)
    markeredgewidth=getp(obj,:markeredgewidth)
    markerfacecolor=getp(obj,:markerfacecolor)
    markerfacecoloralt=getp(obj,:markerfacecoloralt)

    markoptions=Dict{String,Any}()
    fillablemarks=["o","s","D","d"]
    idx=findfirst(fillablemarks.==marker)
    fullmarks=["*","square*","halfsquare*","diamond*"]
    fillmarks=["halfcircle*","halfsquare*","halfsquare*","halfdiamond*"]
    nonemarks=["o","square","halfsquare*","diamond"]
    rotateadd=[0,135,180,180]
    if idx>0
        if "full"==fillstyle
            mark=fullmarks[idx]
            markoptions["fill"]=pgfparsecolor(f,markerfacecolor)
            "D"==marker &&( opts["mark color"]=pgfparsecolor(f,markerfacecolor) )
        elseif any(["left","right","bottom","top"].==fillstyle)
            mark=fillmarks[idx]
            rotatepos=["left","right","bottom"].==fillstyle # top doesn't need to rotate
            rotatedeg=[90,270,180]+rotateadd[idx]
            any(rotatepos) && ( markoptions["rotate"]=rotatedeg[findfirst(rotatepos)] )
            markoptions["fill"]=pgfparsecolor(f,markerfacecolor)
            (eltype(markerfacecoloralt)<:Number||"none"!=lowercase(markerfacecoloralt)) && ( opts["mark color"]=pgfparsecolor(f,markerfacecoloralt) )
        else # fillstyle is "none","None",None, or -1
            mark=nonemarks[idx]
            "D"==marker && (markoptions["fill"]="none")
        end
    elseif any(["^","<","v",">"].==marker) # triangles are a special fillable-marker
        rotatepos=["<","v",">"].==marker
        rotatedeg=[90,180,270]
        any(rotatepos) && (markoptions["rotate"]=rotatedeg[findfirst(rotatepos)])
        if any(["full","left","right","top","bottom"].==fillstyle)
            mark="triangle*"
            markoptions["fill"]=pgfparsecolor(f,markerfacecolor)
        else
            mark="triangle"
        end
    elseif any(["2","3","1","4"].==marker) # Mercedes star
        mark="Mercedes star"
        rotatepos=["3","1","4"].==marker
        rotatedeg=[90,180,270]
        any(rotatepos) && (markoptions["rotate"]=rotatedeg[findfirst(rotatepos)])
    elseif "p"==marker # pentagon
        if any(["full","left","right","top","bottom"].==fillstyle)
            mark="pentagon*"
            markoptions["fill"]=pgfparsecolor(f,markerfacecolor)
        else
            mark="pentagon"
        end
    elseif any(["*","+","-","|","_","x"].==marker)
        mark=["star","+","-","|","-","x"][findfirst(["*","+","-","|","_","x"].==marker)]
    end
    # the draw color of a marker in pgfplots defaults to that of its parent line, so we need
    # only specify it if they are different.
    # markeredgecolor!=getp(obj,:color) && ( markoptions["draw"]=pgfparsecolor(f,markeredgecolor) )
    # FIXME It seems that mpl won't allow for different color lines and markeredgecolor, so we shouldn't need to set draw ever
    # set the "mark options" entry only if there's something to set
    if isempty(markoptions)
        haskey(opts,"mark options") && ( delete!(opts,"mark options") )
    else
        opts["mark options"]=markoptions
    end
    if ~isdefined(:mark)
        warn("Unknown marker `$marker`; passing directly to TikZ, expect problems.")
        mark=marker
    end
    opts["mark"]=mark # now that everything is sorted, set the mark key
end



function pgfparseinaxis1(f::Figure,a::Axis,ia::InAxis,obj::PyPlot.PyObject)
    getp(obj,:visible) || (ia.options["visible"]=false) # (TODO implement checking for this key later)
    # plot opacity
    !isa(getp(obj,:alpha),Void) && 1>getp(obj,:alpha)>=0 && (ia.options["opacity"]=getp(obj,:alpha))
    # linestyle
    ldict=Dict("-" => "solid", ":" => "dotted", "--" => "dashed", "-." => "dashdotted")
    # add the linestyle, a dashing specification, or "only marks" to the options Dict
    linestyle=getp(obj,:linestyle)
    isa(linestyle,Array)&&(linestyle=linestyle[1])
    if isa(linestyle,Tuple)
        dp=linestyle[2] # this is (hopefully) a dashing specification
        if !isa(dp,Void)
            st=""; for i=1:2:length(dp); st*="on $(dp[i])pt off $(dp[i+1])pt "; end
            ia.options["dash pattern"]=st
        end
    else # match the mpl style to our dict values or use only marks for None
        ia.options[ get(ldict,linestyle,"only marks") ]=true # the true isn't necessary, but makes things simpler elsewhere
    end
    # deal with line width here
    linewidth=getp(obj,:linewidth); isa(linewidth,Tuple)&&(linewidth=linewidth[1])
    linewidth!=1 && (ia.options["line width"]="$(4*linewidth/10)pt") # the 1pt matplotlib == 0.4pt pgfplots
end
function pgfparseinaxis2(f::Figure,a::Axis,ia::Fill2D,obj::PyPlot.PyObject)
    # edgecolor and facecolor of a fill_between (Polygon2d) object are apparently stored as rgbA
    edgecolor=getp(obj,:edgecolor);
    edgecolor=size(edgecolor,1)>0?edgecolor[1:3]:"" # keep just rgb
    facecolor=getp(obj,:facecolor)
    facecolor=size(facecolor,1)>0?facecolor[1:3]:"" # letting opacity handle A
    # set the draw and fill colors, respectively
    # only set draw if there is non-zero line width
    linewidth=getp(obj,:linewidth); isa(linewidth,Tuple)&&(linewidth=linewidth[1])
    ia.options["draw"]=linewidth>0 ? pgfparsecolor(f,edgecolor) : "none"
    ia.options["fill"]=pgfparsecolor(f,facecolor)
    # check if there is a hatch pattern that needs to be added
    pdict=Dict("/"  => "north east lines", "\\" => "north west lines", "|"  => "vertical lines",
               "-"  => "horizontal lines", "+"  => "grid",             "x"  => "crosshatch",
               "o"  => "sixpointed stars", "O"  => "crosshatch dots",  "."  => "dots",
               "*"  => "fivepointed stars")
    if haskey(pdict,getp(obj,:hatch))
        # set the field in the Figure object to indicate the patterns library needs to be loaded
        any(f.tikzlibraries .== "patterns")||( push!(f.tikzlibraries,"patterns") )
        popt=Dict{String,Any}()
        # set the (nearly) equivalent pattern style
        popt["pattern"]=pdict[getp(obj,:hatch)]
        # and its drawing color
        popt["pattern color"]=pgfparsecolor(f,edgecolor)
        ia.options["postaction"]=popt # to allow for the possibility of a filled pattern, it must be put in as a postaction
    end
end
function pgfparseinaxis2(f::Figure,a::Axis,ia::Union{Plot,Errorbar},obj::PyPlot.PyObject)
    # (line) drawing color
    ia.options["color"]=pgfparsecolor(f,getp(obj,:markeredgecolor)) # if present, lines get drawn in the markeredgecolor apparently
    # markers; only bother if the marker key is present and not anything which ends up being blank
    isempty(getp(obj,:marker))||any([""," ","None","none"].==getp(obj,:marker))||( pgfparsemark(f,a,ia.options,obj) )
end
function pgfparseinaxis3(f::Figure,a::Axis,ia::Errorbar,obj,objlines) # these objects could have markers, lines, fills, etc.
    # The errorbar end marks in matplotlib and pgfplots are fully-fledged markers and have all
    # of the marker properties. In matplotlib each of the (up to) four markers can have an independent style
    # pgfplots is restricted to only one errorbar marker style per plot, so we can only use the fancy styling
    # if all matplotlib errorbar markers are the same
    erroptions=Dict{String,Any}()
    # dependent on the style of error bars, the options differ
    hasxerrorbars(ia) && (erroptions["x dir"]="both"; erroptions["x explicit"]=true) # the true isn't necessary, but doesn't hurt
    hasyerrorbars(ia) && (erroptions["y dir"]="both"; erroptions["y explicit"]=true)
    if hasxerrorbars(ia)||hasyerrorbars(ia)
      if isempty(obj) # with Matplotlib v2.0.0+ it seems normal to not have caps and to return an empty tuple for obj[2]
        erroptions["mark"]="none"
      else
        errmarks=unique(map(x->getp(x,:marker),obj))
        # in the case of ["|","_"] we *can* do something, in fact we should
        # because the cap color isn't necessarily the line color
        (errmarks==["|","_"]||errmarks==["_","|"])&&(errmarks=["-"])
        if length(errmarks)==1 #if length(errmarks)>1 # we can't do anything
            if any([""," ","none","None"].==errmarks[1]) # no errorbar caps, the easy non-standard case
                erroptions["mark"]="none"
            else
                pgfparsemark(f,a,erroptions,obj[1]) # pick the first one, and hope they're all the same
            end
        end
      end
      # we also (might) need to specify the drawing color for the errorbars themselves (not their caps)
      errlinecolors=unique(getp.(objlines,:color))
      errlinecolor= length(errlinecolors)==1 ? errlinecolors[1]: errlinecolors[2] # try to default to the y color
      isa(errlinecolor,Array)&&length(errlinecolor)>3 && (errlinecolor=errlinecolor[1:3]) # drop the A of rgbA if present
      erroptions["error bar style"]=Dict{String,Any}("draw"=>pgfparsecolor(f,errlinecolor))
    end
    isempty(erroptions)||(ia.options["errormark"]=erroptions)
end
function pgfparse(f::Figure,a::Axis,ia::Errorbar)
    # the first part is the same independent of type
    obj=ia.obj
    # the "object" returned by PyPlot.errorbar is a Tuple{PyC.PyO,Tuple{PyC.PyO,PyC.PyO,PyC.PyO},Tuple{PyC.PyO,PyC.PyO}}
    # obj[1] contains the point markers
    # obj[2] contains the markers for the ends of the errorbars -- normally "|" and "_"
    # obj[3] contains the actual errorbar lines (which we ignore here)
    pgfparseinaxis1(f,a,ia,obj[1]) # parse visibility, opacity, and linestyle
    pgfparseinaxis2(f,a,ia,obj[1]) # parse draw color and markers
    pgfparseinaxis3(f,a,ia,obj[2],obj[3])
end
function pgfparse(f::Figure,a::Axis,ia::PColor)
    if output_graphics() && output_raster_graphics() && ismonotonic(ia)
    #if output_graphics() && isempty(getp(ia,:edgecolor)) && getp(ia,:hatch)===nothing && ismonotonic(ia)
        ia.options["use_png"]=true;
        ia.options["xmin"],ia.options["xmax"]=extrema(ia.x)
        ia.options["ymin"],ia.options["ymax"]=extrema(ia.y)
    elseif output_graphics() # we can't use a PNG, but we *can* use a PDF
        a.options["axis on top"]=true; # the PDF will have a white background :/
        # if we instead figure out how to *import* svg graphics to pgfplots, it's possible to output transparent background svgs
        ia.options["use_pdf"]=true;
        ia.options["xmin"],ia.options["xmax"]=extrema(getp(a,"xlim")) # the generated PDF will
        ia.options["ymin"],ia.options["ymax"]=extrema(getp(a,"ylim")) # have the same limits as the axis
    else # deal with patches :(
        length(ia.z)>10^3 && warn("Creating (up to) $(length(ia.z)) patches. LuaLaTeX compilation may be very slow")
        ia.options["patch"]=true;
        ia.options["shader"]="flat" # isempty(getp(ia,:edgecolor))?"flat":"faceted"
        ia.options["patch type"]="rectangle";
        ia.options["colormap name"]=getpgfcolormap(f,ia) # returns a named colormap (creating one if it does not exist)
        ia.options["point meta min"],ia.options["point meta max"]=getp(ia,:clim)
        # ia.options["patch table with point meta"]=::tablename:: <-- this will be written directly into the stream later
    end
end
function pgfparse(f::Figure,a::Axis,ia::InAxis)
    # the first part is the same independent of type
    obj=ia.obj
    pgfparseinaxis1(f,a,ia,obj)
    pgfparseinaxis2(f,a,ia,obj)
end







#function addpgfcolor{R<:AbstractFloat}(f::Figure,named::String,vec::Array{R,1})
#    !all(0.<=vec.<=1) && (error("pgfplots expects only color values scaled between 0 and 1"))
#    # if the color name already exists, and the vectors are compatible, and not equivalent
#    if haskey(f.availcolors,named)&&compatible(f.availcolors[named],vec)&&!all(f.availcolors[named].==vec)
#        # find an available colorname to use by adding an integer to the given name
#        i=1; orignamed=named; named=orignamed*"$i"
#        while haskey(f.availcolors,named)&&compatible(f.availcolors[named],vec)&&!all(f.availcolors[named].==vec); i+=1; named=orignamed*"$i"; end
#    end
#    # only if the color is actually new, add it to f.availcolors and f.extracolors
#    if !haskey(f.availcolors,named)
#        f.availcolors[named]=vec
#        f.extracolors[named]=vec
#    end
#    return named
#end
#addpgfcolor{R<:Integer}(f::Figure,named::String,vec::Array{R,1})=addpgfcolor(f,named,vec/255.)
#function addpgfcolor(f::Figure,named::String,val::UInt32)
#    if 0x01000000>val
#        r=val>>16; val-=r<<16; g=val>>8;  val-=g<<8; b=val;
#        return addpgfcolor(f,named,[r,g,b])
#    else
#        c=val>>24; val-=c<<24; m=val>>16; val-=m<<16; y=val>>8; val-=y<<8; k=val;
#        return addpgfcolor(f,named,[c,m,y,k])
#    end
#end
#addpgfcolor(f::Figure,named::String,val::Real)=addpgfcolor(f,named,[val,val,val])


#function pgfparsecolor{T<:Real}(f::Figure,c::Array{T,1})
#    found=false; #out=black
#    for (name,v) in f.availcolors
#        compatible(v,c) && all(v.==c) && (found=true; out=name; break)
#    end
#    # matplotlib2tikz.py (and matlab2tikz.m) check for shadings of the named colors
#    # I don't like this behavior because the specific shading might need to be calculated
#    # multiple times in a figure if, e.g., one uses gray lines/points/... to indicate
#    # data which was collected but excluded from analysis.
#    # I think that creating a new named color for each shading used will ultimately reduce
#    # the latex/pdflatex/lualatex/... computation time.
#    if !found
#        # find the most-similar existing color and use its name as a starting point
#        names=collect(keys(f.availcolors))
#        dists=Inf*ones(length(allnames))
#        for i=1:length(allnames)
#            compatible(f.availcolors[names[i]],c) && (dists[i]=sqrt(sumabs2(f.availcolors[names[i]]-c)))
#        end
#        out=any(dists.<Inf) ? names[ indmin(dists) ] : "jlcolor"
#        out=addpgfcolor(f,out,c)
#    end
#    return out
#end
#function pgfparsecolor(f::Figure,c::String)
#    "none"==lowercase(c) && (return "none") # none is a valid absence-of-color indicator
#    # check if c is a one-character matplotlib color
#    mpl=Dict("b"=>"blue","g"=>"green","r"=>"red","c"=>"cyan","m"=>"magenta","y"=>"yellow","k"=>"black","w"=>"white")
#    if 1==length(c)
#        haskey(mpl,c) && (return mpl[c])
#    # or a matplotlib hex color which has the form #RRGGBB
#    elseif length(c)==7 && "#"==c[1]
#        return pgfparsecolor(f,hex2bytes(c[2:end]/255))
#    end
#    # it's also possible that one of the spelled-out matplotlib colors was passed:
#    for (k,v) in mpl; v==c && (return c); end
#    # or maybe the color is one of the available named colors
#    haskey(f.availcolors,c) && (return c)
#    # or, as a last check, it could be a mixing specification, e.g., blue!48!cyan
#    sc=split(c,"!"); ok=true;
#    for i=1:length(sc)
#        isanavailable=haskey(f.availcolors,sc[i])
#        isanintegerno=typeof(parse(sc[i]))<:Integer && (0<=parse(sc[i])<=100)
#        isnamedmplclr=false
#        for (k,v) in mpl; v==sc[i] && (inamedmplclr=true); end
#        ok&= isanavailable|isanintegerno|isnamedmplclr
#    end
#    ok && (return c)
#    # nothing else to try, so give up
#    warning("pgfparsecolor can not parse color=$c, returning black")
#    return "black"
#end
#pgfparsecolor(f::Figure,c::Real)=pgfparsecolor(f,[c,c,c]) # shades of gray
