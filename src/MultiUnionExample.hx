/*******************************************************************************
*                                                                              *
* Author    :  Angus Johnson                                                   *
* Version   :  4.8.8                                                           *
* Date      :  30 August 2012                                                  *
* Website   :  http://www.angusj.com                                           *
* Copyright :  Angus Johnson 2010-2012                                         *
*                                                                              *
* License:                                                                     *
* Use, modification & distribution is subject to Boost Software License Ver 1. *
* http://www.boost.org/LICENSE_1_0.txt                                         *
*                                                                              *
* Attributions:                                                                *
* The code in this library is an extension of Bala Vatti's clipping algorithm: *
* "A generic solution to polygon clipping"                                     *
* Communications of the ACM, Vol 35, Issue 7 (July 1992) pp 56-63.             *
* http://portal.acm.org/citation.cfm?id=129906                                 *
*                                                                              *
* Computer graphics and geometric modeling: implementation and algorithms      *
* By Max K. Agoston                                                            *
* Springer; 1 edition (January 4, 2005)                                        *
* http://books.google.com/books?q=vatti+clipping+agoston                       *
*                                                                              *
* See also:                                                                    *
* "Polygon Offsetting by Computing Winding Numbers"                            *
* Paper no. DETC2005-85513 pp. 565-575                                         *
* ASME 2005 International Design Engineering Technical Conferences             *
* and Computers and Information in Engineering Conference (IDETC/CIE2005)      *
* September 24–28, 2005 , Long Beach, California, USA                          *
* http://www.me.berkeley.edu/~mcmains/pubs/DAC05OffsetPolygon.pdf              *
*                                                                              *
*******************************************************************************/

/*******************************************************************************
*                                                                              *
* This is a translation of the AS3 Clipper library.                            *
*                                                                              *
*                                                                              *
* AS3 Translation Info                                                         *
* Ported by: Chris Denham                                                      *
* Date: 30 October 2012                                                        *
* http://www.virtualworlds.co.uk                                               *
*                                                                              *
*******************************************************************************/

package ;

import flash.display.Graphics;
import flash.display.Sprite;
import flash.events.Event;
import flash.Lib;

import clipper.Clipper;
import clipper.ClipperBase;
import clipper.ClipperException;
import clipper.ClipType;
import clipper.EdgeSide;
import clipper.ExPolygon;
import clipper.HorzJoinRec;
import clipper.IntersectNode;
import clipper.IntPoint;
import clipper.IntRect;
import clipper.JoinType;
import clipper.LocalMinima;
import clipper.OutPt;
import clipper.OutPtRef;
import clipper.OutRec;
import clipper.Point;
import clipper.PolyFillType;
import clipper.Polygon;
import clipper.Polygons;
import clipper.PolyType;
import clipper.Segment;
import clipper.TEdge;

class MultiUnionExample extends Sprite 
{
		
	private var shapes: Array<Shape>;
	
	private function init(e) 
	{
		shapes = new Array<Shape>();
		
		for ( i in 0...10 )
		{
			var shape: Shape = Shape.createDisk( Std.random(25) + 50, Std.random(10) + 3 );
			shape.translate( Std.random(400) + 100, Std.random(200) + 100 );
			shapes.push( shape );
		}
			
		addEventListener(Event.ENTER_FRAME, update);
	}
	
	private function update(e)
	{
		// update polygon positions
		for ( shape in shapes )
			shape.step();
		
		// inialize results to have all polygons
		var resultPolygons: Array<Shape> = new Array<Shape>();
		for ( shape in shapes )
			resultPolygons.push( shape );
			
		// clip together all polygons
		var i: Int = 0;
		var reset: Bool = false;
		while ( i  < resultPolygons.length )
		{
			for ( j in (i+1)...resultPolygons.length )
			{
				var poly1: Shape = resultPolygons[i];
				var poly2: Shape = resultPolygons[j];
				if ( !poly1.aabbIntersects( poly2 ) ) // only try to clip polygons that are near each other
					continue;
				
				var result: Array<Array<Point>> = Clipper.clipPolygon(poly1.points, poly2.points, ClipType.UNION);
				
				// this mess prevents removing and adding the same polygons
				if ( result.length != 2 || (!pointsEqual(poly1.points, result[0]) && !pointsEqual(poly1.points, result[1]) && !pointsEqual(poly2.points, result[0]) && !pointsEqual(poly2.points, result[1])) )
				{
					resultPolygons.remove(poly1);
					resultPolygons.remove(poly2);
					for (r in result)
						resultPolygons.push(new Shape(r));
					i = 0;
					reset = true;
					break;
				}
			}
			
			if ( !reset )
				i++;
			else
				reset = false;
		}

		// render
		graphics.clear();
		graphics.lineStyle(1.5, 0);
		for ( shape in resultPolygons )
			shape.draw( graphics );
	}
	
