// ---------------------------------------------------------------------------
//   S2 DHTML editor
//
//   s2parser.js - incremental S2 parser
// ---------------------------------------------------------------------------

var s2parseOffset;
var s2parseIncrement;

var s2parserState;
var s2parserToken;
var s2parserLineNo;

// Parsing is implemented as a simple finite state machine. s2parse() should
// not assume the beginning of the input file - it could be called anywhere,
// even within a quoted string! s2parserState should be used to determine
// where we are.
function s2parse(code, offset)
{
	var ret = new Array();
	var codeLen = code.length;
	
	for (var i = 0; i < codeLen; i++) {
		var c = code.charAt(i);
		var cc = c.charCodeAt(0);
		
		if (c == "\n")
			s2parserLineNo++;
		
		switch (s2parserState) {
			case 0:		// main
				if ((cc >= 0x41 && cc <= 0x5a) ||
					(cc >= 0x61 && cc <= 0x7a)) {	// :alpha:
					s2parserToken += c;
					break;
				}
				if (cc >= 0x30 && cc <= 0x39 &&
					s2parserToken.length > 0) {		// :digit:
					s2parserToken += c;
					break;
				}
				
				// End of a token
				if (s2parserToken.length > 0) {
					if (s2parserToken.toLowerCase() == 'function') {
						s2parserToken = '';
						s2parserState = 1;		// -> function name
						break;
					}
							
					if (s2parserToken.toLowerCase() == 'propgroup') {
						s2parserToken = '';
						s2parserState = 2;		// -> propgroup name
						break;
					}
				
					s2parserToken = "";
				}
				break;
				
			case 1:		// function name
				if ((cc >= 0x41 && cc <= 0x5a) ||
					(cc >= 0x61 && cc <= 0x7a) ||
					(cc >= 0x30 && cc <= 0x39) ||
					cc == 0x3a || cc == 0x5f) {
					s2parserToken += c;
					break;
				}
				if (s2parserToken.length == 0)
					break;	// extra whitespace, we'll assume
				
				// Found the function
				var sym = new Object();
				sym.loc = offset + i;
				sym.line = s2parserLineNo;
				sym.type = (/:/.test(s2parserToken) ? 1 : 0);
				sym.name = s2parserToken + '()';
				ret.push(sym);
				
				s2parserToken = '';
				s2parserState = 0;
				break;
				
			case 2:		// propgroup name
				if ((cc >= 0x41 && cc <= 0x5a) ||
					(cc >= 0x61 && cc <= 0x7a) ||
					(cc >= 0x30 && cc <= 0x39) ||
					cc == 0x5f) {
					s2parserToken += c;
					break;
				}
				if (s2parserToken.length == 0)
					break;
				
				// Found the name of the propgroup
				var sym = new Object();
				sym.loc = offset + i;
				sym.line = s2parserLineNo;
				sym.type = 2;
				sym.name = s2parserToken;
				ret.push(sym);
				
				s2parserToken = '';
				s2parserState = 0;
				break;
		}
	}

	return ret;
}

function s2parseNext()
{
	if (s2parseOffset == 0 && s2dirty == 0)
		return;

	var code = s2getCode();
	
	var chunk;
	if (s2parseOffset + s2parseIncrement < code.length)
		chunk = code.substring(s2parseOffset, s2parseOffset + s2parseIncrement);
	else
		chunk = code.substring(s2parseOffset);
	s2index[s2parseOffset / s2parseIncrement] = s2parse(chunk, s2parseOffset);
	
	s2parseOffset += s2parseIncrement;
	if (s2parseOffset >= code.length) {
		s2lineCount = s2parserLineNo;
		s2dirty = 0;
		s2index[s2parseOffset / s2parseIncrement] = null;
		s2resetParser();
	}
		
	s2updateNav();
}

function s2resetParser()
{
	s2parseOffset = 0;
	s2parseIncrement = 5000;	// 5000 chars each 2.5 sec
	
	s2parserState = 0;
	s2parserToken = "";
	s2parserLineNo = 1;
}

function s2initParser()
{
	s2resetParser();
	window.setInterval("s2parseNext()", 2500);
	s2parseNext();
}
