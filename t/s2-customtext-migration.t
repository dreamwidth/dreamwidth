# t/s2-customtext-migration.t
#
# Custom text is copied into a journal's userprops only from the journal's own
# style, never from a style the journal is being viewed in.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use LJ::Test qw(temp_user temp_feed with_fake_memcache);
use LJ::S2;

DW::Request::Standard->new( HTTP::Request->new( GET => 'http://localhost/' ) );

my $owner        = temp_user();
my $viewer       = temp_user();
my $feed         = temp_feed();
my $owner_style  = LJ::S2::create_style( $owner, 'owner style' );
my $viewer_style = LJ::S2::create_style( $viewer, 'viewer style' );
ok( $owner_style && $viewer_style, 'created styles' );

$owner->set_prop( stylesys => 2 );
$owner->set_prop( s2_style => $owner_style );
$owner->{_journalbase} = $owner->journal_base;
$feed->{_journalbase}  = $feed->journal_base;

# The S2 context of the style the page is rendered with.
sub context {
    my ($who) = @_;
    my @ctx;
    $ctx[S2::PROPS] = {
        text_module_customtext         => "$who heading",
        text_module_customtext_url     => "https://example.com/$who",
        text_module_customtext_content => "$who custom text",
    };
    $ctx[S2::LAYERLIST] = [];
    return \@ctx;
}

# make_journal stores a non-numeric style (such as the site's feed style) as 0
sub render {
    my ( $styleid, $ctx, %opts ) = @_;
    my $journal = delete $opts{journal} || $owner;
    $journal->{_s2styleid} = $styleid;
    return LJ::S2::Page( $journal, { getargs => {}, ctx => $ctx, %opts } );
}

sub stored {
    my $u = LJ::load_userid( ( $_[0] || $owner )->id );
    return join '|',
        map { $u->prop($_) // '' } qw(customtext_title customtext_url customtext_content);
}

with_fake_memcache {

    # ?style=mine: the viewer's own style
    my $page = render( $viewer_style, context('viewer'), style_u => $viewer );
    is( stored(), '||', "style=mine does not save the viewer's custom text to the journal" );
    unlike( $page->{customtext_content},
        qr/viewer/, "style=mine does not show the viewer's custom text" );

    # ?s2id= for another user's public style
    render( $viewer_style, context('viewer') );
    is( stored(), '||', "another user's style does not save its custom text to the journal" );

    # the journal's own style still migrates its custom text
    $page = render( $owner_style, context('owner') );
    is(
        stored(),
        'owner heading|https://example.com/owner|owner custom text',
        "the journal's own style saves its custom text"
    );
    is( $page->{customtext_content}, 'owner custom text', "own style shows the journal's text" );

    # once migrated, other styles show the journal's own custom text
    $page = render( $viewer_style, context('viewer'), style_u => $viewer );
    is( $page->{customtext_title}, 'owner heading', "style=mine shows the journal's heading" );
    is(
        $page->{customtext_content},
        'owner custom text',
        "style=mine shows the journal's custom text"
    );
    is(
        stored(),
        'owner heading|https://example.com/owner|owner custom text',
        'the saved custom text is unchanged'
    );

    # feeds use the site's feed style, which supplies their custom text
    render( $viewer_style, context('viewer'), journal => $feed, style_u => $viewer );
    is( stored($feed), '||', "style=mine does not save the viewer's custom text to a feed" );
    $page = render( 0, context('feed'), journal => $feed );
    is(
        stored($feed),
        'feed heading|https://example.com/feed|feed custom text',
        "the site's feed style saves its custom text to the feed"
    );
    is( $page->{customtext_content}, 'feed custom text', "the feed shows the feed style's text" );
};

LJ::S2::delete_user_style( $owner,  $owner_style );
LJ::S2::delete_user_style( $viewer, $viewer_style );

done_testing;
