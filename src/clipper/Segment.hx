package clipper;

class Segment 
{

	public var pt1: IntPoint;
	public var pt2: IntPoint;
	
	
	public function new( pt1: IntPoint, pt2: IntPoint ) 
	{
		this.pt1 = pt1;
		this.pt2 = pt2;
	}
	
	inline public function swapPoints()
	{
		var temp: IntPoint = pt1;
		pt1 = pt2;
		pt2 = temp;
	}
	
}