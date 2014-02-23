package clipper;

class Polygons 
{

	private var _polygons: Array<Polygon>;
	
	
	public function new() 
	{		
		_polygons = new Array<Polygon>();
	}
	
	inline public function addPolygon( polygon: Polygon )
	{
		_polygons[_polygons.length] = polygon;
	}
	
	inline public function clear()
	{
		_polygons.splice( 0, _polygons.length );
	}
	
	inline public function getPolygons(): Array<Polygon>
	{
		return _polygons;
	}
	
}