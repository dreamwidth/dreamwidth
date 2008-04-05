// ---------------------------------------------------------------------------
//   S2 DHTML editor
//
//   s2sense.js - code sense for S2
// ---------------------------------------------------------------------------

var s2classCompCache;
var s2methodCompCache;

var s2completions = new Array();
var s2compText = "";
var s2compColor = '';

function s2startClassMethodCompletion(className)
{
	var cls = s2classCompCache[className];
	if (cls == null)
		return;
	
	s2compText = className + "::";
	for (var i = 0; i < cls.methods.length; i++) {
		var nm = cls.methods[i].name;
		s2completions.push(className + "::" + nm.substring(0,
			nm.indexOf('(')));
	}
	
	s2compColor = '#ceb1ff';
	s2completionUpdated();
}

function s2startMethodCompletion()
{
	s2compText = '';
	s2completions = s2methodCompCache;
	
	s2compColor = '#ffb0b0';
	s2completionUpdated();
}

function s2startMemberCompletion()
{
	s2compText = '';
	s2completions = s2memberCompCache;
	
	s2compColor = '#b1c7ff';
	s2completionUpdated();
}

function s2completionUpdated(color)
{
	s2printStatusColor(s2completions.length + ' completions: ' +
		s2completions.slice(0, Math.min(5, s2completions.length)).join(", ") +
		(s2completions.length > 5 ? ", ..." : ""), s2compColor);
}

function s2acceptCompletion()
{
	var area = s2getCodeArea();

	if (!(s2completions.length))
		return false;

	nxinsertText(area, s2completions[0].substring(s2compText.length));
	s2printStatus('Autocompleted: ' + s2completions[0]);
	s2completions = new Array();
	
	return true;
}

function s2abandonCompletion()
{
	s2completions = new Array();
	s2printStatus('');
}

// Entry point for code sense - should be called each time a change occurs
function s2sense(ch)
{
	var area = s2getCodeArea();
	
	var oldScrollTop = area.scrollTop;
	
	if (ch == 0) {
		s2abandonCompletion();
		return;
	}
	
	if (s2completions.length) {
		if ((ch >= 0x30 && ch <= 0x39) ||	// 0-9
			(ch >= 0x41 && ch <= 0x5a) ||	// A-Z
			(ch >= 0x61 && ch <= 0x7a) ||	// a-z
			ch == 0x5f) {					// _
			s2compText += String.fromCharCode(ch);
			
			var s2newCompletions = new Array();
			for (var i = 0; i < s2completions.length; i++)
				if (s2completions[i].substring(0, s2compText.length) == s2compText)
					s2newCompletions.push(s2completions[i]);
			s2completions = s2newCompletions;
			
			if (s2completions.length == 0)
				s2abandonCompletion();
			else
				s2completionUpdated();
		} else {
			s2acceptCompletion();
		}
	} else
		switch (ch) {
			case 58:	// :
				var m = nxgetLastChars(area, 64).match(/([A-Za-z0-9_]+):$/);
				if (m)
					s2startClassMethodCompletion(m[1]);
				break;
				
			case 0x3e:	// >
				var m = nxgetLastChars(area, 64).match(/\$[^-]+-$/);
				if (m)
					s2startMethodCompletion();
				break;
				
			case 0x2e:	// .
				var m = nxgetLastChars(area, 64).match(/\$[^.]+$/);
				if (m)
					s2startMemberCompletion();
				break;
		}
}

// Create the completion caches - initialization routine
function s2buildCompletionCaches()
{
	// Decreases class lookup from O(n) to O(1)
	s2classCompCache = new Object();
	for (var i = 0; i < s2classlib.length; i++)
		s2classCompCache[s2classlib[i].name] = s2classlib[i];
	
	var s2methods = new Object();
	s2methodCompCache = new Array();
	for (var i = 0; i < s2classlib.length; i++)
		for (var j = 0; j < s2classlib[i].methods.length; j++) {
			var nm = s2classlib[i].methods[j].name;
			nm = nm.substring(0, nm.indexOf('('));
			s2methods[nm] = nm;
		}
	for (var nm in s2methods)
		s2methodCompCache.push(nm);
	s2methodCompCache.sort();
	
	// members
	var s2members = new Object();
	s2memberCompCache = new Array();
	for (var i = 0; i < s2classlib.length; i++)
		for (var j = 0; j < s2classlib[i].members.length; j++) {
			var nm = s2classlib[i].members[j].name;
			s2members[nm] = nm;
		}
	for (var nm in s2members)
		s2memberCompCache.push(nm);
	s2memberCompCache.sort();
}

function s2initSense()
{
	s2buildCompletionCaches();
}
