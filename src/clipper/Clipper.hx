package clipper;

import clipper.Error;
import clipper.Point;

class Clipper extends ClipperBase
{

	public static function clipPolygon(subjectPolygonFloat:Array<Point>, clipPolygonFloat:Array<Point>, clipType:Int):Array<Array<Point>>
	{			
		var subjectPolygon:Polygon = new Polygon();
		var clipPolygon:Polygon = new Polygon();

		// Convert clipper.Point arrays into IntPoint vectors
		var point:Point;			
		for (point in subjectPolygonFloat) 
		{				
			subjectPolygon.addPoint(new IntPoint(Std.int(Math.round(point.x)), Std.int(Math.round(point.y))));			
		}			
		for (point in clipPolygonFloat) 
		{				
			clipPolygon.addPoint(new IntPoint(Std.int(Math.round(point.x)), Std.int(Math.round(point.y))));			
		}
		
		var clipperObj:Clipper = new Clipper();
		clipperObj.addPolygon(subjectPolygon, PolyType.SUBJECT);
		clipperObj.addPolygon(clipPolygon, PolyType.CLIP);
		
		var solution:Polygons = new Polygons();
		clipperObj.execute(clipType, solution, PolyFillType.EVEN_ODD, PolyFillType.EVEN_ODD);
		var ret:Array<Array<Point>> = new Array<Array<Point>>();			
		for (solutionPoly in solution.getPolygons()) 
		{
			var n:Int = solutionPoly.getSize();
			var points:Array<Point> = new Array<Point>();				
			for (i in 0...n) 
			{
				var p:IntPoint = solutionPoly.getPoint(i);
				points[i] = new Point(p.X, p.Y);
			}				
			ret.push(points);			
		}			
		return ret;
	}
	
	
	private var m_PolyOuts: Array<OutRec>;
	private var m_ClipType: Int; //ClipType 
	private var m_Scanbeam: Scanbeam;
	private var m_ActiveEdges: TEdge;
	private var m_SortedEdges: TEdge;
	private var m_IntersectNodes: IntersectNode;
	private var m_ExecuteLocked: Bool;
	private var m_ClipFillType: Int; //PolyFillType 
	private var m_SubjFillType: Int; //PolyFillType 
	private var m_Joins: Array<JoinRec>;
	private var m_HorizJoins: Array<HorzJoinRec>;
	private var m_ReverseOutput: Bool;
	
	
	public function new() 
	{
		super();
		
		m_Scanbeam = null;
		m_ActiveEdges = null;
		m_SortedEdges = null;
		m_IntersectNodes = null;
		m_ExecuteLocked = false;
		m_PolyOuts = new Array<OutRec>();
		m_Joins = new Array<JoinRec>();
		m_HorizJoins = new Array<HorzJoinRec>();
		m_ReverseOutput = false;
	}
	
	override public function clear()
	{
		if (m_edges.length == 0) return; //avoids problems with ClipperBase destructor
		disposeAllPolyPts();
		super.clear();
	}
	
	private function disposeScanbeamList()
	{
		while ( m_Scanbeam != null ) 
		{
			var sb2: Scanbeam = m_Scanbeam.next;
			m_Scanbeam = null;
			m_Scanbeam = sb2;
		}
	}
	
	override function reset() 
	{
		super.reset();
		m_Scanbeam = null;
		m_ActiveEdges = null;
		m_SortedEdges = null;
		disposeAllPolyPts();
		var lm: LocalMinima = m_MinimaList;
		while (lm != null)
		{
			insertScanbeam(lm.Y);
			insertScanbeam(lm.leftBound.ytop);
			lm = lm.next;
		}
	}
	
	inline public function setReverseSolution( reverse: Bool )
	{
		m_ReverseOutput = reverse;
	}
	
	inline public function getReverseSolution(): Bool
	{
		return m_ReverseOutput;
	}
	
	private function insertScanbeam( Y: Int )
	{
		if (m_Scanbeam == null)
		{
			m_Scanbeam = new Scanbeam();
			m_Scanbeam.next = null;
			m_Scanbeam.Y = Y;
		}
		else if (Y > m_Scanbeam.Y)
		{
			var newSb: Scanbeam = new Scanbeam();
			newSb.Y = Y;
			newSb.next = m_Scanbeam;
			m_Scanbeam = newSb;
		} 
		else
		{
			var sb2: Scanbeam = m_Scanbeam;
			while( sb2.next != null  && ( Y <= sb2.next.Y ) ) sb2 = sb2.next;
			if(  Y == sb2.Y ) return; //ie ignores duplicates
			var newSb: Scanbeam = new Scanbeam();
			newSb.Y = Y;
			newSb.next = sb2.next;
			sb2.next = newSb;
		}
	}
	
	public function execute(
			clipType: Int,//ClipType
			solution: Polygons,
			subjFillType: Int,//PolyFillType 
			clipFillType: Int //PolyFillType 
			): Bool
	{
		if (m_ExecuteLocked) return false;
		m_ExecuteLocked = true;
		solution.clear();
		m_SubjFillType = subjFillType;
		m_ClipFillType = clipFillType;
		m_ClipType = clipType;
		var succeeded: Bool = executeInternal(false);
		//build the return polygons ...
		if (succeeded) buildResult(solution);
		m_ExecuteLocked = false;
		return succeeded;
	}
	
	function findAppendLinkEnd( outRec: OutRec ): OutRec 
	{
		while (outRec.appendLink != null) outRec = outRec.appendLink;
		return outRec;
	}
	
	function fixHoleLinkage( outRec: OutRec )
	{
		var tmp: OutRec;
		if (outRec.bottomPt != null) 
			tmp = m_PolyOuts[outRec.bottomPt.idx].firstLeft; 
		else
			tmp = outRec.firstLeft;
		if (outRec == tmp) throw new ClipperException("HoleLinkage error");

		if (tmp != null) 
		{
			if (tmp.appendLink != null) tmp = findAppendLinkEnd(tmp);

			if (tmp == outRec) tmp = null;
			else if (tmp.isHole)
			{
				fixHoleLinkage(tmp);
				tmp = tmp.firstLeft;
			}
		}
		outRec.firstLeft = tmp;
		if (tmp == null) outRec.isHole = false;
		outRec.appendLink = null;
	}
	
	private function executeInternal( fixHoleLinkages: Bool): Bool
	{
		var succeeded: Bool;
		try
		{
			reset();
			if (m_CurrentLM == null) return true;
			var botY: Int = popScanbeam();
			do
			{
				insertLocalMinimaIntoAEL(botY);
				m_HorizJoins.splice(0, m_HorizJoins.length); //clear;
				processHorizontals();
				var topY:Int = popScanbeam();
				succeeded = processIntersections(botY, topY);
				if (!succeeded) break;
				processEdgesAtTopOfScanbeam(topY);
				botY = topY;
			} while (m_Scanbeam != null);
		}
		catch (e: Error) 
		{ 
			succeeded = false; 
		}

		if (succeeded)
		{ 
			//tidy up output polygons and fix orientations where necessary ...
			for (outRec in m_PolyOuts)
			{
				if (outRec.pts == null) continue;
				fixupOutPolygon(outRec);
				if (outRec.pts == null) continue;
				if (outRec.isHole && fixHoleLinkages) fixHoleLinkage(outRec);

				if (outRec.bottomPt == outRec.bottomFlag &&
					(orientationOutRec(outRec, m_UseFullRange) != (areaOutRec(outRec, m_UseFullRange) > 0)))
				{
					disposeBottomPt(outRec);
				}

				if (outRec.isHole == ClipperBase.xor(m_ReverseOutput, orientationOutRec(outRec, m_UseFullRange)))
				{
					reversePolyPtLinks(outRec.pts);
				}
			}

			joinCommonEdges(fixHoleLinkages);
			if (fixHoleLinkages) m_PolyOuts.sort(polySort);
		}
		m_Joins.splice(0, m_Joins.length); // clear
		m_HorizJoins.splice(0, m_HorizJoins.length); // clear
		return succeeded;
	}
	
	private static function polySort(or1: OutRec, or2: OutRec): Int
	{
		if (or1 == or2)
		{
			return 0;
		}
		else if (or1.pts == null || or2.pts == null)
		{
			if ((or1.pts == null) != (or2.pts == null))
			{
				return or1.pts == null ? 1 : -1;
			}
			else return 0;          
		}
		
		var i1: Int;
		var i2: Int;
		if (or1.isHole)
			i1 = or1.firstLeft.idx; 
		else
			i1 = or1.idx;
			
		if (or2.isHole)
			i2 = or2.firstLeft.idx; 
		else
			i2 = or2.idx;
			
		var result: Int = i1 - i2;
		if (result == 0 && (or1.isHole != or2.isHole))
		{
			return or1.isHole ? 1 : -1;
		}
		return result;
	}
	
	inline private function popScanbeam(): Int
	{
		var Y: Int = m_Scanbeam.Y;
		var sb2: Scanbeam = m_Scanbeam;
		m_Scanbeam = m_Scanbeam.next;
		sb2 = null;
		return Y;
	}
	
	inline private function disposeAllPolyPts()
	{
		for ( i in 0...m_PolyOuts.length ) disposeOutRec(i);
		m_PolyOuts.splice(0, m_PolyOuts.length);
	}
	
	private function disposeBottomPt( outRec: OutRec )
	{
		var next:OutPt = outRec.bottomPt.next;
		var prev:OutPt = outRec.bottomPt.prev;
		if (outRec.pts == outRec.bottomPt) outRec.pts = next;
		outRec.bottomPt = null;
		next.prev = prev;
		prev.next = next;
		outRec.bottomPt = next;
		fixupOutPolygon(outRec);
	}
	
	function disposeOutRec( index: Int)
	{
	  var outRec:OutRec = m_PolyOuts[index];
	  if (outRec.pts != null) disposeOutPts(outRec.pts);
	  outRec = null;
	  m_PolyOuts[index] = null;
	}
	
	private function disposeOutPts(pp:OutPt)
	{
		if (pp == null) return;
		var tmpPp:OutPt = null;
		pp.prev.next = null;
		while (pp != null)
		{
			tmpPp = pp;
			pp = pp.next;
			tmpPp = null;
		}
	}
	
	private function addJoin(e1:TEdge, e2:TEdge, e1OutIdx:Int, e2OutIdx:Int)
	{
		var jr:JoinRec = new JoinRec();
		if (e1OutIdx >= 0)
			jr.poly1Idx = e1OutIdx; else
		jr.poly1Idx = e1.outIdx;
		jr.pt1a = new IntPoint(e1.xcurr, e1.ycurr);
		jr.pt1b = new IntPoint(e1.xtop, e1.ytop);
		if (e2OutIdx >= 0)
			jr.poly2Idx = e2OutIdx; else
			jr.poly2Idx = e2.outIdx;
		jr.pt2a = new IntPoint(e2.xcurr, e2.ycurr);
		jr.pt2b = new IntPoint(e2.xtop, e2.ytop);
		m_Joins.push(jr);
	}
	
