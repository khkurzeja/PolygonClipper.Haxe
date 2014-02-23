package clipper;

class Point 
{

	public static var zero: Point = new Point(0,0);
	
	public var x: Float;
	public var y: Float;
	
	private var _length: Float;
	
	public function new(?x: Float = 0, ?y: Float = 0) 
	{
		this.x = x;
		this.y = y;
	}
	
	inline public function add(v: Point): Point
	{
		return new Point(x + v.x, y + v.y);
	}
	
	inline public function clone(): Point
	{
		return new Point(x, y);
	}
	
	inline public function copyFrom(sourcePoint: Point)
	{
		x = sourcePoint.x;
		y = sourcePoint.y;
	}
	
	inline public static function distance(pt1: Point, pt2: Point): Float
	{
		return Math.sqrt((pt1.x - pt2.x) * (pt1.x - pt2.x) + (pt1.y - pt2.y) * (pt1.y - pt2.y));
	}
	
	inline public function equals(toCompare: Point): Bool
	{
		return x == toCompare.x && y == toCompare.y;
	}
	
	inline public function interpolate(pt1: Point, pt2: Point, f: Float): Point
	{
		return new Point(pt1.x + (pt2.x-pt1.x) * f, pt1.y + (pt2.y - pt1.y) * f);
	}
	
	inline public function normalize(?thickness: Float = 1)
	{
		var len: Float = length;
		if (len != 0)
		{
			var invLen: Float = 1 / len;
			x *= thickness * invLen;
			y *= thickness * invLen;
		}
	}
	
	inline public function offset(dx: Float, dy: Float)
	{
		x += dx;
		y += dy;
	}
	
	inline public static function polar(len: Float, angle: Float): Point
	{
		return new Point(Math.cos(angle) * len, Math.sin(angle) * len);
	}
	
	inline public function setTo(xa: Float, ya: Float)
	{
		x = xa;
		y = ya;
	}
	
	inline public function subtract(v: Point): Point
	{
		return new Point(x - v.x, y - v.y);
	}
	
	public function toString(): String
	{
		return "(x=" + x + ", y=" + y + ")";
	}
	
	inline private function get_length():Float 
	{
		return Point.distance(zero, this);
	}
	inline public var length(get_length, null):Float;
	
	
	
}