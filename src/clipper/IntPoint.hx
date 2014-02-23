package clipper;

class IntPoint 
{

	public var X: Int;
	public var Y: Int;
	
	
	public function new( ?x: Int = 0, ?y: Int = 0 ) 
	{
		this.X = x;
		this.Y = y;
	}
	
	inline public static function cross( vec1: IntPoint, vec2: IntPoint ): Int
	{
		return vec1.X * vec2.Y - vec2.X * vec1.Y;
	}
	
	inline public function equals( pt: IntPoint ): Bool
	{
		return this.X == pt.X && this.Y == pt.Y;
	}
	
}