	private function addHorzJoin(e:TEdge, idx:Int)
	{
		var hj:HorzJoinRec = new HorzJoinRec();
		hj.edge = e;
		hj.savedIdx = idx;
		m_HorizJoins.push(hj);
	}
	
	private function insertLocalMinimaIntoAEL(botY:Int)
	{
		while(  m_CurrentLM != null  && ( m_CurrentLM.Y == botY ) )
		{
			var lb:TEdge = m_CurrentLM.leftBound;
			var rb:TEdge = m_CurrentLM.rightBound;

			insertEdgeIntoAEL( lb );
			insertScanbeam( lb.ytop );
			insertEdgeIntoAEL( rb );

			if (isEvenOddFillType(lb))
			{
				lb.windDelta = 1;
				rb.windDelta = 1;
			}
			else
			{
				rb.windDelta = -lb.windDelta;
			}
			setWindingCount(lb);
			rb.windCnt = lb.windCnt;
			rb.windCnt2 = lb.windCnt2;

			if(  rb.dx == ClipperBase.horizontal )
			{
				//nb: only rightbounds can have a horizontal bottom edge
				addEdgeToSEL( rb );
				insertScanbeam( rb.nextInLML.ytop );
			}
			else
				insertScanbeam( rb.ytop );

			if( isContributing(lb) )
				addLocalMinPoly(lb, rb, new IntPoint(lb.xcurr, m_CurrentLM.Y));

			//if any output polygons share an edge, they'll need joining later ...
			if (rb.outIdx >= 0)
			{
				if (rb.dx == ClipperBase.horizontal)
				{
					for ( i in 0...m_HorizJoins.length )
					{
						var hj:HorzJoinRec = m_HorizJoins[i];
						//if horizontals rb and hj.edge overlap, flag for joining later ...
						var pt1a:IntPoint = new IntPoint(hj.edge.xbot, hj.edge.ybot);
						var pt1b:IntPoint = new IntPoint(hj.edge.xtop, hj.edge.ytop);
						var pt2a:IntPoint =	new IntPoint(rb.xbot, rb.ybot);
						var pt2b:IntPoint =	new IntPoint(rb.xtop, rb.ytop); 
						if (getOverlapSegment(new Segment(pt1a, pt1b), new Segment(pt2a, pt2b), new Segment(null, null)))
						{
							addJoin(hj.edge, rb, hj.savedIdx, -1);
						}
					}
				}
			}


			if( lb.nextInAEL != rb )
			{
				if (rb.outIdx >= 0 && rb.prevInAEL.outIdx >= 0 && 
					slopesEqual(rb.prevInAEL, rb, m_UseFullRange))
				{
					addJoin(rb, rb.prevInAEL, -1, -1);
				}
				var e:TEdge = lb.nextInAEL;
				var pt:IntPoint = new IntPoint(lb.xcurr, lb.ycurr);
				while( e != rb )
				{
					if(e == null) 
						throw new ClipperException("InsertLocalMinimaIntoAEL: missing rightbound!");
					//nb: For calculating winding counts etc, IntersectEdges() assumes
					//that param1 will be to the right of param2 ABOVE the intersection ...
					intersectEdges( rb , e , pt , Protects.NONE); //order important here
					e = e.nextInAEL;
				}
			}
			popLocalMinima();
		}
	}
	
	private function insertEdgeIntoAEL(edge:TEdge)
	{
		edge.prevInAEL = null;
		edge.nextInAEL = null;
		if (m_ActiveEdges == null)
		{
			m_ActiveEdges = edge;
		}
		else if( E2InsertsBeforeE1(m_ActiveEdges, edge) )
		{
			edge.nextInAEL = m_ActiveEdges;
			m_ActiveEdges.prevInAEL = edge;
			m_ActiveEdges = edge;
		} 
		else
		{
			var e:TEdge = m_ActiveEdges;
			while (e.nextInAEL != null && !E2InsertsBeforeE1(e.nextInAEL, edge))
			  e = e.nextInAEL;
			edge.nextInAEL = e.nextInAEL;
			if (e.nextInAEL != null) e.nextInAEL.prevInAEL = edge;
			edge.prevInAEL = e;
			e.nextInAEL = edge;
		}
	}
	
	inline private function E2InsertsBeforeE1(e1:TEdge, e2:TEdge):Bool
	{
		return e2.xcurr == e1.xcurr? e2.dx > e1.dx : e2.xcurr < e1.xcurr;
	}
	
	inline private function isEvenOddFillType(edge:TEdge):Bool
	{
	  if (edge.polyType == PolyType.SUBJECT)
		  return m_SubjFillType == PolyFillType.EVEN_ODD; 
	  else
		  return m_ClipFillType == PolyFillType.EVEN_ODD;
	}
	
	inline private function isEvenOddAltFillType(edge:TEdge):Bool
	{
	  if (edge.polyType == PolyType.SUBJECT)
		  return m_ClipFillType == PolyFillType.EVEN_ODD; 
	  else
		  return m_SubjFillType == PolyFillType.EVEN_ODD;
	}
	
	private function isContributing(edge:TEdge):Bool
	{
		var pft:Int;
		var pft2:Int; //PolyFillType
		if (edge.polyType == PolyType.SUBJECT)
		{
			pft = m_SubjFillType;
			pft2 = m_ClipFillType;
		}
		else
		{
			pft = m_ClipFillType;
			pft2 = m_SubjFillType;
		}

		switch (pft)
		{
			case PolyFillType.EVEN_ODD:
				if (ClipperBase.abs(edge.windCnt) != 1) return false;
				
			case PolyFillType.NON_ZERO:
				if (ClipperBase.abs(edge.windCnt) != 1) return false;
				
			case PolyFillType.POSITIVE:
				if (edge.windCnt != 1) return false;
				
			default: //PolyFillType.NEGATIVE
				if (edge.windCnt != -1) return false; 
				
		}

		switch (m_ClipType)
		{
			case ClipType.INTERSECTION:
				switch (pft2)
				{
					case PolyFillType.EVEN_ODD:
						return (edge.windCnt2 != 0);
					case PolyFillType.NON_ZERO:
						return (edge.windCnt2 != 0);
					case PolyFillType.POSITIVE:
						return (edge.windCnt2 > 0);
					default:
						return (edge.windCnt2 < 0);
				}
			case ClipType.UNION:
				switch (pft2)
				{
					case PolyFillType.EVEN_ODD:
						return (edge.windCnt2 == 0);
					case PolyFillType.NON_ZERO:
						return (edge.windCnt2 == 0);
					case PolyFillType.POSITIVE:
						return (edge.windCnt2 <= 0);
					default:
						return (edge.windCnt2 >= 0);
				}
			case ClipType.DIFFERENCE:
				if (edge.polyType == PolyType.SUBJECT)
					switch (pft2)
					{
						case PolyFillType.EVEN_ODD:
							return (edge.windCnt2 == 0);
						case PolyFillType.NON_ZERO:
							return (edge.windCnt2 == 0);
						case PolyFillType.POSITIVE:
							return (edge.windCnt2 <= 0);
						default:
							return (edge.windCnt2 >= 0);
					}
				else
					switch (pft2)
					{
						case PolyFillType.EVEN_ODD:
							return (edge.windCnt2 != 0);
						case PolyFillType.NON_ZERO:
							return (edge.windCnt2 != 0);
						case PolyFillType.POSITIVE:
							return (edge.windCnt2 > 0);
						default:
							return (edge.windCnt2 < 0);
					}
		}
		return true;
	}
	
	private function setWindingCount(edge:TEdge)
	{
		var e:TEdge = edge.prevInAEL;
		//find the edge of the same polytype that immediately preceeds 'edge' in AEL
		while (e != null && e.polyType != edge.polyType)
			e = e.prevInAEL;
		if (e == null)
		{
			edge.windCnt = edge.windDelta;
			edge.windCnt2 = 0;
			e = m_ActiveEdges; //ie get ready to calc windCnt2
		}
		else if (isEvenOddFillType(edge))
		{
			//even-odd filling ...
			edge.windCnt = 1;
			edge.windCnt2 = e.windCnt2;
			e = e.nextInAEL; //ie get ready to calc windCnt2
		}
		else
		{
			//nonZero filling ...
			if (e.windCnt * e.windDelta < 0)
			{
				if (ClipperBase.abs(e.windCnt) > 1)
				{
					if (e.windDelta * edge.windDelta < 0)
						edge.windCnt = e.windCnt;
					else
						edge.windCnt = e.windCnt + edge.windDelta;
				}
				else
					edge.windCnt = e.windCnt + e.windDelta + edge.windDelta;
			}
			else
			{
				if (ClipperBase.abs(e.windCnt) > 1 && e.windDelta * edge.windDelta < 0)
					edge.windCnt = e.windCnt;
				else if (e.windCnt + edge.windDelta == 0)
					edge.windCnt = e.windCnt;
				else
					edge.windCnt = e.windCnt + edge.windDelta;
			}
			edge.windCnt2 = e.windCnt2;
			e = e.nextInAEL; //ie get ready to calc windCnt2
		}

		//update windCnt2 ...
		if (isEvenOddAltFillType(edge))
		{
			//even-odd filling ...
			while (e != edge)
			{
				edge.windCnt2 = (edge.windCnt2 == 0) ? 1 : 0;
				e = e.nextInAEL;
			}
		}
		else
		{
			//nonZero filling ...
			while (e != edge)
			{
				edge.windCnt2 += e.windDelta;
				e = e.nextInAEL;
			}
		}
	}
	
	private function addEdgeToSEL(edge:TEdge)
	{
		//SEL pointers in PEdge are reused to build a list of horizontal edges.
		//However, we don't need to worry about order with horizontal edge processing.
		if (m_SortedEdges == null)
		{
			m_SortedEdges = edge;
			edge.prevInSEL = null;
			edge.nextInSEL = null;
		}
		else
		{
			edge.nextInSEL = m_SortedEdges;
			edge.prevInSEL = null;
			m_SortedEdges.prevInSEL = edge;
			m_SortedEdges = edge;
		}
	}
	
	private function copyAELToSEL()
	{
		var e:TEdge = m_ActiveEdges;
		m_SortedEdges = e;
		if (m_ActiveEdges == null)
			return;
		m_SortedEdges.prevInSEL = null;
		e = e.nextInAEL;
		while (e != null)
		{
			e.prevInSEL = e.prevInAEL;
			e.prevInSEL.nextInSEL = e;
			e.nextInSEL = null;
			e = e.nextInAEL;
		}
	}
	
