#!/usr/bin/perl
#
# Validate UTF-8 in Perl, using C.
#
#    Brad Fitzpatrick, <bradfitz@livejournal.com>
#   
# UTF-8 character validation code copyright by Unicode, Inc.
# See below.
#

use Inline C;
use strict;

sub check_utf8
{
    my $t = shift;
    return 0 if $t =~ /\0/;  # no embedded nulls
    return isLegalUTF8String($t);
}


my @tests = (
	     # these are okay:
	     "1) a" => 1,
	     "2) Some string!\n" => 1,
	     "3) Stra\xc3\x9fe" => 1,   # StraBe  (B = German 'ss')

	     # these should fail:
	     "4) Stra\xc3" => 0,      # Strasse, with B cut in middle
	     "5) \0" => 0,            # don't allow nulls in middle
	     "6) \xFF", => 0,         # out of range

	     # these overlongs should fail:  (all for ASCII "/")
	     "7) \xc0\xaf" => 0,
	     "8) \xe0\x80\xaf" => 0,
	     "9) \xf0\x80\x80\xaf" => 0,
	     "10) \xf8\x80\x80\x80\xaf" => 0,

	     );

while (@tests) {
    my ($t, $ev) = splice(@tests, 0, 2);
    my $av = check_utf8($t);
    unless ($av == $ev) { die "FAIL on $t\n"; }
}

print "All tests pass.\n";

__END__
__C__

/*
 * Copyright 2001 Unicode, Inc.
 * 
 * Disclaimer
 * 
 * This source code is provided as is by Unicode, Inc. No claims are
 * made as to fitness for any particular purpose. No warranties of any
 * kind are expressed or implied. The recipient agrees to determine
 * applicability of information provided. If this file has been
 * purchased on magnetic or optical media from Unicode, Inc., the
 * sole remedy for any claim will be exchange of defective media
 * within 90 days of receipt.
 * 
 * Limitations on Rights to Redistribute This Code
 * 
 * Unicode, Inc. hereby grants the right to freely use the information
 * supplied in this file in the creation of products supporting the
 * Unicode Standard, and to make copies of this file in any form
 * for internal or external distribution as long as this notice
 * remains attached.
 */


typedef unsigned char UTF8;	
typedef unsigned char Boolean;

#define false		0
#define true		1

static const char trailingBytesForUTF8[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
};

static Boolean isLegalUTF8(UTF8 *source, int length) {
	UTF8 a;
	UTF8 *srcptr = source+length;
	switch (length) {
	default: return false;
		/* Everything else falls through when "true"... */
	case 4: if ((a = (*--srcptr)) < 0x80 || a > 0xBF) return false;
	case 3: if ((a = (*--srcptr)) < 0x80 || a > 0xBF) return false;
	case 2: if ((a = (*--srcptr)) > 0xBF) return false;
		switch (*source) {
		    /* no fall-through in this inner switch */
		    case 0xE0: if (a < 0xA0) return false; break;
		    case 0xF0: if (a < 0x90) return false; break;
		    case 0xF4: if (a > 0x8F) return false; break;
		    default:  if (a < 0x80) return false;
		}
    	case 1: if (*source >= 0x80 && *source < 0xC2) return false;
		if (*source > 0xF4) return false;
	}
	return true;
}

/********************* End code from Unicode, Inc. ***************/

/*
 * Author: Brad Fitzpatrick
 *
 */

Boolean isLegalUTF8String(char *str)
{
    UTF8 *cp = str;
    int i;
    while (*cp) {
	/* how many bytes follow this character? */
	int length = trailingBytesForUTF8[*cp]+1;

	/* check for early termination of string: */
	for (i=1; i<length; i++) {
	    if (cp[i] == 0) return false;
	}

	/* is this a valid group of characters? */
	if (!isLegalUTF8(cp, length))
	    return false;

	cp += length;
    }
    return true;
}

