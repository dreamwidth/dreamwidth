# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::JSUtil;
use strict;

#<LJFUNC>
# name: LJ::JSUtil::autocomplete
# class: web
# des: given the name of a form filed and a list of strings, return the
#      JavaScript needed to turn on autocomplete for the given field.
# returns: HTML/JS to insert in an HTML page
# </LJFUNC>
sub autocomplete {
    my %opts = @_;

    my $fieldid = $opts{field};
    my @list    = @{ $opts{list} };

    # create formatted string to use as a javascript list
    @list = sort { lc $a cmp lc $b } @list;
    @list = map  { $_ = "\"$_\"" } @list;
    my $formatted_list = join( ",", @list );

    return qq{
    <script type="text/javascript" language="JavaScript">
        function AutoCompleteFriends (ele) \{
            var keywords = new InputCompleteData([$formatted_list], "ignorecase");
            var ic = new InputComplete(ele, keywords);
        \}
        if (\$('$fieldid')) AutoCompleteFriends(\$('$fieldid'));
    </script>
    };
}

1;