	private function swapPositionsInAEL(edge1:TEdge, edge2:TEdge)
	{
		if (edge1.nextInAEL == null && edge1.prevInAEL == null)
			return;
		if (edge2.nextInAEL == null && edge2.prevInAEL == null)
			return;

		if (edge1.nextInAEL == edge2)
		{
			var next:TEdge = edge2.nextInAEL;
			if (next != null)
				next.prevInAEL = edge1;
			var prev:TEdge = edge1.prevInAEL;
			if (prev != null)
				prev.nextInAEL = edge2;
			edge2.prevInAEL = prev;
			edge2.nextInAEL = edge1;
			edge1.prevInAEL = edge2;
			edge1.nextInAEL = next;
		}
		else if (edge2.nextInAEL == edge1)
		{
			var next = edge1.nextInAEL;
			if (next != null)
				next.prevInAEL = edge2;
			var prev = edge2.prevInAEL;
			if (prev != null)
				prev.nextInAEL = edge1;
			edge1.prevInAEL = prev;
			edge1.nextInAEL = edge2;
			edge2.prevInAEL = edge1;
			edge2.nextInAEL = next;
		}
		else
		{
			var next = edge1.nextInAEL;
			var prev = edge1.prevInAEL;
			edge1.nextInAEL = edge2.nextInAEL;
			if (edge1.nextInAEL != null)
				edge1.nextInAEL.prevInAEL = edge1;
			edge1.prevInAEL = edge2.prevInAEL;
			if (edge1.prevInAEL != null)
				edge1.prevInAEL.nextInAEL = edge1;
			edge2.nextInAEL = next;
			if (edge2.nextInAEL != null)
				edge2.nextInAEL.prevInAEL = edge2;
			edge2.prevInAEL = prev;
			if (edge2.prevInAEL != null)
				edge2.prevInAEL.nextInAEL = edge2;
		}

		if (edge1.prevInAEL == null)
			m_ActiveEdges = edge1;
		else if (edge2.prevInAEL == null)
			m_ActiveEdges = edge2;
	}
	
	private function swapPositionsInSEL(edge1:TEdge, edge2:TEdge)
	{
		if (edge1.nextInSEL == null && edge1.prevInSEL == null)
			return;
		if (edge2.nextInSEL == null && edge2.prevInSEL == null)
			return;

		if (edge1.nextInSEL == edge2)
		{
			var next:TEdge = edge2.nextInSEL;
			if (next != null)
				next.prevInSEL = edge1;
			var prev:TEdge = edge1.prevInSEL;
			if (prev != null)
				prev.nextInSEL = edge2;
			edge2.prevInSEL = prev;
			edge2.nextInSEL = edge1;
			edge1.prevInSEL = edge2;
			edge1.nextInSEL = next;
		}
		else if (edge2.nextInSEL == edge1)
		{
			var next = edge1.nextInSEL;
			if (next != null)
				next.prevInSEL = edge2;
			var prev = edge2.prevInSEL;
			if (prev != null)
				prev.nextInSEL = edge1;
			edge1.prevInSEL = prev;
			edge1.nextInSEL = edge2;
			edge2.prevInSEL = edge1;
			edge2.nextInSEL = next;
		}
		else
		{
			var next = edge1.nextInSEL;
			var prev = edge1.prevInSEL;
			edge1.nextInSEL = edge2.nextInSEL;
			if (edge1.nextInSEL != null)
				edge1.nextInSEL.prevInSEL = edge1;
			edge1.prevInSEL = edge2.prevInSEL;
			if (edge1.prevInSEL != null)
				edge1.prevInSEL.nextInSEL = edge1;
			edge2.nextInSEL = next;
			if (edge2.nextInSEL != null)
				edge2.nextInSEL.prevInSEL = edge2;
			edge2.prevInSEL = prev;
			if (edge2.prevInSEL != null)
				edge2.prevInSEL.nextInSEL = edge2;
		}

		if (edge1.prevInSEL == null)
			m_SortedEdges = edge1;
		else if (edge2.prevInSEL == null)
			m_SortedEdges = edge2;
	}
	
	private function addLocalMaxPoly(e1:TEdge, e2:TEdge, pt:IntPoint)
	{
		addOutPt(e1, pt);
		if (e1.outIdx == e2.outIdx)
		{
			e1.outIdx = -1;
			e2.outIdx = -1;
		}
		else if (e1.outIdx < e2.outIdx) 
			appendPolygon(e1, e2);
		else 
			appendPolygon(e2, e1);
	}
	
	private function addLocalMinPoly(e1:TEdge, e2:TEdge, pt:IntPoint)
	{
		var e:TEdge, prevE:TEdge;
		if (e2.dx == ClipperBase.horizontal || (e1.dx > e2.dx))
		{
			addOutPt(e1, pt);
			e2.outIdx = e1.outIdx;
			e1.side = EdgeSide.LEFT;
			e2.side = EdgeSide.RIGHT;
			e = e1;
			if (e.prevInAEL == e2)
			  prevE = e2.prevInAEL; 
			else
			  prevE = e.prevInAEL;
		}
		else
		{
			addOutPt(e2, pt);
			e1.outIdx = e2.outIdx;
			e1.side = EdgeSide.RIGHT;
			e2.side = EdgeSide.LEFT;
			e = e2;
			if (e.prevInAEL == e1)
				prevE = e1.prevInAEL;
			else
				prevE = e.prevInAEL;
		}

		if (prevE != null && prevE.outIdx >= 0 &&
			(topX(prevE, pt.Y) == topX(e, pt.Y)) &&
			 slopesEqual(e, prevE, m_UseFullRange))
			   addJoin(e, prevE, -1, -1);
	}
	
	private function createOutRec():OutRec
	{
		var result:OutRec = new OutRec();
		result.idx = -1;
		result.isHole = false;
		result.firstLeft = null;
		result.appendLink = null;
		result.pts = null;
		result.bottomPt = null;
		result.bottomFlag = null;
		result.sides = EdgeSide.NEITHER;
		return result;
	}
	
	private function addOutPt(e:TEdge, pt:IntPoint)
	{
		var toFront:Bool = (e.side == EdgeSide.LEFT);
		if (e.outIdx < 0)
		{
			var outRec:OutRec = createOutRec();
			m_PolyOuts.push(outRec);
			outRec.idx = m_PolyOuts.length -1;
			e.outIdx = outRec.idx;
			var op:OutPt = new OutPt();
			outRec.pts = op;
			outRec.bottomPt = op;
			op.pt = pt;
			op.idx = outRec.idx;
			op.next = op;
			op.prev = op;
			setHoleState(e, outRec);
		} 
		else
		{
			var outRec = m_PolyOuts[e.outIdx];
			var op = outRec.pts;
			var op2:OutPt;
			var opBot:OutPt;
			if (toFront && ClipperBase.pointsEqual(pt, op.pt) || 
			  (!toFront && ClipperBase.pointsEqual(pt, op.prev.pt)))
			{
				return;
			}

			if ((e.side | outRec.sides) != outRec.sides)
			{
				//check for 'rounding' artefacts ...
				if (outRec.sides == EdgeSide.NEITHER && pt.Y == op.pt.Y)
				if (toFront)
				{
					if (pt.X == op.pt.X + 1) return;    //ie wrong side of bottomPt
				}
				else if (pt.X == op.pt.X - 1) return; //ie wrong side of bottomPt

				outRec.sides = outRec.sides | e.side;
				if (outRec.sides == EdgeSide.BOTH)
				{
					//A vertex from each side has now been added.
					//Vertices of one side of an output polygon are quite commonly close to
					//or even 'touching' edges of the other side of the output polygon.
					//Very occasionally vertices from one side can 'cross' an edge on the
					//the other side. The distance 'crossed' is always less that a unit
					//and is purely an artefact of coordinate rounding. Nevertheless, this
					//results in very tiny self-intersections. Because of the way
					//orientation is calculated, even tiny self-intersections can cause
					//the Orientation function to return the wrong result. Therefore, it's
					//important to ensure that any self-intersections close to BottomPt are
					//detected and removed before orientation is assigned.

					if (toFront)
					{
						opBot = outRec.pts;
						op2 = opBot.next; //op2 == right side
						if (opBot.pt.Y != op2.pt.Y && opBot.pt.Y != pt.Y &&
							((opBot.pt.X - pt.X) / (opBot.pt.Y - pt.Y) <
							(opBot.pt.X - op2.pt.X) / (opBot.pt.Y - op2.pt.Y)))
						{
							outRec.bottomFlag = opBot;
						}
					}
					else
					{
						opBot = outRec.pts.prev;
						op2 = opBot.next; //op2 == left side
						if (opBot.pt.Y != op2.pt.Y && opBot.pt.Y != pt.Y &&
						  ((opBot.pt.X - pt.X) / (opBot.pt.Y - pt.Y) >
						   (opBot.pt.X - op2.pt.X) / (opBot.pt.Y - op2.pt.Y)))
						{
							outRec.bottomFlag = opBot;
						}
					}
				}
			}

			op2 = new OutPt();
			op2.pt = pt;
			op2.idx = outRec.idx;
			if (op2.pt.Y == outRec.bottomPt.pt.Y &&
				op2.pt.X < outRec.bottomPt.pt.X)
			{
				outRec.bottomPt = op2;
			}
			op2.next = op;
			op2.prev = op.prev;
			op2.prev.next = op2;
			op.prev = op2;
			if (toFront) outRec.pts = op2;
		}
	}
	
	private function getOverlapSegment(seg1:Segment, seg2:Segment, seg:Segment):Bool
	{
		//precondition: segments are colinear.
		if ( seg1.pt1.Y == seg1.pt2.Y || ClipperBase.abs(Std.int((seg1.pt1.X - seg1.pt2.X)/(seg1.pt1.Y - seg1.pt2.Y))) > 1 )
		{
			if (seg1.pt1.X > seg1.pt2.X) seg1.swapPoints();
			if (seg2.pt1.X > seg2.pt2.X) seg2.swapPoints();
			if (seg1.pt1.X > seg2.pt1.X) seg.pt1 = seg1.pt1; else seg.pt1 = seg2.pt1;
			if (seg1.pt2.X < seg2.pt2.X) seg.pt2 = seg1.pt2; else seg.pt2 = seg2.pt2;
			return seg.pt1.X < seg.pt2.X;
		} 
		else
		{
			if (seg1.pt1.Y < seg1.pt2.Y) seg1.swapPoints();
			if (seg2.pt1.Y < seg2.pt2.Y) seg2.swapPoints();
			if (seg1.pt1.Y < seg2.pt1.Y) seg.pt1 = seg1.pt1; else seg.pt1 = seg2.pt1;
			if (seg1.pt2.Y > seg2.pt2.Y) seg.pt2 = seg1.pt2; else seg.pt2 = seg2.pt2;
			return seg.pt1.Y > seg.pt2.Y;
		}
	}
	
