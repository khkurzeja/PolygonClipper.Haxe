package clipper;

class OutRec 
{

	public var idx: Int;
	public var isHole: Bool;
	public var firstLeft: OutRec;
	public var appendLink: OutRec;
	public var pts: OutPt;
	public var bottomPt: OutPt;
	public var bottomFlag: OutPt;
	public var sides: Int;  //EdgeSide
	
	public function new()
	{
		
	}
	
}