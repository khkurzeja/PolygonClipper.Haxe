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

class SimpleExample extends Sprite 
{
	
	private function init(e) 
	{
		var subjectPolygon: Array<Point> = [new Point(0, 0), new Point(200, 0), new Point(100, 200)];
		var clipPolygon: Array<Point> = [new Point(0, 100), new Point(200, 100), new Point(300, 200)];
		var resultPolygons: Array<Array<Point>> = Clipper.clipPolygon(subjectPolygon, clipPolygon, ClipType.DIFFERENCE);
		
		graphics.lineStyle(2, 0xFF0000, 1.0);
		drawPolygon(subjectPolygon);
		
		graphics.lineStyle(2, 0x0000FF, 1.0);
		drawPolygon(clipPolygon);
		
		graphics.lineStyle(3, 0x00FF00, 1.0);
		graphics.beginFill(0xFF0000, 0.5);
		for( polygon in resultPolygons )
			drawPolygon(polygon);
		graphics.endFill();
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
		
		Lib.current.addChild(new SimpleExample());
	}
	
}