	private function findSegment(ppRef:OutPtRef, seg:Segment):Bool
	{
		var pp:OutPt = ppRef.outPt;
		if (pp == null) return false;
		var pp2:OutPt = pp;
		var pt1a:IntPoint = seg.pt1;
		var pt2a:IntPoint = seg.pt2;
		var seg1:Segment = new Segment(pt1a, pt2a);
		do
		{
			var seg2:Segment = new Segment(pp.pt, pp.prev.pt);
			if (slopesEqual4(pt1a, pt2a, pp.pt, pp.prev.pt, true) &&
				slopesEqual3(pt1a, pt2a, pp.pt, true) &&
				getOverlapSegment(seg1, seg2, seg))
			{
				return true;
			}
			pp = pp.next;
			ppRef.outPt = pp; // update the reference for the caller.
		} while (pp != pp2);
		return false;
	}
	
	inline function pt3IsBetweenPt1AndPt2(pt1:IntPoint, pt2:IntPoint, pt3:IntPoint):Bool
	{
		if (ClipperBase.pointsEqual(pt1, pt3) || ClipperBase.pointsEqual(pt2, pt3)) return true;
		else if (pt1.X != pt2.X) return (pt1.X < pt3.X) == (pt3.X < pt2.X);
		else return (pt1.Y < pt3.Y) == (pt3.Y < pt2.Y);
	}
	
	private function insertPolyPtBetween(p1:OutPt, p2:OutPt, pt:IntPoint):OutPt
	{
		var result:OutPt = new OutPt();
		result.pt = pt;
		if (p2 == p1.next)
		{
			p1.next = result;
			p2.prev = result;
			result.next = p2;
			result.prev = p1;
		} else
		{
			p2.next = result;
			p1.prev = result;
			result.next = p1;
			result.prev = p2;
		}
		return result;
	}
	
	private function setHoleState(e:TEdge, outRec:OutRec)
	{
		var isHole:Bool = false;
		var e2:TEdge = e.prevInAEL;
		while (e2 != null)
		{
			if (e2.outIdx >= 0)
			{
				isHole = !isHole;
				if (outRec.firstLeft == null)
					outRec.firstLeft = m_PolyOuts[e2.outIdx];
			}
			e2 = e2.prevInAEL;
		}
		if (isHole) outRec.isHole = true;
	}
	
	inline private function getDx(pt1:IntPoint, pt2:IntPoint): Float
	{
		if (pt1.Y == pt2.Y) return ClipperBase.horizontal;
		else return (pt2.X - pt1.X) / (pt2.Y - pt1.Y);
	}
	
	private function firstIsBottomPt(btmPt1:OutPt, btmPt2:OutPt):Bool
	{
		var p:OutPt = btmPt1.prev;
		while (ClipperBase.pointsEqual(p.pt, btmPt1.pt) && (p != btmPt1)) p = p.prev;
		var dx1p:Float = Math.abs(getDx(btmPt1.pt, p.pt));
		p = btmPt1.next;
		while (ClipperBase.pointsEqual(p.pt, btmPt1.pt) && (p != btmPt1)) p = p.next;
		var dx1n:Float = Math.abs(getDx(btmPt1.pt, p.pt));

		p = btmPt2.prev;
		while (ClipperBase.pointsEqual(p.pt, btmPt2.pt) && (p != btmPt2)) p = p.prev;
		var dx2p:Float = Math.abs(getDx(btmPt2.pt, p.pt));
		p = btmPt2.next;
		while (ClipperBase.pointsEqual(p.pt, btmPt2.pt) && (p != btmPt2)) p = p.next;
		var dx2n:Float = Math.abs(getDx(btmPt2.pt, p.pt));
		return (dx1p >= dx2p && dx1p >= dx2n) || (dx1n >= dx2p && dx1n >= dx2n);
	}
	
	private function getBottomPt(pp:OutPt):OutPt
	{
		var dups:OutPt = null;
		var p:OutPt = pp.next;
		while (p != pp)
		{
			if (p.pt.Y > pp.pt.Y)
			{
				pp = p;
				dups = null;
			}
			else if (p.pt.Y == pp.pt.Y && p.pt.X <= pp.pt.X)
			{
				if (p.pt.X < pp.pt.X)
				{
					dups = null;
					pp = p;
				} 
				else
				{
					if (p.next != pp && p.prev != pp) dups = p;
				}
			}
			p = p.next;
		}
		if (dups != null)
		{
			//there appears to be at least 2 vertices at bottomPt so ...
			while (dups != p)
			{
				if (!firstIsBottomPt(p, dups)) pp = dups;
				dups = dups.next;
				while (!ClipperBase.pointsEqual(dups.pt, pp.pt)) dups = dups.next;
			}
		}
		return pp;
	}
	
	private function getLowermostRec(outRec1:OutRec, outRec2:OutRec):OutRec
	{
		//work out which polygon fragment has the correct hole state ...
		var bPt1:OutPt = outRec1.bottomPt;
		var bPt2:OutPt = outRec2.bottomPt;
		if (bPt1.pt.Y > bPt2.pt.Y) return outRec1;
		else if (bPt1.pt.Y < bPt2.pt.Y) return outRec2;
		else if (bPt1.pt.X < bPt2.pt.X) return outRec1;
		else if (bPt1.pt.X > bPt2.pt.X) return outRec2;
		else if (bPt1.next == bPt1) return outRec2;
		else if (bPt2.next == bPt2) return outRec1;
		else if (firstIsBottomPt(bPt1, bPt2)) return outRec1;
		else return outRec2;
	}
	
	private function param1RightOfParam2(outRec1:OutRec, outRec2:OutRec):Bool
	{
		do
		{
			outRec1 = outRec1.firstLeft;
			if (outRec1 == outRec2) return true;
		} while (outRec1 != null);
		return false;
	}
	
	private function appendPolygon(e1:TEdge, e2:TEdge)
	{
		//get the start and ends of both output polygons ...
		var outRec1:OutRec = m_PolyOuts[e1.outIdx];
		var outRec2:OutRec = m_PolyOuts[e2.outIdx];

		var holeStateRec:OutRec;
		if (param1RightOfParam2(outRec1, outRec2)) holeStateRec = outRec2;
		else if (param1RightOfParam2(outRec2, outRec1)) holeStateRec = outRec1;
		else holeStateRec = getLowermostRec(outRec1, outRec2);

		var p1_lft:OutPt = outRec1.pts;
		var p1_rt:OutPt = p1_lft.prev;
		var p2_lft:OutPt = outRec2.pts;
		var p2_rt:OutPt = p2_lft.prev;

		var side:Int; //EdgeSide
		//join e2 poly onto e1 poly and delete pointers to e2 ...
		if(  e1.side == EdgeSide.LEFT )
		{
			if (e2.side == EdgeSide.LEFT)
			{
				//z y x a b c
				reversePolyPtLinks(p2_lft);
				p2_lft.next = p1_lft;
				p1_lft.prev = p2_lft;
				p1_rt.next = p2_rt;
				p2_rt.prev = p1_rt;
				outRec1.pts = p2_rt;
			} 
			else
			{
				//x y z a b c
				p2_rt.next = p1_lft;
				p1_lft.prev = p2_rt;
				p2_lft.prev = p1_rt;
				p1_rt.next = p2_lft;
				outRec1.pts = p2_lft;
			}
			side = EdgeSide.LEFT;
		} 
		else
		{
			if (e2.side == EdgeSide.RIGHT)
			{
				//a b c z y x
				reversePolyPtLinks( p2_lft );
				p1_rt.next = p2_rt;
				p2_rt.prev = p1_rt;
				p2_lft.next = p1_lft;
				p1_lft.prev = p2_lft;
			} 
			else
			{
				//a b c x y z
				p1_rt.next = p2_lft;
				p2_lft.prev = p1_rt;
				p1_lft.prev = p2_rt;
				p2_rt.next = p1_lft;
			}
			side = EdgeSide.RIGHT;
		}

		if (holeStateRec == outRec2)
		{
			outRec1.bottomPt = outRec2.bottomPt;
			outRec1.bottomPt.idx = outRec1.idx;
			if (outRec2.firstLeft != outRec1)
			{
				outRec1.firstLeft = outRec2.firstLeft;
			}
			outRec1.isHole = outRec2.isHole;
		}
		outRec2.pts = null;
		outRec2.bottomPt = null;
		outRec2.appendLink = outRec1;
		var oKIdx:Int = e1.outIdx;
		var obsoleteIdx:Int = e2.outIdx;

		e1.outIdx = -1; //nb: safe because we only get here via AddLocalMaxPoly
		e2.outIdx = -1;

		var e:TEdge = m_ActiveEdges;
		while( e != null )
		{
			if( e.outIdx == obsoleteIdx )
			{
				e.outIdx = oKIdx;
				e.side = side;
				break;
			}
			e = e.nextInAEL;
		}

		for ( i in 0...m_Joins.length )
		{
			if (m_Joins[i].poly1Idx == obsoleteIdx) m_Joins[i].poly1Idx = oKIdx;
			if (m_Joins[i].poly2Idx == obsoleteIdx) m_Joins[i].poly2Idx = oKIdx;
		}

		for ( i in 0...m_HorizJoins.length )
		{
			if (m_HorizJoins[i].savedIdx == obsoleteIdx)
			{
				m_HorizJoins[i].savedIdx = oKIdx;
			}
		}
	}
	
	private function reversePolyPtLinks(pp:OutPt)
	{
		var pp1:OutPt;
		var pp2:OutPt;
		pp1 = pp;
		do
		{
			pp2 = pp1.next;
			pp1.next = pp1.prev;
			pp1.prev = pp2;
			pp1 = pp2;
		} while (pp1 != pp);
	}
	
	inline private static function swapSides(edge1:TEdge, edge2:TEdge)
	{
		var side:Int = edge1.side; //EdgeSide
		edge1.side = edge2.side;
		edge2.side = side;
	}
	
	inline private static function swapPolyIndexes(edge1:TEdge, edge2:TEdge)
	{
		var outIdx:Int = edge1.outIdx;
		edge1.outIdx = edge2.outIdx;
		edge2.outIdx = outIdx;
	}
	
	inline private function doEdge1(edge1:TEdge, edge2:TEdge, pt:IntPoint)
	{
		addOutPt(edge1, pt);
		swapSides(edge1, edge2);
		swapPolyIndexes(edge1, edge2);
	}
	
	inline private function doEdge2(edge1:TEdge, edge2:TEdge, pt:IntPoint)
	{
		addOutPt(edge2, pt);
		swapSides(edge1, edge2);
		swapPolyIndexes(edge1, edge2);
	}
	
	inline private function doBothEdges(edge1:TEdge, edge2:TEdge, pt:IntPoint)
	{
		addOutPt(edge1, pt);
		addOutPt(edge2, pt);
		swapSides(edge1, edge2);
		swapPolyIndexes(edge1, edge2);
	}
	
