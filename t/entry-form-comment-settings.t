# t/entry-form-comment-settings.t
#
# Test that editing a community entry preserves who disabled its comments.
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
use HTML::TokeParser;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Entry;
use LJ::Session;
use LJ::Test qw(temp_user temp_comm);

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $poster = temp_user();
$poster->update_self( { status => 'A' } );
my $comm    = temp_comm();
my $session = LJ::Session->create( $poster, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryCommentSettings';

my @cases = (
    {
        name     => 'unchanged administrator setting',
        initial  => [ 0, 1, 0 ],
        expected => [ 0, 1, 0 ],
    },
    {
        name     => 'unchanged administrator setting with email disabled',
        initial  => [ 0, 1, 1 ],
        expected => [ 0, 1, 1 ],
    },
    {
        name     => 'poster disables comments',
        initial  => [ 0, 0, 0 ],
        selected => 'nocomments',
        expected => [ 1, 0, 0 ],
    },
    {
        name     => 'unchanged poster setting',
        initial  => [ 1, 0, 0 ],
        expected => [ 1, 0, 0 ],
    },
    {
        name     => 'poster and administrator both disabled comments',
        initial  => [ 1, 1, 0 ],
        expected => [ 1, 1, 0 ],
    },
    {
        name     => 'poster explicitly enables comments',
        initial  => [ 0, 1, 1 ],
        selected => '',
        expected => [ 0, 0, 0 ],
    },
    {
        name     => 'poster explicitly enables comments without email',
        initial  => [ 0, 1, 0 ],
        selected => 'noemail',
        expected => [ 0, 0, 1 ],
    },
);

my @props = qw(opt_nocomments opt_nocomments_maintainer opt_noemail);

sub selected_comment_settings {
    my ($html) = @_;
    my $parser = HTML::TokeParser->new( \$html );
    while ( my $select = $parser->get_tag('select') ) {
        next unless ( $select->[1]{name} // '' ) eq 'comment_settings';
        my $first;
        while ( my $option = $parser->get_tag( 'option', '/select' ) ) {
            last if $option->[0] eq '/select';
            my $attrs = $option->[1];
            return $attrs->{value} if exists $attrs->{selected};
            $first //= $attrs->{value};
        }
        return $first;
    }
    return undef;
}

test_psgi $app, sub {
    my ($send) = @_;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    foreach my $layout (qw(advanced simple)) {
        foreach my $case (@cases) {
            subtest "$layout: $case->{name}" => sub {
                my $entry = $poster->t_post_fake_entry(
                    usejournal      => $comm->user,
                    usejournal_okay => 1,
                );
                my %initial;
                @initial{@props} = @{ $case->{initial} };
                LJ::set_logprop( $comm, $entry->jitemid, \%initial );
                LJ::Entry::reset_singletons();

                my $url = 'http://localhost/entry/' . $comm->user . '/' . $entry->ditemid . '/edit';
                $url .= '?mode=simple' if $layout eq 'simple';
                my $html        = $request->( GET $url )->content;
                my ($form_auth) = $html =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
                my $selected    = selected_comment_settings($html);
                ok( $form_auth && defined $selected, 'native edit form renders' ) or return;

                my $subject  = 'Edited through the native form';
                my $response = $request->(
                    POST $url,
                    [
                        'action:post'    => 1,
                        lj_form_auth     => $form_auth,
                        subject          => $subject,
                        event            => 'Entry body',
                        security         => 'public',
                        comment_settings => $case->{selected} // $selected,
                    ]
                );
                is( $response->code, 200, 'native edit returns a success page' );

                LJ::Entry::reset_singletons();
                my $saved = LJ::Entry->new( $comm, ditemid => $entry->ditemid );
                is( $saved->subject_raw, $subject, 'the edit was saved' );
                is_deeply( [ map { $saved->prop($_) ? 1 : 0 } @props ],
                    $case->{expected},
                    'stored poster, administrator and email preferences remain distinct' );
            };
        }
    }
};

done_testing();
