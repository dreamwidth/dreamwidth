# t/plack-layeredit.t
#
# Layer editor return navigation must follow the authorized layer owner.
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
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $admin    = temp_user();
my $comm     = temp_comm();
my $stranger = temp_user();
LJ::set_rel( $comm, $admin, 'A' );
$_->update_self( { caps => 8 } ) for ( $admin, $comm );

my @layers;
END { LJ::S2::delete_layer($_) for @layers; }

sub layer_for {
    my ($u) = @_;

    # Rendering the editor needs stored source and metadata, not a compiled core.
    my $id = LJ::S2::create_layer( $u, 1, 'layout' ) or die 'create layer';
    push @layers, $id;
    my $source = 'layerinfo "type" = "layout";';
    LJ::S2::set_layer_source( $id, \$source );
    my $dbh = LJ::get_db_writer();
    $dbh->do( 'INSERT INTO s2info (s2lid, infokey, value) VALUES (?, ?, ?)',
        undef, $id, 'type', 'layout' );
    return $id;
}

my $personal  = layer_for($admin);
my $community = layer_for($comm);
my $base      = 'http://localhost/customize/advanced';

# Test databases need not contain translations. Keep the actual template's link
# visible while passing other messages through the normal translator.
my $get_text = \&LJ::Lang::get_text;
{
    no warnings 'redefine';
    local *LJ::Lang::get_text = sub {
        my ( $lang, $key, $date, $args ) = @_;
        return $args->{link} if $key eq 'Actionlink';
        return 'Back to layers list'
            if $key eq '/customize/advanced/layeredit.tt.advancedlayerlink';
        return $get_text->(@_);
    };

    test_psgi $app, sub {
        my $cb = shift;
        for my $case (
            [ 'personal layer',                  $personal,  '', '' ],
            [ 'community layer opened directly', $community, '', '?authas=' . $comm->user ],
            [
                'community layer with authas',
                $community,
                '&authas=' . $comm->user,
                '?authas=' . $comm->user
            ],
            [
                'owner takes precedence over unrelated authas',
                $community,
                '&authas=' . $stranger->user,
                '?authas=' . $comm->user
            ],
            [ 'personal layer with unrelated authas', $personal, '&authas=' . $comm->user, '' ],
            )
        {
            my ( $label, $id, $query, $suffix ) = @$case;
            subtest $label => sub {
                my $res = $cb->( GET "$base/layeredit?id=$id&as=" . $admin->user . $query );
                is( $res->code, 200, 'editor renders' );
                like( $res->content, qr/Loaded layer $id\./, 'requested layer is loaded' );
                my ($href) = $res->content =~ /<a href='([^']+)'>Back to layers list<\/a>/;
                ok( defined $href, 'return link is present' );
                is(
                    $href,
                    "$LJ::SITEROOT/customize/advanced/layers$suffix",
                    'return link selects the layer owner'
                );
            };
        }

        my $res = $cb->( GET "$base/layeredit?id=$community&as=" . $stranger->user );
        unlike(
            $res->content,
            qr/Loaded layer $community\./,
            'non-administrator cannot open the layer'
        );
        unlike( $res->content, qr/Back to layers list/,
            'denied request has no editor return link' );
    };

}

done_testing;
