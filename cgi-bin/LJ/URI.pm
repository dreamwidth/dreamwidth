# This is a module for handling URIs
use strict;

package LJ::URI;
use Apache2::Const qw/ :common REDIRECT HTTP_NOT_MODIFIED
                       HTTP_MOVED_PERMANENTLY HTTP_MOVED_TEMPORARILY
                       M_TRACE M_OPTIONS /;

# Takes an Apache $r and a path to BML filename relative to htdocs
sub bml_handler {
    my ($class, $r, $filename) = @_;

    $r->handler("perl-script");
    $r->notes->{bml_filename} = "$LJ::HOME/htdocs/$filename";
    $r->push_handlers(PerlHandler => \&Apache::BML::handler);
    return OK;
}

# Handle a URI. Returns response if success, undef if not handled
# Takes URI and Apache $r
sub handle {
    my ($class, $uri, $r) = @_;

    return undef unless $uri;

    # handle "RPC" URIs
    if (my ($rpc) = $uri =~ m!^.*/__rpc_(\w+)$!) {
        my $bml_handler_path = $LJ::AJAX_URI_MAP{$rpc};

        return LJ::URI->bml_handler($r, $bml_handler_path) if $bml_handler_path;
    }

    # handle normal URI mappings
    if (my $bml_file = $LJ::URI_MAP{$uri}) {
        return LJ::URI->bml_handler($r, $bml_file);
    }

    # handle URI redirects
    if (my $url = $LJ::URI_REDIRECT{$uri}) {
        return Apache::LiveJournal::redir($r, $url, HTTP_MOVED_TEMPORARILY);
    }

    return undef;
}

1;