	private function intersectEdges(e1:TEdge, e2:TEdge, pt:IntPoint, protects:Int)
	{
		//e1 will be to the left of e2 BELOW the intersection. Therefore e1 is before
		//e2 in AEL except when e1 is being inserted at the intersection point ...

		var e1stops:Bool = (Protects.LEFT & protects) == 0 && e1.nextInLML == null &&
			e1.xtop == pt.X && e1.ytop == pt.Y;
		var e2stops:Bool = (Protects.RIGHT & protects) == 0 && e2.nextInLML == null &&
			e2.xtop == pt.X && e2.ytop == pt.Y;
		var e1Contributing:Bool = (e1.outIdx >= 0);
		var e2contributing:Bool = (e2.outIdx >= 0);

		//update winding counts...
		//assumes that e1 will be to the right of e2 ABOVE the intersection
		if (e1.polyType == e2.polyType)
		{
			if (isEvenOddFillType(e1))
			{
				var oldE1WindCnt:Int = e1.windCnt;
				e1.windCnt = e2.windCnt;
				e2.windCnt = oldE1WindCnt;
			}
			else
			{
				if (e1.windCnt + e2.windDelta == 0) e1.windCnt = -e1.windCnt;
				else e1.windCnt += e2.windDelta;
				if (e2.windCnt - e1.windDelta == 0) e2.windCnt = -e2.windCnt;
				else e2.windCnt -= e1.windDelta;
			}
		}
		else
		{
			if (!isEvenOddFillType(e2)) e1.windCnt2 += e2.windDelta;
			else e1.windCnt2 = (e1.windCnt2 == 0) ? 1 : 0;
			if (!isEvenOddFillType(e1)) e2.windCnt2 -= e1.windDelta;
			else e2.windCnt2 = (e2.windCnt2 == 0) ? 1 : 0;
		}

		var e1FillType:Int, e2FillType:Int, e1FillType2:Int, e2FillType2:Int; //PolyFillType 
		if (e1.polyType == PolyType.SUBJECT)
		{
			e1FillType = m_SubjFillType;
			e1FillType2 = m_ClipFillType;
		}
		else
		{
			e1FillType = m_ClipFillType;
			e1FillType2 = m_SubjFillType;
		}
		if (e2.polyType == PolyType.SUBJECT)
		{
			e2FillType = m_SubjFillType;
			e2FillType2 = m_ClipFillType;
		}
		else
		{
			e2FillType = m_ClipFillType;
			e2FillType2 = m_SubjFillType;
		}

		var e1Wc:Int, e2Wc:Int;
		switch (e1FillType)
		{
			case PolyFillType.POSITIVE: e1Wc = e1.windCnt;
			case PolyFillType.NEGATIVE: e1Wc = -e1.windCnt;
			default: e1Wc = ClipperBase.abs(e1.windCnt);
		}
		switch (e2FillType)
		{
			case PolyFillType.POSITIVE: e2Wc = e2.windCnt;
			case PolyFillType.NEGATIVE: e2Wc = -e2.windCnt; 
			default: e2Wc = ClipperBase.abs(e2.windCnt);
		}


		if (e1Contributing && e2contributing)
		{
			if ( e1stops || e2stops || 
			  (e1Wc != 0 && e1Wc != 1) || (e2Wc != 0 && e2Wc != 1) ||
			  (e1.polyType != e2.polyType && m_ClipType != ClipType.XOR))
				addLocalMaxPoly(e1, e2, pt);
			else
				doBothEdges(e1, e2, pt);
		}
		else if (e1Contributing)
		{
			if ((e2Wc == 0 || e2Wc == 1) && 
			  (m_ClipType != ClipType.INTERSECTION || 
				e2.polyType == PolyType.SUBJECT || (e2.windCnt2 != 0))) 
					doEdge1(e1, e2, pt);
		}
		else if (e2contributing)
		{
			if ((e1Wc == 0 || e1Wc == 1) &&
			  (m_ClipType != ClipType.INTERSECTION ||
							e1.polyType == PolyType.SUBJECT || (e1.windCnt2 != 0))) 
					doEdge2(e1, e2, pt);
		}
		else if ( (e1Wc == 0 || e1Wc == 1) && 
			(e2Wc == 0 || e2Wc == 1) && !e1stops && !e2stops )
		{
			//neither edge is currently contributing ...
			var e1Wc2:Int, e2Wc2:Int;
			switch (e1FillType2)
			{
				case PolyFillType.POSITIVE: e1Wc2 = e1.windCnt2; 
				case PolyFillType.NEGATIVE: e1Wc2 = -e1.windCnt2; 
				default: e1Wc2 = ClipperBase.abs(e1.windCnt2); 
			}
			switch (e2FillType2)
			{
				case PolyFillType.POSITIVE: e2Wc2 = e2.windCnt2; 
				case PolyFillType.NEGATIVE: e2Wc2 = -e2.windCnt2;
				default: e2Wc2 = ClipperBase.abs(e2.windCnt2); 
			}

			if (e1.polyType != e2.polyType)
				addLocalMinPoly(e1, e2, pt);
			else if (e1Wc == 1 && e2Wc == 1)
				switch (m_ClipType)
				{
					case ClipType.INTERSECTION:
						{
							if (e1Wc2 > 0 && e2Wc2 > 0)
								addLocalMinPoly(e1, e2, pt);
						}
					case ClipType.UNION:
						{
							if (e1Wc2 <= 0 && e2Wc2 <= 0)
								addLocalMinPoly(e1, e2, pt);
						}
					case ClipType.DIFFERENCE:
						{
							if (((e1.polyType == PolyType.CLIP) && (e1Wc2 > 0) && (e2Wc2 > 0)) ||
							   ((e1.polyType == PolyType.SUBJECT) && (e1Wc2 <= 0) && (e2Wc2 <= 0)))
									addLocalMinPoly(e1, e2, pt);
						}
					case ClipType.XOR:
						{
							addLocalMinPoly(e1, e2, pt);
						}
				}
			else 
				swapSides(e1, e2);
		}

		if ((e1stops != e2stops) &&
		  ((e1stops && (e1.outIdx >= 0)) || (e2stops && (e2.outIdx >= 0))))
		{
			swapSides(e1, e2);
			swapPolyIndexes(e1, e2);
		}

		//finally, delete any non-contributing maxima edges  ...
		if (e1stops) deleteFromAEL(e1);
		if (e2stops) deleteFromAEL(e2);
	}
	
	private function deleteFromAEL(e:TEdge)
	{
		var AelPrev:TEdge = e.prevInAEL;
		var AelNext:TEdge = e.nextInAEL;
		if (AelPrev == null && AelNext == null && (e != m_ActiveEdges))
			return; //already deleted
		if (AelPrev != null)
			AelPrev.nextInAEL = AelNext;
		else m_ActiveEdges = AelNext;
		if (AelNext != null)
			AelNext.prevInAEL = AelPrev;
		e.nextInAEL = null;
		e.prevInAEL = null;
	}
	
	private function deleteFromSEL(e:TEdge)
	{
		var SelPrev:TEdge = e.prevInSEL;
		var SelNext:TEdge = e.nextInSEL;
		if (SelPrev == null && SelNext == null && (e != m_SortedEdges))
			return; //already deleted
		if (SelPrev != null)
			SelPrev.nextInSEL = SelNext;
		else m_SortedEdges = SelNext;
		if (SelNext != null)
			SelNext.prevInSEL = SelPrev;
		e.nextInSEL = null;
		e.prevInSEL = null;
	}
	
	private function updateEdgeIntoAEL(e:TEdge):TEdge
	{
		if (e.nextInLML == null)
			throw new ClipperException("UpdateEdgeIntoAEL: invalid call");
		var AelPrev:TEdge = e.prevInAEL;
		var AelNext:TEdge  = e.nextInAEL;
		e.nextInLML.outIdx = e.outIdx;
		if (AelPrev != null)
			AelPrev.nextInAEL = e.nextInLML;
		else m_ActiveEdges = e.nextInLML;
		if (AelNext != null)
			AelNext.prevInAEL = e.nextInLML;
		e.nextInLML.side = e.side;
		e.nextInLML.windDelta = e.windDelta;
		e.nextInLML.windCnt = e.windCnt;
		e.nextInLML.windCnt2 = e.windCnt2;
		e = e.nextInLML;
		e.prevInAEL = AelPrev;
		e.nextInAEL = AelNext;
		if (e.dx != ClipperBase.horizontal) insertScanbeam(e.ytop);
		return e;
	}
	
	private function processHorizontals()
	{
		var horzEdge:TEdge = m_SortedEdges;
		while (horzEdge != null)
		{
			deleteFromSEL(horzEdge);
			processHorizontal(horzEdge);
			horzEdge = m_SortedEdges;
		}
	}
	
	private function processHorizontal(horzEdge:TEdge)
	{
		var direction:Int; // Direction
		var horzLeft:Int, horzRight:Int;

		if (horzEdge.xcurr < horzEdge.xtop)
		{
			horzLeft = horzEdge.xcurr;
			horzRight = horzEdge.xtop;
			direction = Direction.LEFT_TO_RIGHT;
		}
		else
		{
			horzLeft = horzEdge.xtop;
			horzRight = horzEdge.xcurr;
			direction = Direction.RIGHT_TO_LEFT;
		}

		var eMaxPair:TEdge;
		if (horzEdge.nextInLML != null)
			eMaxPair = null;
		else
			eMaxPair = getMaximaPair(horzEdge);

		var e:TEdge = getNextInAEL(horzEdge, direction);
		while (e != null)
		{
			var eNext:TEdge = getNextInAEL(e, direction);
			if (eMaxPair != null ||
			  ((direction == Direction.LEFT_TO_RIGHT) && (e.xcurr <= horzRight)) ||
			  ((direction == Direction.RIGHT_TO_LEFT) && (e.xcurr >= horzLeft)))
			{
				//ok, so far it looks like we're still in range of the horizontal edge
				if (e.xcurr == horzEdge.xtop && eMaxPair == null)
				{
					if (slopesEqual(e, horzEdge.nextInLML, m_UseFullRange))
					{
						//if output polygons share an edge, they'll need joining later ...
						if (horzEdge.outIdx >= 0 && e.outIdx >= 0)
							addJoin(horzEdge.nextInLML, e, horzEdge.outIdx, -1);
						break; //we've reached the end of the horizontal line
					}
					else if (e.dx < horzEdge.nextInLML.dx)
						//we really have got to the end of the intermediate horz edge so quit.
						//nb: More -ve slopes follow more +ve slopes ABOVE the horizontal.
						break;
				}

				if (e == eMaxPair)
				{
					//horzEdge is evidently a maxima horizontal and we've arrived at its end.
					if (direction == Direction.LEFT_TO_RIGHT)
						intersectEdges(horzEdge, e, new IntPoint(e.xcurr, horzEdge.ycurr), 0);
					else
						intersectEdges(e, horzEdge, new IntPoint(e.xcurr, horzEdge.ycurr), 0);
					if (eMaxPair.outIdx >= 0) throw new ClipperException("ProcessHorizontal error");
					return;
				}
				else if (e.dx == ClipperBase.horizontal && !isMinima(e) && !(e.xcurr > e.xtop))
				{
					if (direction == Direction.LEFT_TO_RIGHT)
						intersectEdges(horzEdge, e, new IntPoint(e.xcurr, horzEdge.ycurr),
						  (isTopHorz(horzEdge, e.xcurr)) ? Protects.LEFT : Protects.BOTH);
					else
						intersectEdges(e, horzEdge, new IntPoint(e.xcurr, horzEdge.ycurr),
						  (isTopHorz(horzEdge, e.xcurr)) ? Protects.RIGHT : Protects.BOTH);
				}
				else if (direction == Direction.LEFT_TO_RIGHT)
				{
					intersectEdges(horzEdge, e, new IntPoint(e.xcurr, horzEdge.ycurr),
					  (isTopHorz(horzEdge, e.xcurr)) ? Protects.LEFT : Protects.BOTH);
				}
				else
				{
					intersectEdges(e, horzEdge, new IntPoint(e.xcurr, horzEdge.ycurr),
					  (isTopHorz(horzEdge, e.xcurr)) ? Protects.RIGHT : Protects.BOTH);
				}
				swapPositionsInAEL(horzEdge, e);
			}
			else if ( (direction == Direction.LEFT_TO_RIGHT && 
				e.xcurr > horzRight && horzEdge.nextInSEL == null) || 
				(direction == Direction.RIGHT_TO_LEFT && 
				e.xcurr < horzLeft && horzEdge.nextInSEL == null) )
			{
				break;
			}
			e = eNext;
		} //end while ( e )

		if (horzEdge.nextInLML != null)
		{
			if (horzEdge.outIdx >= 0)
				addOutPt(horzEdge, new IntPoint(horzEdge.xtop, horzEdge.ytop));
			horzEdge = updateEdgeIntoAEL(horzEdge);
		}
		else
		{
			if (horzEdge.outIdx >= 0)
				intersectEdges(horzEdge, eMaxPair, 
					new IntPoint(horzEdge.xtop, horzEdge.ycurr), Protects.BOTH);
			deleteFromAEL(eMaxPair);
			deleteFromAEL(horzEdge);
		}
	}
	
