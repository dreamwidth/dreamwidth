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

# This is a module for handling URIs
use strict;

package LJ::URI;
use Apache2::Const qw/ :common REDIRECT HTTP_NOT_MODIFIED
    HTTP_MOVED_PERMANENTLY HTTP_MOVED_TEMPORARILY
    M_TRACE M_OPTIONS /;

# Takes an Apache $apache_r and a path to BML filename relative to htdocs
sub bml_handler {
    my ( $class, $apache_r, $filename ) = @_;
    my $dw_r = DW::Request->get;

    $apache_r->handler("perl-script");
    $dw_r->cache(bml_filename => "$LJ::HTDOCS/$filename");
    $apache_r->push_handlers( PerlHandler => \&Apache::BML::handler );
    return OK;
}

# Handle a URI. Returns response if success, undef if not handled
# Takes URI and Apache $apache_r
sub handle {
    my ( $class, $uri, $apache_r ) = @_;

    return undef unless $uri;

    # handle "RPC" URIs
    if ( my ($rpc) = $uri =~ m!^.*/__rpc_(\w+)$! ) {
        my $bml_handler_path = $LJ::AJAX_URI_MAP{$rpc};

        return LJ::URI->bml_handler( $apache_r, $bml_handler_path )
            if $bml_handler_path;
    }

    # handle normal URI mappings -- removed, unused
    # handle URI redirects -- removed, also unused

    return undef;
}

1;
