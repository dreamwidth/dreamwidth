// ---------------------------------------------------------------------------
//   S2 DHTML editor
//
//   s2edit.js - main editor declarations
// ---------------------------------------------------------------------------

var s2index;

var s2dirty;
var s2lineCount;

function s2init()
{
	s2dirty = 1;
	s2lineCount = 0;

	s2initIndex();
	s2initParser();
	s2initSense();
	s2buildReference();
	s2initDrag();

	// Disable selection in the document (IE only - prevents wacky dragging bugs)
	document.onselectstart = function () { return false; };
}

function s2initIndex()
{
	s2index = new Object();
}
