package clipper;

class ClipperBase 
{

	//--------------------
	// Static
	
	inline static var horizontal: Float = -3.4E+38;
	inline static var loRange: Int = 0x3FFFFFFF;          
	inline static var hiRange: Int = 0x3FFFFFFF;//FFFFFFFFL; Int64 not suppported 
	
	
	inline public static function abs( i: Int ): Int
	{
		return i < 0 ? -i : i;
	}
	
	inline public static function xor( lhs: Bool, rhs: Bool ): Bool
	{
		return !( lhs && rhs ) && ( lhs || rhs );
	}
	
	inline static function pointsEqual( pt1: IntPoint, pt2: IntPoint ): Bool
	{
		return pt1.equals( pt2 );
	}
	
	
	
	//--------------------
	// Object
	
	var m_MinimaList: LocalMinima;
	var m_CurrentLM: LocalMinima;
	var m_edges: Array<Array<TEdge>>;
	var m_UseFullRange: Bool;
	
	
	public function new()
	{
		m_edges = new Array<Array<TEdge>>();
		m_MinimaList = null;
		m_CurrentLM = null;
		m_UseFullRange = false;
	}
	
	public function clear()
	{
		disposeLocalMinimaList();
		for ( i in 0...m_edges.length )
		{
			var temp: Array<TEdge> = m_edges[i];
			for ( j in 0...temp.length ) 
				temp[j] = null;
			temp.splice(0, temp.length); //clear
		}
		m_edges.splice( 0, m_edges.length ); // clear
		m_UseFullRange = false;
	}
	
	private function disposeLocalMinimaList()
	{
		while( m_MinimaList != null )
		{
			var tmpLm: LocalMinima = m_MinimaList.next;
			m_MinimaList = null;
			m_MinimaList = tmpLm;
		}
		m_CurrentLM = null;
	}
	
	public function addPolygons( ppg: Polygons, polyType: Int/*PolyType*/ ): Bool
	{
		var result: Bool = false;
		for ( polygon in ppg.getPolygons() )
			if ( addPolygon(polygon, polyType) ) 
				result = true;
				
		return result;
	}
	
	public function addPolygon( polygon: Polygon, polyType: Int/*PolyType*/): Bool
	{
		var pg: Array<IntPoint> = polygon.getPoints();
		var len: Int = pg.length;
		if ( len < 3 ) return false;
		var newPoly: Polygon = new Polygon();
		var p: Array<IntPoint> = newPoly.getPoints();
		p.push( pg[0] );
		var j:Int = 0;
		for ( i in 1...len )
		{
			var pgi: IntPoint = pg[i];
			var pj: IntPoint = p[j];
			var pjm: IntPoint = p[j - 1];
			
			var maxVal: Int;
			if (m_UseFullRange) maxVal = hiRange; else maxVal = loRange;
			if (abs(pgi.X) > maxVal || abs(pgi.Y) > maxVal)
			{
				if (abs(pgi.X) > hiRange || abs(pgi.Y) > hiRange)
				{
					throw new ClipperException("Coordinate exceeds range bounds");
				}
				maxVal = hiRange;
				m_UseFullRange = true;
			}

			if (pointsEqual(pj, pgi))
			{
				continue;
			}
			else if (j > 0 && slopesEqual3(pjm, pj, pgi, m_UseFullRange))
			{
				if (pointsEqual(pjm, pgi)) j--;
			} 
			else
			{
				j++;
			}
				
			if (j < p.length)
			{
				p[j] = pgi; 
			}
			else
			{
				p.push(pgi);
			}
		}
		if (j < 2) return false;

		len = j+1;
		while (len > 2)
		{
			//nb: test for point equality before testing slopes ...
			if (pointsEqual(p[j], p[0])) j--;
			else if (pointsEqual(p[0], p[1]) || slopesEqual3(p[j], p[0], p[1], m_UseFullRange))
				p[0] = p[j--];
			else if (slopesEqual3(p[j - 1], p[j], p[0], m_UseFullRange)) j--;
			else if (slopesEqual3(p[0], p[1], p[2], m_UseFullRange))
			{
				var i: Int = 2;
				while ( i <= j ) {
					p[i - 1] = p[i];
					++i;
				}
				j--;
			}
			else break;
			len--;
		}
		if (len < 3) return false;

		//create a new edge array ...
		var edges: Array<TEdge> = new Array<TEdge>();
		for ( i in 0...len ) edges[i] = new TEdge();
		m_edges.push(edges);

		//convert vertices to a double-linked-list of edges and initialize ...
		edges[0].xcurr = p[0].X;
		edges[0].ycurr = p[0].Y;
		initEdge(edges[len - 1], edges[0], edges[len - 2], p[len - 1], polyType);
		var i = len - 2;
		while ( i > 0 )
		{
			initEdge(edges[i], edges[i + 1], edges[i - 1], p[i], polyType);
			--i;
		}
		initEdge(edges[0], edges[1], edges[len-1], p[0], polyType);

		//reset xcurr & ycurr and find 'eHighest' (given the Y axis coordinates
		//increase downward so the 'highest' edge will have the smallest ytop) ...
		var e: TEdge = edges[0];
		var eHighest: TEdge = e;
		do
		{
			e.xcurr = e.xbot;
			e.ycurr = e.ybot;
			if (e.ytop < eHighest.ytop) eHighest = e;
			e = e.next;
		} while ( e != edges[0]);

		//make sure eHighest is positioned so the following loop works safely ...
		if (eHighest.windDelta > 0) eHighest = eHighest.next;
		if (eHighest.dx == horizontal) eHighest = eHighest.next;

		//finally insert each local minima ...
		e = eHighest;
		do {
			e = addBoundsToLML(e);
		} while( e != eHighest );

		return true;
	}
	
