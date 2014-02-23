package clipper;

class Polygon 
{

	private var _points: Array<IntPoint>;
	
	
	public function new() 
	{		
		_points = new Array<IntPoint>();
	}
	
	inline public function addPoint( point: IntPoint )
	{
		_points[_points.length] = point;
	}
	
	inline public function getPoint( index: Int ): IntPoint
	{
		return _points[index];
	}
	
	inline public function getPoints(): Array<IntPoint>
	{
		return _points;
	}
	
	inline public function getSize(): Int
	{
		return _points.length;
	}

	inline public function reverse()
	{
		_points.reverse();
	}
	
}