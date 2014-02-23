package clipper;

class PolyFillType 
{

	//By far the most widely used winding rules for polygon filling are
	//EvenOdd & NonZero (GDI, GDI+, XLib, OpenGL, Cairo, AGG, Quartz, SVG, Gr32)
	//Others rules include Positive, Negative and ABS_GTR_EQ_TWO (only in OpenGL)
	//see http://glprogramming.com/red/chapter11.html

	inline public static var EVEN_ODD: Int = 0;
	inline public static var NON_ZERO: Int = 1;
	inline public static var POSITIVE: Int = 2;
	inline public static var NEGATIVE: Int = 3;
	
}