	private function initEdge( e: TEdge, eNext: TEdge, ePrev: TEdge, pt: IntPoint, polyType: Int)
	{
		e.next = eNext;
		e.prev = ePrev;
		e.xcurr = pt.X;
		e.ycurr = pt.Y;
		if (e.ycurr >= e.next.ycurr)
		{
			e.xbot = e.xcurr;
			e.ybot = e.ycurr;
			e.xtop = e.next.xcurr;
			e.ytop = e.next.ycurr;
			e.windDelta = 1;
		} 
		else
		{
			e.xtop = e.xcurr;
			e.ytop = e.ycurr;
			e.xbot = e.next.xcurr;
			e.ybot = e.next.ycurr;
			e.windDelta = -1;
		}
		setDx(e);
		e.polyType = polyType;
		e.outIdx = -1;
	}
	
	private function setDx( e: TEdge )
	{
		if (e.ybot == e.ytop) e.dx = horizontal;
		else e.dx = (e.xtop - e.xbot)/(e.ytop - e.ybot);
	}
	
	private function addBoundsToLML( e: TEdge ): TEdge
	{
		//Starting at the top of one bound we progress to the bottom where there's
		//a local minima. We then go to the top of the next bound. These two bounds
		//form the left and right (or right and left) bounds of the local minima.
		e.nextInLML = null;
		e = e.next;
		while (true)
		{
			if ( e.dx == horizontal )
			{
				//nb: proceed through horizontals when approaching from their right,
				//    but break on horizontal minima if approaching from their left.
				//    This ensures 'local minima' are always on the left of horizontals.
				if (e.next.ytop < e.ytop && e.next.xbot > e.prev.xbot) break;
				if (e.xtop != e.prev.xbot) swapX(e);
				e.nextInLML = e.prev;
			}
			else if (e.ycurr == e.prev.ycurr) break;
			else e.nextInLML = e.prev;
			e = e.next;
		}

		//e and e.prev are now at a local minima ...
		var newLm: LocalMinima = new LocalMinima();
		newLm.next = null;
		newLm.Y = e.prev.ybot;

		if ( e.dx == horizontal ) //horizontal edges never start a left bound
		{
			if (e.xbot != e.prev.xbot) swapX(e);
			newLm.leftBound = e.prev;
			newLm.rightBound = e;
		} 
		else if (e.dx < e.prev.dx)
		{
			newLm.leftBound = e.prev;
			newLm.rightBound = e;
		} 
		else
		{
			newLm.leftBound = e;
			newLm.rightBound = e.prev;
		}
		newLm.leftBound.side = EdgeSide.LEFT;
		newLm.rightBound.side = EdgeSide.RIGHT;
		insertLocalMinima( newLm );

		while(true)
		{
			if ( e.next.ytop == e.ytop && e.next.dx != horizontal ) break;
			e.nextInLML = e.next;
			e = e.next;
			if ( e.dx == horizontal && e.xbot != e.prev.xtop) swapX(e);
		}
		return e.next;
	}
	
	private function insertLocalMinima( newLm:LocalMinima )
	{
		if( m_MinimaList == null )
		{
			m_MinimaList = newLm;
		}
		else if( newLm.Y >= m_MinimaList.Y )
		{
			newLm.next = m_MinimaList;
			m_MinimaList = newLm;
		} 
		else
		{
			var tmpLm: LocalMinima = m_MinimaList;
			while( tmpLm.next != null  && ( newLm.Y < tmpLm.next.Y ) )
				tmpLm = tmpLm.next;
			newLm.next = tmpLm.next;
			tmpLm.next = newLm;
		}
	}
	
