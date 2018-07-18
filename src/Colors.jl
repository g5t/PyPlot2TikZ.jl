export addpgfcolor,pgfparsecolor

# converted to julia from matplotlib2tikz.py's available_colors which lists xcolor-colors
const xcolors=Dict{String,Array{Float64,1}}(
    "red"       => Float64[1,    0,    0   ],
    "green"     => Float64[0,    1,    0   ],
    "blue"      => Float64[0,    0,    1   ],
    "brown"     => Float64[0.75, 0.5,  0.25],
    "lime"      => Float64[0.75, 1,    0   ],
    "orange"    => Float64[1,    0.5,  0   ],
    "pink"      => Float64[1,    0.75, 0.75],
    "purple"    => Float64[0.75, 0,    0.25],
    "teal"      => Float64[0,    0.5,  0.5 ],
    "violet"    => Float64[0.5,  0,    0.5 ],
    "black"     => Float64[0,    0,    0   ],
    "darkgray"  => Float64[0.25, 0.25, 0.25],
    "gray"      => Float64[0.5,  0.5,  0.5 ],
    "lightgray" => Float64[0.75, 0.75, 0.75],
    "white"     => Float64[1,    1,    1   ])
#following matplotlib2tikz.py:
        # The colors cyan, magenta, yellow, and olive are also
        # predefined by xcolor, but their RGB approximation of the
        # native CMYK values is not very good. Don't use them here.


function addpgfcolor{R<:AbstractFloat}(f::Figure,named::String,vec::Array{R,1})
    !all(0.<=vec.<=1) && (error("pgfplots expects only color values scaled between 0 and 1"))
    # if the color name already exists, and the vectors are compatible, and not equivalent
    if haskey(f.availcolors,named)&&compatible(f.availcolors[named],vec)&&!all(f.availcolors[named].==vec)
        # find an available colorname to use by adding an integer to the given name
        i=1; orignamed=named; named=orignamed*"$i"
        while haskey(f.availcolors,named)&&compatible(f.availcolors[named],vec)&&!all(f.availcolors[named].==vec); i+=1; named=orignamed*"$i"; end
    end
    # only if the color is actually new, add it to f.availcolors and f.extracolors
    if !haskey(f.availcolors,named)
        f.availcolors[named]=vec
        f.extracolors[named]=vec
    end
    return named
end
addpgfcolor{R<:Integer}(f::Figure,named::String,vec::Array{R,1})=addpgfcolor(f,named,vec/255.)
function addpgfcolor(f::Figure,named::String,val::UInt32)
    if 0x01000000>val
        r=val>>16; val-=r<<16; g=val>>8;  val-=g<<8; b=val;
        return addpgfcolor(f,named,[r,g,b])
    else
        c=val>>24; val-=c<<24; m=val>>16; val-=m<<16; y=val>>8; val-=y<<8; k=val;
        return addpgfcolor(f,named,[c,m,y,k])
    end
end
addpgfcolor(f::Figure,named::String,val::Real)=addpgfcolor(f,named,[val,val,val])


function pgfparsecolor{T<:Real}(f::Figure,c::Array{T,1})
    found=false; #out=black
    for (name,v) in f.availcolors
        compatible(v,c) && all(v.==c) && (found=true; out=name; break)
    end
    # matplotlib2tikz.py (and matlab2tikz.m) check for shadings of the named colors
    # I don't like this behavior because the specific shading might need to be calculated
    # multiple times in a figure if, e.g., one uses gray lines/points/... to indicate
    # data which was collected but excluded from analysis.
    # I think that creating a new named color for each shading used will ultimately reduce
    # the latex/pdflatex/lualatex/... computation time.
    if !found
        # find the most-similar existing color and use its name as a starting point
        if 3==length(c)&&0.01>std(c)
            out="gray"
        elseif 3==length(c)
                out=minimum(c)<0.5?"dark":"light"
                tc=c-minimum(c) # tc is now c with any white component removed
                idxs=Vector{Int64}[  [1],    [2],   [3],   [1,2],    [1,3], [2,3]]
                nams=             ["red","green","blue","yellow","magenta","cyan"]
                nidx=map(x->find(tc.==maximum(tc))==x,idxs)
                any(nidx) && (out*=nams[findfirst(nidx)])
        else
            names=collect(keys(f.availcolors))
            dists=Inf*ones(length(names))
            for i=1:length(names)
                compatible(f.availcolors[names[i]],c) && (dists[i]=sqrt(sumabs2(f.availcolors[names[i]]-c)))
            end
            out=any(dists.<Inf) ? names[ indmin(dists) ] : "jlcolor"
        end
        out=addpgfcolor(f,out,c)
    end
    return out
end
function pgfparsecolor(f::Figure,c::String)
    # check if c is a one-character matplotlib color
    mpl=Dict("b"=>"blue","g"=>"green","r"=>"red","c"=>"cyan","m"=>"magenta","y"=>"yellow","k"=>"black","w"=>"white")
    if 1==length(c)
        haskey(mpl,c) && (return mpl[c])
    # or a matplotlib hex color which has the form #RRGGBB
    elseif length(c)==7 && '#'==c[1]
        return pgfparsecolor(f,hex2bytes(c[2:end])/255) # hex2bytes returns a vector
    end
    # it's also possible that one of the spelled-out matplotlib colors was passed:
    any(keys(mpl).==c) && (return c)
    # or maybe the color is one of the available named colors
    haskey(f.availcolors,c) && (return c)
    # or, as a last check, it could be a mixing specification, e.g., blue!48!cyan
    sc=split(c,"!"); ok=true;
    for i=1:length(sc)
        isanavailable=haskey(f.availcolors,sc[i])
        isanintegerno=typeof(parse(sc[i]))<:Integer && (0<=parse(sc[i])<=100)
        isnamedmplclr=false
        for (k,v) in mpl; v==sc[i] && (inamedmplclr=true); end
        ok&= isanavailable|isanintegerno|isnamedmplclr
    end
    ok && (return c)
    # nothing else to try, so give up
    warn("pgfparsecolor can not parse color=$c, returning black")
    return "black"
end
pgfparsecolor(f::Figure,c::Real)=pgfparsecolor(f,[c,c,c]) # shades of gray