	private function isTopHorz(horzEdge:TEdge, XPos:Float):Bool
	{
		var e:TEdge = m_SortedEdges;
		while (e != null)
		{
			if ((XPos >= Math.min(e.xcurr, e.xtop)) && (XPos <= Math.max(e.xcurr, e.xtop)))
				return false;
			e = e.nextInSEL;
		}
		return true;
	}
	
	inline private static function getNextInAEL(e:TEdge, direction:Int):TEdge
	{
		return direction == Direction.LEFT_TO_RIGHT ? e.nextInAEL: e.prevInAEL;
	}
	
	inline private static function isMinima(e:TEdge):Bool
	{
		return e != null && (e.prev.nextInLML != e) && (e.next.nextInLML != e);
	}
	
	inline private static function isMaxima(e:TEdge, Y:Float):Bool
	{
		return (e != null && e.ytop == Y && e.nextInLML == null);
	}
	
	inline private static function isIntermediate(e:TEdge, Y:Float):Bool
	{
		return (e.ytop == Y && e.nextInLML != null);
	}
	
	inline private static function getMaximaPair(e:TEdge):TEdge
	{
		if (!isMaxima(e.next, e.ytop) || (e.next.xtop != e.xtop))
		{
			return e.prev;
		}
		else
		{
			return e.next;
		}
	}
	
	private function processIntersections(botY:Int, topY:Int):Bool
	{
		if( m_ActiveEdges == null ) return true;
		try {
			buildIntersectList(botY, topY);
			if ( m_IntersectNodes == null) return true;
			if ( fixupIntersections() ) processIntersectList();
			else return false;
		}
		catch (e:Error)
		{
			m_SortedEdges = null;
			disposeIntersectNodes();
			throw new ClipperException("ProcessIntersections error");
		}
		return true;
	}
	
	private function buildIntersectList(botY:Int, topY:Int)
	{
		if ( m_ActiveEdges == null ) return;

		//prepare for sorting ...
		var e:TEdge = m_ActiveEdges;
		e.tmpX = topX( e, topY );
		m_SortedEdges = e;
		m_SortedEdges.prevInSEL = null;
		e = e.nextInAEL;
		while( e != null )
		{
			e.prevInSEL = e.prevInAEL;
			e.prevInSEL.nextInSEL = e;
			e.nextInSEL = null;
			e.tmpX = topX( e, topY );
			e = e.nextInAEL;
		}

		//bubblesort ...
		var isModified:Bool = true;
		while( isModified && m_SortedEdges != null )
		{
			isModified = false;
			e = m_SortedEdges;
			while( e.nextInSEL != null )
			{
				var eNext:TEdge = e.nextInSEL;
				var pt:IntPoint = new IntPoint();
				if(e.tmpX > eNext.tmpX && intersectPoint(e, eNext, pt))
				{
					if (pt.Y > botY)
					{
						pt.Y = botY;
						pt.X = topX(e, pt.Y);
					}
					addIntersectNode(e, eNext, pt);
					swapPositionsInSEL(e, eNext);
					isModified = true;
				}
				else
				{
					e = eNext;
				}
			}
			if( e.prevInSEL != null ) e.prevInSEL.nextInSEL = null;
			else break;
		}
		m_SortedEdges = null;
	}
	
	private function fixupIntersections():Bool
	{
		if ( m_IntersectNodes.next == null ) return true;

		copyAELToSEL();
		var int1:IntersectNode = m_IntersectNodes;
		var int2:IntersectNode = m_IntersectNodes.next;
		while (int2 != null)
		{
			var e1:TEdge = int1.edge1;
			var e2:TEdge;
			if (e1.prevInSEL == int1.edge2) e2 = e1.prevInSEL;
			else if (e1.nextInSEL == int1.edge2) e2 = e1.nextInSEL;
			else
			{
				//The current intersection is out of order, so try and swap it with
				//a subsequent intersection ...
				while (int2 != null)
				{
					if (int2.edge1.nextInSEL == int2.edge2 ||
						int2.edge1.prevInSEL == int2.edge2) break;
					else int2 = int2.next;
				}
				if (int2 == null) return false; //oops!!!

				//found an intersect node that can be swapped ...
				swapIntersectNodes(int1, int2);
				e1 = int1.edge1;
				e2 = int1.edge2;
			}
			swapPositionsInSEL(e1, e2);
			int1 = int1.next;
			int2 = int1.next;
		}

		m_SortedEdges = null;

		//finally, check the last intersection too ...
		return (int1.edge1.prevInSEL == int1.edge2 || int1.edge1.nextInSEL == int1.edge2);
	}
	
	private function processIntersectList()
	{
		while( m_IntersectNodes != null )
		{
			var iNode:IntersectNode = m_IntersectNodes.next;
			{
				intersectEdges( m_IntersectNodes.edge1 ,
							m_IntersectNodes.edge2 , m_IntersectNodes.pt, Protects.BOTH );
				swapPositionsInAEL( m_IntersectNodes.edge1 , m_IntersectNodes.edge2 );
			}
			m_IntersectNodes = null;
			m_IntersectNodes = iNode;
		}
	}
	
	inline private static function round(value:Float):Int
	{
		return value < 0 ? Std.int(value - 0.5) : Std.int(value + 0.5);
	}
	
	inline private static function topX(edge:TEdge, currentY:Int):Int
	{
		if (currentY == edge.ytop)
			return edge.xtop;
		else return edge.xbot + round(edge.dx *(currentY - edge.ybot));
	}
	
	private function addIntersectNode(e1:TEdge, e2:TEdge, pt:IntPoint)
	{
		var newNode:IntersectNode = new IntersectNode();
		newNode.edge1 = e1;
		newNode.edge2 = e2;
		newNode.pt = pt;
		newNode.next = null;
		if (m_IntersectNodes == null) m_IntersectNodes = newNode;
		else if (processParam1BeforeParam2(newNode, m_IntersectNodes))
		{
			newNode.next = m_IntersectNodes;
			m_IntersectNodes = newNode;
		}
		else
		{
			var iNode:IntersectNode = m_IntersectNodes;
			while (iNode.next != null && processParam1BeforeParam2(iNode.next, newNode))
				iNode = iNode.next;
			newNode.next = iNode.next;
			iNode.next = newNode;
		}
	}
	
	private function processParam1BeforeParam2(node1:IntersectNode, node2:IntersectNode):Bool
	{
		var result:Bool;
		if (node1.pt.Y == node2.pt.Y)
		{
			if (node1.edge1 == node2.edge1 || node1.edge2 == node2.edge1)
			{
				result = node2.pt.X > node1.pt.X;
				return node2.edge1.dx > 0 ? !result : result;
			}
			else if (node1.edge1 == node2.edge2 || node1.edge2 == node2.edge2)
			{
				result = node2.pt.X > node1.pt.X;
				return node2.edge2.dx > 0 ? !result : result;
			}
			else return node2.pt.X > node1.pt.X;
		}
		else return node1.pt.Y > node2.pt.Y;
	}
	
	private function swapIntersectNodes(int1:IntersectNode, int2:IntersectNode)
	{
		var e1:TEdge = int1.edge1;
		var e2:TEdge = int1.edge2;
		var p:IntPoint = int1.pt;
		int1.edge1 = int2.edge1;
		int1.edge2 = int2.edge2;
		int1.pt = int2.pt;
		int2.edge1 = e1;
		int2.edge2 = e2;
		int2.pt = p;
	}
	
	private function intersectPoint(edge1:TEdge, edge2:TEdge, ip:IntPoint):Bool
	{
		var b1:Float, b2:Float;
		if (slopesEqual(edge1, edge2, m_UseFullRange)) return false;
		else if (edge1.dx == 0)
		{
			ip.X = edge1.xbot;
			if (edge2.dx == ClipperBase.horizontal)
			{
				ip.Y = edge2.ybot;
			} 
			else
			{
				b2 = edge2.ybot - (edge2.xbot/edge2.dx);
				ip.Y = round(ip.X/edge2.dx + b2);
			}
		}
		else if (edge2.dx == 0)
		{
			ip.X = edge2.xbot;
			if (edge1.dx == ClipperBase.horizontal)
			{
				ip.Y = edge1.ybot;
			} 
			else
			{
				b1 = edge1.ybot - (edge1.xbot/edge1.dx);
				ip.Y = round(ip.X/edge1.dx + b1);
			}
		} 
		else
		{
			b1 = edge1.xbot - edge1.ybot * edge1.dx;
			b2 = edge2.xbot - edge2.ybot * edge2.dx;
			b2 = (b2-b1)/(edge1.dx - edge2.dx);
			ip.Y = round(b2);
			ip.X = round(edge1.dx * b2 + b1);
		}

		//can be *so close* to the top of one edge that the rounded Y equals one ytop ...
		return	(ip.Y == edge1.ytop && ip.Y >= edge2.ytop && edge1.tmpX > edge2.tmpX) ||
				(ip.Y == edge2.ytop && ip.Y >= edge1.ytop && edge1.tmpX > edge2.tmpX) ||
				(ip.Y > edge1.ytop && ip.Y > edge2.ytop);
	}
	