	inline function popLocalMinima()
	{
		if (m_CurrentLM != null)
		m_CurrentLM = m_CurrentLM.next;
	}
	
	inline private function swapX( e: TEdge )
	{
		//swap horizontal edges' top and bottom x's so they follow the natural
		//progression of the bounds - ie so their xbots will align with the
		//adjoining lower edge. [Helpful in the ProcessHorizontal() method.]
		e.xcurr = e.xtop;
		e.xtop = e.xbot;
		e.xbot = e.xcurr;
	}
	
	function reset()
	{
		m_CurrentLM = m_MinimaList;

		//reset all edges ...
		var lm: LocalMinima = m_MinimaList;
		while (lm != null)
		{
			var e: TEdge = lm.leftBound;
			while (e != null)
			{
				e.xcurr = e.xbot;
				e.ycurr = e.ybot;
				e.side = EdgeSide.LEFT;
				e.outIdx = -1;
				e = e.nextInLML;
			}
			e = lm.rightBound;
			while (e != null)
			{
				e.xcurr = e.xbot;
				e.ycurr = e.ybot;
				e.side = EdgeSide.RIGHT;
				e.outIdx = -1;
				e = e.nextInLML;
			}
			lm = lm.next;
		}
	}
	
	public function getBounds(): IntRect 
	{
		var result: IntRect = new IntRect(0, 0, 0, 0);
		var lm: LocalMinima = m_MinimaList;
		if (lm == null) return result;
		result.left = lm.leftBound.xbot;
		result.top = lm.leftBound.ybot;
		result.right = lm.leftBound.xbot;
		result.bottom = lm.leftBound.ybot;
		while (lm != null)
		{
			if (lm.leftBound.ybot > result.bottom)
				result.bottom = lm.leftBound.ybot;
			var e: TEdge = lm.leftBound;
			while(true)
			{
				var bottomE: TEdge = e;
				while (e.nextInLML != null)
				{
					if (e.xbot < result.left) result.left = e.xbot;
					if (e.xbot > result.right) result.right = e.xbot;
					e = e.nextInLML;
				}
				if (e.xbot < result.left) result.left = e.xbot;
				if (e.xbot > result.right) result.right = e.xbot;
				if (e.xtop < result.left) result.left = e.xtop;
				if (e.xtop > result.right) result.right = e.xtop;
				if (e.ytop < result.top) result.top = e.ytop;

				if (bottomE == lm.leftBound) e = lm.rightBound;
				else break;
			}
			lm = lm.next;
		}
		return result;
	}
	
	inline function pointIsVertex(pt:IntPoint, pp:OutPt):Bool
	{
		var result: Bool = false;
		var pp2:OutPt = pp;
		do
		{
			if (pointsEqual(pp2.pt, pt)) {
				result = true;
				break;
			}
			pp2 = pp2.next;
		}
		while (pp2 != pp);
		return result;
	}
	
	inline function pointInPolygon(pt:IntPoint, pp:OutPt, useFulllongRange:Bool):Bool
	{
		var pp2:OutPt = pp;
		var result:Bool = false;
		do
		{
			if ((((pp2.pt.Y <= pt.Y) && (pt.Y < pp2.prev.pt.Y)) ||
				((pp2.prev.pt.Y <= pt.Y) && (pt.Y < pp2.pt.Y))) &&
				(pt.X - pp2.pt.X < (pp2.prev.pt.X - pp2.pt.X) * (pt.Y - pp2.pt.Y) /
				(pp2.prev.pt.Y - pp2.pt.Y))) result = !result;
			pp2 = pp2.next;
		} while (pp2 != pp);
		return result;
	}
	
	inline function slopesEqual(e1:TEdge, e2:TEdge, useFullRange:Bool):Bool
	{
		return (e1.ytop - e1.ybot) * (e2.xtop - e2.xbot) -
			   (e1.xtop - e1.xbot) * (e2.ytop - e2.ybot) == 0;
	}
	
	inline function slopesEqual3( pt1: IntPoint, pt2: IntPoint, pt3: IntPoint, useFullRange: Bool ): Bool
	{
		return (pt1.Y - pt2.Y) * (pt2.X - pt3.X) - (pt1.X - pt2.X) * (pt2.Y - pt3.Y) == 0;
	}
	
	inline function slopesEqual4(pt1:IntPoint, pt2:IntPoint, pt3:IntPoint, pt4:IntPoint, 
		useFullRange:Bool):Bool
	{
		return (pt1.Y - pt2.Y) * (pt3.X - pt4.X) - (pt1.X - pt2.X) * (pt3.Y - pt4.Y) == 0;
	}
	
}