
type BBox
    bb::NTuple{4}
    function BBox(b::NTuple{4})
        v=[b...] # convert to a vector temporarily
        @assert all(v.>=0) && all(v.<=1)
        v[3]>v[1]||( v=v[[3,2,1,4]] )
        v[4]>v[2]||( v=v[[1,4,3,2]] )
        new((v...))
    end
end
BBox{T<:Real}(ll::NTuple{2,T},ur::NTuple{2,T})=BBox((ll[1],ll[2],ur[1],ur[2]))
function BBox(a::PyCall.PyObject)
    trns=PyCall.PyNULL() # initialize a home for matplotlib.transform
    copy!(trns, PyCall.pyimport("matplotlib.transforms") )
    PyPlot.py"isinstance"(a,trns[:Bbox]) || info("About to do something dangerous: calling `getp($a,\"points\")` on a non matplotlib.transforms.Bbox object")
    ## this is dangerous. a better be a PyCall.PyObject Bbox!
    #pos=getp(a,"points") #XXX sometimes asking for "points" from a Bbox object causes a segmentation fault?!?
    #@assert size(pos)==(2,2)
    #@assert eltype(pos)<:Real
    #BBox( (pos[[1,3,2,4]]...) ) # [x1 x2; y1 y2] == [ 1 3; 2 4]
    BBox( (a[:xmin],a[:ymin],a[:xmax],a[:ymax]) )
end

lowerleft(a::BBox) =(a.bb[1],a.bb[2])
upperleft(a::BBox) =(a.bb[1],a.bb[4])
lowerright(a::BBox)=(a.bb[3],a.bb[2])
upperright(a::BBox)=(a.bb[3],a.bb[4])

width(a::BBox) =abs(a.bb[3]-a.bb[1]) # the difference in x coordinates
height(a::BBox)=abs(a.bb[4]-a.bb[2]) # the difference in y coordinates

distance(a::NTuple{2},b::NTuple{2})=sqrt( (a[1]-b[1])^2 + (a[2]-b[2])^2 )

# FIXME this can only be defined after Figure.jl is loaded :/
## Given a vector of Axis objects (the children of a Figure object)
## use their BBox information to determine how (if at all) they are positioned
#function encodeAxisAlignment(f::Figure)
#    axs=f.children
#    length(axs)<2 && return
#    bboxes=[BBox(getp(a,"position")) for a in axs]
#    mula=findfirst( [ distance( (0,1), x ) for x in map(upperleft,bboxes) ] ) # index of most upper-left axis
#
#    # TODO write this :(
#    # There are 25 unique alignment cases for two rectangles sharing at least one corner
#    # (1 sharing 4 corners, 8 sharing 2 corners [4 internal, 4 external], 16 sharing 1 corner)
#    # The switch case to deal with this is complicated but possible.
#    # More complicated are the innumerable cases for two rectangles that share *no* corners
#end