	private function disposeIntersectNodes()
	{
		while ( m_IntersectNodes != null )
		{
			var iNode:IntersectNode = m_IntersectNodes.next;
			m_IntersectNodes = null;
			m_IntersectNodes = iNode;
		}
	}
	
	private function processEdgesAtTopOfScanbeam(topY:Int)
	{
		var e:TEdge = m_ActiveEdges;
		while( e != null )
		{
			//1. process maxima, treating them as if they're 'bent' horizontal edges,
			//   but exclude maxima with horizontal edges. nb: e can't be a horizontal.
			if( isMaxima(e, topY) && getMaximaPair(e).dx != ClipperBase.horizontal )
			{
				//'e' might be removed from AEL, as may any following edges so ...
				var ePrior:TEdge = e.prevInAEL;
				doMaxima(e, topY);
				if( ePrior == null ) e = m_ActiveEdges;
				else e = ePrior.nextInAEL;
			}
			else
			{
				//2. promote horizontal edges, otherwise update xcurr and ycurr ...
				if( isIntermediate(e, topY) && e.nextInLML.dx == ClipperBase.horizontal )
				{
					if (e.outIdx >= 0)
					{
						addOutPt(e, new IntPoint(e.xtop, e.ytop));

						for ( i in 0...m_HorizJoins.length )
						{
							var hj:HorzJoinRec = m_HorizJoins[i];
							var pt1a:IntPoint = new IntPoint(hj.edge.xbot, hj.edge.ybot);
							var pt1b:IntPoint = new IntPoint(hj.edge.xtop, hj.edge.ytop);
							var pt2a:IntPoint = new IntPoint(e.nextInLML.xbot, e.nextInLML.ybot);
							var pt2b:IntPoint = new IntPoint(e.nextInLML.xtop, e.nextInLML.ytop);
							if (getOverlapSegment(
								new Segment(pt1a, pt1b), 
								new Segment(pt2a, pt2b), 
								new Segment(null, null)))
							{
								addJoin(hj.edge, e.nextInLML, hj.savedIdx, e.outIdx);
							}
						}

						addHorzJoin(e.nextInLML, e.outIdx);
					}
					e = updateEdgeIntoAEL(e);
					addEdgeToSEL(e);
				} 
				else
				{
					//this just simplifies horizontal processing ...
					e.xcurr = topX( e, topY );
					e.ycurr = topY;
				}
				e = e.nextInAEL;
			}
		}

		//3. Process horizontals at the top of the scanbeam ...
		processHorizontals();

		//4. Promote intermediate vertices ...
		e = m_ActiveEdges;
		while( e != null )
		{
			if( isIntermediate( e, topY ) )
			{
				if (e.outIdx >= 0) addOutPt(e, new IntPoint(e.xtop, e.ytop));
				e = updateEdgeIntoAEL(e);

				//if output polygons share an edge, they'll need joining later ...
				if (e.outIdx >= 0 && e.prevInAEL != null && e.prevInAEL.outIdx >= 0 &&
					e.prevInAEL.xcurr == e.xbot && e.prevInAEL.ycurr == e.ybot &&
					slopesEqual4(
						new IntPoint(e.xbot, e.ybot), 
						new IntPoint(e.xtop, e.ytop),
						new IntPoint(e.xbot, e.ybot),
						new IntPoint(e.prevInAEL.xtop, e.prevInAEL.ytop), 
						m_UseFullRange))
				{
					addOutPt(e.prevInAEL, new IntPoint(e.xbot, e.ybot));
					addJoin(e, e.prevInAEL, -1, -1);
				}
				else if (e.outIdx >= 0 && e.nextInAEL != null && e.nextInAEL.outIdx >= 0 &&
					e.nextInAEL.ycurr > e.nextInAEL.ytop &&
					e.nextInAEL.ycurr <= e.nextInAEL.ybot && 
					e.nextInAEL.xcurr == e.xbot && e.nextInAEL.ycurr == e.ybot &&
					slopesEqual4(
						new IntPoint(e.xbot, e.ybot), 
						new IntPoint(e.xtop, e.ytop),
						new IntPoint(e.xbot, e.ybot),
						new IntPoint(e.nextInAEL.xtop, e.nextInAEL.ytop), m_UseFullRange))
				{
					addOutPt(e.nextInAEL, new IntPoint(e.xbot, e.ybot));
					addJoin(e, e.nextInAEL, -1, -1);
				}
			}
			e = e.nextInAEL;
		}
	}
	
	private function doMaxima(e:TEdge, topY:Int)
	{
		var eMaxPair:TEdge = getMaximaPair(e);
		var X:Int = e.xtop;
		var eNext:TEdge = e.nextInAEL;
		while( eNext != eMaxPair )
		{
			if (eNext == null) throw new ClipperException("DoMaxima error");
			intersectEdges( e, eNext, new IntPoint(X, topY), Protects.BOTH );
			eNext = eNext.nextInAEL;
		}
		if( e.outIdx < 0 && eMaxPair.outIdx < 0 )
		{
			deleteFromAEL( e );
			deleteFromAEL( eMaxPair );
		}
		else if( e.outIdx >= 0 && eMaxPair.outIdx >= 0 )
		{
			intersectEdges(e, eMaxPair, new IntPoint(X, topY), Protects.NONE);
		}
		else throw new ClipperException("DoMaxima error");
	}
	
	inline public static function reversePolygons(polys:Polygons)
	{ 
		for (poly in polys.getPolygons()) poly.reverse();
	}
	
	public static function orientation(polygon:Polygon):Bool
	{
		var poly:Array<IntPoint> = polygon.getPoints();
		var highI:Int = poly.length -1;
		if (highI < 2) return false;
		var j:Int = 0, jplus:Int, jminus:Int;
		var i: Int = 0;
		while ( i <= highI )
		{
			if (poly[i].Y < poly[j].Y) continue;
			if ((poly[i].Y > poly[j].Y || poly[i].X < poly[j].X)) j = i;
			++i;
		}
		if (j == highI) jplus = 0;
		else jplus = j +1;
		if (j == 0) jminus = highI;
		else jminus = j -1;

		//get cross product of vectors of the edges adjacent to highest point ...
		var vec1:IntPoint = new IntPoint(poly[j].X - poly[jminus].X, poly[j].Y - poly[jminus].Y);
		var vec2:IntPoint = new IntPoint(poly[jplus].X - poly[j].X, poly[jplus].Y - poly[j].Y);
		if (ClipperBase.abs(vec1.X) > ClipperBase.loRange || ClipperBase.abs(vec1.Y) > ClipperBase.loRange ||
			ClipperBase.abs(vec2.X) > ClipperBase.loRange || ClipperBase.abs(vec2.Y) > ClipperBase.loRange)
		{
			if (ClipperBase.abs(vec1.X) > ClipperBase.hiRange || ClipperBase.abs(vec1.Y) > ClipperBase.hiRange ||
				ClipperBase.abs(vec2.X) > ClipperBase.hiRange || ClipperBase.abs(vec2.Y) > ClipperBase.hiRange)
			{
				throw new ClipperException("Coordinate exceeds range bounds.");
			}
			return IntPoint.cross(vec1, vec2) >= 0;
		}
		else
		{
			return IntPoint.cross(vec1, vec2) >=0;
		}
	}
	
	private function orientationOutRec(outRec:OutRec, useFull64BitRange:Bool):Bool
	{
		//first make sure bottomPt is correctly assigned ...
		var opBottom:OutPt = outRec.pts, op:OutPt = outRec.pts.next;
		while (op != outRec.pts) 
		{
			if (op.pt.Y >= opBottom.pt.Y) 
			{
				if (op.pt.Y > opBottom.pt.Y || op.pt.X < opBottom.pt.X) 
				opBottom = op;
			}
			op = op.next;
		}
		outRec.bottomPt = opBottom;
		opBottom.idx = outRec.idx;
		
		op = opBottom;
		//find vertices either side of bottomPt (skipping duplicate points) ....
		var opPrev:OutPt = op.prev;
		var opNext:OutPt = op.next;
		while (op != opPrev && ClipperBase.pointsEqual(op.pt, opPrev.pt)) 
		  opPrev = opPrev.prev;
		while (op != opNext && ClipperBase.pointsEqual(op.pt, opNext.pt))
		  opNext = opNext.next;

		var vec1:IntPoint = new IntPoint(op.pt.X - opPrev.pt.X, op.pt.Y - opPrev.pt.Y);
		var vec2:IntPoint = new IntPoint(opNext.pt.X - op.pt.X, opNext.pt.Y - op.pt.Y);

		if (useFull64BitRange)
		{
			//Int128 cross = Int128.Int128Mul(vec1.X, vec2.Y) - Int128.Int128Mul(vec2.X, vec1.Y);
			//return !cross.IsNegative();
			return IntPoint.cross(vec1, vec2) >= 0;
		}
		else
		{
			return IntPoint.cross(vec1, vec2) >= 0;
		}
	}
	
	private function pointCount(pts:OutPt):Int
	{
		if (pts == null) return 0;
		var result:Int = 0;
		var p:OutPt = pts;
		do
		{
			result++;
			p = p.next;
		}
		while (p != pts);
		return result;
	}
	
	private function buildResult(polyg:Polygons)
	{
		polyg.clear();
		for (outRec in m_PolyOuts)
		{
			if (outRec.pts == null) continue;
			var p:OutPt = outRec.pts;
			var cnt:Int = pointCount(p);
			if (cnt < 3) continue;
			var pg:Polygon = new Polygon();
			for (j in 0...cnt)
			{
				pg.addPoint(p.pt);
				p = p.next;
			}
			polyg.addPolygon(pg);
		}
	}
	
	private function fixupOutPolygon(outRec:OutRec)
	{
		//FixupOutPolygon() - removes duplicate points and simplifies consecutive
		//parallel edges by removing the middle vertex.
		var lastOK:OutPt  = null;
		outRec.pts = outRec.bottomPt;
		var pp:OutPt = outRec.bottomPt;
		while(true)
		{
			if (pp.prev == pp || pp.prev == pp.next)
			{
				disposeOutPts(pp);
				outRec.pts = null;
				outRec.bottomPt = null;
				return;
			}
			//test for duplicate points and for same slope (cross-product) ...
			if (ClipperBase.pointsEqual(pp.pt, pp.next.pt) ||
			  slopesEqual3(pp.prev.pt, pp.pt, pp.next.pt, m_UseFullRange))
			{
				lastOK = null;
				var tmp:OutPt = pp;
				if (pp == outRec.bottomPt)
					 outRec.bottomPt = null; //flags need for updating
				pp.prev.next = pp.next;
				pp.next.prev = pp.prev;
				pp = pp.prev;
				tmp = null;
			}
			else if (pp == lastOK)
			{
				break;
			}
			else
			{
				if (lastOK == null) lastOK = pp;
				pp = pp.next;
			}
		}
		if (outRec.bottomPt == null) 
		{
			outRec.bottomPt = getBottomPt(pp);
			outRec.bottomPt.idx = outRec.idx;
			outRec.pts = outRec.bottomPt;
		}
	}
	