	public function drawPolygon( polygon: Array<Point> )
	{
		var n: Int = polygon.length;
		if ( n < 3 ) return;
		var p: Point = polygon[0];
		graphics.moveTo(p.x, p.y);
		for ( i in 1...(n+1) )
		{
			p = polygon[i % n];
			graphics.lineTo(p.x, p.y);
		}
	}
	
	public function pointsEqual( points1: Array<Point>, points2: Array<Point> ): Bool
	{
		if ( points1.length != points2.length )
			return false;
			
		var hashX1: Int = 0;  // the points may not be in the same order, so this hash is to determine equality despite this
		var hashY1: Int = 0;
		var hashX2: Int = 0;
		var hashY2: Int = 0;
		
		for ( p in points1 )
		{
			hashX1 += Std.int(p.x);
			hashY1 += Std.int(p.y);
		}
		
		for ( p in points2 )
		{
			hashX2 += Std.int(p.x);
			hashY2 += Std.int(p.y);
		}
			
		return hashX1 == hashX2 && hashY1 == hashY2;
	}
	
	private function addShape(shape: Shape)
	{
		shapes.push(shape);
	}
	
	//--------------------
	// setup
	
	public function new() 
	{
		super();
		#if iphone
		Lib.current.stage.addEventListener(Event.RESIZE, init);
		#else
		addEventListener(Event.ADDED_TO_STAGE, init);
		#end
	}
	
	static public function main() 
	{
		var stage = Lib.current.stage;
		stage.scaleMode = flash.display.StageScaleMode.NO_SCALE;
		stage.align = flash.display.StageAlign.TOP_LEFT;
		
		Lib.current.addChild(new MultiUnionExample());
	}
	
}

class Shape
{
	public var points: Array<Point>;
	public var velX: Float;
	public var velY: Float;
	public var l: Float;
	public var r: Float;
	public var t: Float;
	public var b: Float;
	
	public function new( points: Array<Point> )
	{
		this.points = points;
		
		velX = Std.random(6) - 3;
		velY = Std.random(6) - 3;
		
		l = t = 1e99;
		r = b = -1e99;
		for ( p in points )
		{
			l = Math.min( l, p.x );
			r = Math.max( r, p.x );
			t = Math.min( t, p.y );
			b = Math.max( b, p.y );
		}
	}
	
	public function step()
	{
		translate( velX, velY );
		
		if (l < 0 || r > Lib.current.stage.stageWidth)
			velX *= -1;
			
		if (t < 0 || b > Lib.current.stage.stageHeight)
			velY *= -1;
	}
	
	public function translate( dx: Float , dy: Float )
	{
		for ( p in points )
			p.offset( dx, dy );
			
		l += dx;
		r += dx;
		t += dy;
		b += dy;
	}
	
	public function draw( g: Graphics )
	{
		var n: Int = points.length;
		if ( n < 3 ) return;
		var p: Point = points[0];
		g.moveTo(p.x, p.y);
		for ( i in 1...(n+1) )
		{
			p = points[i % n];
			g.lineTo(p.x, p.y);
		}
	}
	
	inline public function aabbIntersects( s: Shape ): Bool
	{
		return !(l > s.r || r < s.l || t > s.b || b < s.t);
	}
	
	public static function createDisk(radius: Float, segments: Int): Shape
	{
		var points: Array<Point> = new Array<Point>();
		
		var radians: Float = 0;
		var deltaRadians: Float = 2 * Math.PI / segments;
		
		for ( i in 0...segments )
		{
			points.push( Point.polar(radius, radians) );
			radians += deltaRadians;
		}
		
		return new Shape(points);
	}
}