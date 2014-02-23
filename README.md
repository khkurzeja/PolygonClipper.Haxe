PolygonClipper.Haxe
===================

A Haxe port of the AS3 port of the C# version of the Clipper library.

The AS3 version was ported by Chris Denham, and can be found at:
https://github.com/ChrisDenham/PolygonClipper.AS3

The original was made by Angus Johnson, and can be found at:
http://www.angusj.com/delphi/clipper.php

This port is almost exactly the same as the AS3 port. Though I did add a few optimizations, mainly inlining many functions. I also created a new point class to mimic AS3's, so that this port will not have to be Flash only. I created a new example showing the unioning of several polygons togther since it is what I needed this library for.

As with the AS3 port, I did not test the code extensively, but I did run a few tests using union, XOR, difference, and intersection, and everything seems to work fine.