	private function checkHoleLinkages1(outRec1:OutRec, outRec2:OutRec)
	{
	  //when a polygon is split into 2 polygons, make sure any holes the original
	  //polygon contained link to the correct polygon ...
	  for (i in 0...m_PolyOuts.length)
	  {
		if (m_PolyOuts[i].isHole && m_PolyOuts[i].bottomPt != null &&
			m_PolyOuts[i].firstLeft == outRec1 &&
			!pointInPolygon(m_PolyOuts[i].bottomPt.pt, 
			outRec1.pts, m_UseFullRange))
				m_PolyOuts[i].firstLeft = outRec2;
	  }
	}
	
	private function checkHoleLinkages2(outRec1:OutRec, outRec2:OutRec)
	{
	  //if a hole is owned by outRec2 then make it owned by outRec1 ...
	  for (i in 0...m_PolyOuts.length)
		if (m_PolyOuts[i].isHole && m_PolyOuts[i].bottomPt != null &&
		  m_PolyOuts[i].firstLeft == outRec2)
			m_PolyOuts[i].firstLeft = outRec1;
	}
	
	private function joinCommonEdges(fixHoleLinkages:Bool)
	{
		for (i in 0...m_Joins.length)
		{
			var j:JoinRec = m_Joins[i];
			var outRec1:OutRec = m_PolyOuts[j.poly1Idx];
			var pp1aRef:OutPtRef = new OutPtRef(outRec1.pts);
			var outRec2:OutRec = m_PolyOuts[j.poly2Idx];
			var pp2aRef:OutPtRef = new OutPtRef(outRec2.pts);
			var seg1:Segment = new Segment(j.pt2a, j.pt2b);
			var seg2:Segment = new Segment(j.pt1a, j.pt1b);
			if (!findSegment(pp1aRef, seg1)) continue;
			if (j.poly1Idx == j.poly2Idx)
			{
				//we're searching the same polygon for overlapping segments so
				//segment 2 mustn't be the same as segment 1 ...
				pp2aRef.outPt = pp1aRef.outPt.next;
				if (!findSegment(pp2aRef, seg2) || (pp2aRef.outPt == pp1aRef.outPt)) continue;
			}
			else if (!findSegment(pp2aRef, seg2)) continue;

			var seg:Segment = new Segment(null, null);
			if (!getOverlapSegment(seg1, seg2, seg)) continue;
			
			var pt1:IntPoint = seg.pt1;
			var pt2:IntPoint = seg.pt2;
			var pt3:IntPoint = seg2.pt1;
			var pt4:IntPoint = seg2.pt2;

			var pp1a:OutPt = pp1aRef.outPt;
			var pp2a:OutPt = pp2aRef.outPt;
			
			var p1:OutPt, p2:OutPt, p3:OutPt, p4:OutPt;
			var prev:OutPt = pp1a.prev;
			//get p1 & p2 polypts - the overlap start & endpoints on poly1

			if (ClipperBase.pointsEqual(pp1a.pt, pt1)) p1 = pp1a;
			else if (ClipperBase.pointsEqual(prev.pt, pt1)) p1 = prev;
			else p1 = insertPolyPtBetween(pp1a, prev, pt1);

			if (ClipperBase.pointsEqual(pp1a.pt, pt2)) p2 = pp1a;
			else if (ClipperBase.pointsEqual(prev.pt, pt2)) p2 = prev;
			else if ((p1 == pp1a) || (p1 == prev))
				p2 = insertPolyPtBetween(pp1a, prev, pt2);
			else if (pt3IsBetweenPt1AndPt2(pp1a.pt, p1.pt, pt2))
				p2 = insertPolyPtBetween(pp1a, p1, pt2); 
			else
				p2 = insertPolyPtBetween(p1, prev, pt2);

			//get p3 & p4 polypts - the overlap start & endpoints on poly2
			prev = pp2a.prev;
			if (ClipperBase.pointsEqual(pp2a.pt, pt1)) p3 = pp2a;
			else if (ClipperBase.pointsEqual(prev.pt, pt1)) p3 = prev;
			else p3 = insertPolyPtBetween(pp2a, prev, pt1);

			if (ClipperBase.pointsEqual(pp2a.pt, pt2)) p4 = pp2a;
			else if (ClipperBase.pointsEqual(prev.pt, pt2)) p4 = prev;
			else if ((p3 == pp2a) || (p3 == prev))
				p4 = insertPolyPtBetween(pp2a, prev, pt2);
			else if (pt3IsBetweenPt1AndPt2(pp2a.pt, p3.pt, pt2))
				p4 = insertPolyPtBetween(pp2a, p3, pt2);
			else
				p4 = insertPolyPtBetween(p3, prev, pt2);

			//p1.pt should equal p3.pt and p2.pt should equal p4.pt here, so ...
			//join p1 to p3 and p2 to p4 ...
			if (p1.next == p2 && p3.prev == p4)
			{
				p1.next = p3;
				p3.prev = p1;
				p2.prev = p4;
				p4.next = p2;
			}
			else if (p1.prev == p2 && p3.next == p4)
			{
				p1.prev = p3;
				p3.next = p1;
				p2.next = p4;
				p4.prev = p2;
			}
			else
				continue; //an orientation is probably wrong

			if (j.poly2Idx == j.poly1Idx)
			{
				//instead of joining two polygons, we've just created a new one by
				//splitting one polygon into two.
				outRec1.pts = getBottomPt(p1);
				outRec1.bottomPt = outRec1.pts;
				outRec1.bottomPt.idx = outRec1.idx;
				outRec2 = createOutRec();
				m_PolyOuts.push(outRec2);
				outRec2.idx = m_PolyOuts.length - 1;
				j.poly2Idx = outRec2.idx;
				outRec2.pts = getBottomPt(p2);
				outRec2.bottomPt = outRec2.pts;
				outRec2.bottomPt.idx = outRec2.idx;

				if (pointInPolygon(outRec2.pts.pt, outRec1.pts, m_UseFullRange))
				{
					//outRec1 is contained by outRec2 ...
					outRec2.isHole = !outRec1.isHole;
					outRec2.firstLeft = outRec1;
					if (outRec2.isHole == ClipperBase.xor(m_ReverseOutput, orientationOutRec(outRec2, m_UseFullRange)))
						reversePolyPtLinks(outRec2.pts);
				}
				else if (pointInPolygon(outRec1.pts.pt, outRec2.pts, m_UseFullRange))
				{
					//outRec2 is contained by outRec1 ...
					outRec2.isHole = outRec1.isHole;
					outRec1.isHole = !outRec2.isHole;
					outRec2.firstLeft = outRec1.firstLeft;
					outRec1.firstLeft = outRec2;
					if (outRec1.isHole == ClipperBase.xor(m_ReverseOutput, orientationOutRec(outRec1, m_UseFullRange)))
						reversePolyPtLinks(outRec1.pts);
					//make sure any contained holes now link to the correct polygon ...
					if (fixHoleLinkages) checkHoleLinkages1(outRec1, outRec2);
				}
				else
				{
					outRec2.isHole = outRec1.isHole;
					outRec2.firstLeft = outRec1.firstLeft;
					//make sure any contained holes now link to the correct polygon ...
					if (fixHoleLinkages) checkHoleLinkages1(outRec1, outRec2);
				}

				//now fixup any subsequent m_Joins that match this polygon
				for (k in (i+1)...m_Joins.length)
				{
					var j2:JoinRec = m_Joins[k];
					if (j2.poly1Idx == j.poly1Idx && pointIsVertex(j2.pt1a, p2))
						j2.poly1Idx = j.poly2Idx;
					if (j2.poly2Idx == j.poly1Idx && pointIsVertex(j2.pt2a, p2))
						j2.poly2Idx = j.poly2Idx;
				}
				
				//now cleanup redundant edges too ...
				fixupOutPolygon(outRec1);
				fixupOutPolygon(outRec2);
				if (orientationOutRec(outRec1, m_UseFullRange) != (areaOutRec(outRec1, m_UseFullRange) > 0))
					disposeBottomPt(outRec1);
				if (orientationOutRec(outRec2, m_UseFullRange) != (areaOutRec(outRec2, m_UseFullRange) > 0)) 
					disposeBottomPt(outRec2);
			}
			else
			{
				//joined 2 polygons together ...

				//make sure any holes contained by outRec2 now link to outRec1 ...
				if (fixHoleLinkages) checkHoleLinkages2(outRec1, outRec2);

				//now cleanup redundant edges too ...
				fixupOutPolygon(outRec1);

				if (outRec1.pts != null)
				{
					outRec1.isHole = !orientationOutRec(outRec1, m_UseFullRange);
					if (outRec1.isHole &&  outRec1.firstLeft == null) 
					  outRec1.firstLeft = outRec2.firstLeft;
				}

				//delete the obsolete pointer ...
				var OKIdx:Int = outRec1.idx;
				var ObsoleteIdx:Int = outRec2.idx;
				outRec2.pts = null;
				outRec2.bottomPt = null;
				outRec2.appendLink = outRec1;

				//now fixup any subsequent joins that match this polygon
				for (k in (i + 1)...m_Joins.length)
				{
					var j2 = m_Joins[k];
					if (j2.poly1Idx == ObsoleteIdx) j2.poly1Idx = OKIdx;
					if (j2.poly2Idx == ObsoleteIdx) j2.poly2Idx = OKIdx;
				}
			}
		}
	}
	
	private function areaOutRec(outRec:OutRec, useFull64BitRange:Bool):Float
	{
		var op:OutPt = outRec.pts;
		var a:Float = 0;
		do {
		  a += (op.prev.pt.X * op.pt.Y) - (op.pt.X * op.prev.pt.Y);
		  op = op.next;
		} while (op != outRec.pts);
		return a*.5;
	}
	
}

class Protects 
{ 
	inline public static var NONE: Int = 0;
	inline public static var LEFT: Int = 1;
	inline public static var RIGHT: Int = 2;
	inline public static var BOTH: Int = 3;
}

class Direction 
{ 
	inline public static var RIGHT_TO_LEFT: Int = 0;
	inline public static var LEFT_TO_RIGHT: Int = 1;
}

class Scanbeam
{
	public var Y: Int;
	public var next: Scanbeam;
	
	public function new(){}
}

class JoinRec
{
	public var pt1a: IntPoint;
	public var pt1b: IntPoint;
	public var poly1Idx: Int;
	public var pt2a: IntPoint;
	public var pt2b: IntPoint;
	public var poly2Idx: Int;
	
	public function new(){}
}
