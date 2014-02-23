package clipper;

class TEdge 
{

	public var xbot: Int;
	public var ybot: Int;
	public var xcurr: Int;
	public var ycurr: Int;
	public var xtop: Int;
	public var ytop: Int;
	public var dx: Float;
	public var tmpX: Int;
	public var polyType: Int; //PolyType 
	public var side: Int; //EdgeSide 
	public var windDelta: Int; //1 or -1 depending on winding direction
	public var windCnt: Int;
	public var windCnt2: Int; //winding count of the opposite polytype
	public var outIdx: Int;
	public var next: TEdge;
	public var prev: TEdge;
	public var nextInLML: TEdge;
	public var nextInAEL: TEdge;
	public var prevInAEL: TEdge;
	public var nextInSEL: TEdge;
	public var prevInSEL: TEdge;
	
	
	public function new()
	{
		
	}
	
}