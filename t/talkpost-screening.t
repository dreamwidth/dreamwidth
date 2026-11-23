# t/talkpost-screening.t
#
# Test automatic screening of comments in personal journals and communities.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );
use LJ::Talk;

# CAPTCHA has separate tests. Keep it from preventing anonymous comments from
# reaching the real screening decision.
{
    no warnings qw( redefine once );
    local *LJ::Talk::Post::require_captcha_test = sub { return ''; };

    my @levels = ( '', 'N', 'R', 'F', 'A' );
    my %states = (
        ''  => [ 'A', 'A', 'A' ],
        'N' => [ 'A', 'A', 'A' ],
        'R' => [ 'S', 'A', 'A' ],
        'F' => [ 'S', 'S', 'A' ],
        'A' => [ 'S', 'S', 'S' ],
    );

    for my $type ( 'personal', 'community' ) {
        subtest $type => sub {
            my $journal  = $type eq 'personal' ? temp_user() : temp_comm();
            my $stranger = temp_user();
            my $trusted  = temp_user();
            $_->update_self( { status => 'A' } ) for ( $journal, $stranger, $trusted );
            $journal->update_self( { opt_whocanreply => 'all' } );
            if ( $type eq 'personal' ) {
                $journal->add_edge( $trusted, trust => { nonotify => 1 } );
            }
            else {
                $trusted->join_community( $journal, 1, 1 );
            }
            DW::Cache->request->clear_ns('rel');

            my $entry =
                  $type eq 'personal'
                ? $journal->t_post_fake_entry()
                : $trusted->t_post_fake_entry( usejournal => $journal->user, usejournal_okay => 1 );
            ok( $entry, 'Created a real entry' ) or return;

            my @commenters = ( undef, $stranger, $trusted );
            my @names      = ( 'anonymous', 'stranger', 'trusted or member' );
            my $prepare    = sub {
                my ($commenter) = @_;
                my @errors;
                my $need_captcha = 0;
                my $comment      = LJ::Talk::Post::prepare_and_validate_comment(
                    { body => 'Screening test comment', subject => 'Screening' },
                    $commenter, $entry, \$need_captcha, \@errors );
                diag( join( "\n", @errors ) ) if @errors;
                return $comment ? $comment->{state} : 'rejected';
            };

            for my $journal_level (@levels) {
                $journal->set_prop( opt_whoscreened => $journal_level );
                for my $entry_level (@levels) {
                    LJ::set_logprop( $journal, $entry->jitemid, { opt_screening => $entry_level } );
                    my $effective = length $entry_level ? $entry_level : $journal_level;
                    my $label     = sprintf(
                        'journal=%s entry=%s',
                        $journal_level || 'unset',
                        $entry_level   || 'inherit'
                    );
                    subtest $label => sub {
                        for my $i ( 0 .. $#commenters ) {
                            is( $prepare->( $commenters[$i] ), $states{$effective}[$i],
                                $names[$i] );
                        }

                        # Selective screening overrides both inherited settings and an
                        # explicit entry setting of "none", even for trusted commenters.
                        for my $i ( 1, 2 ) {
                            LJ::set_rel( $journal, $commenters[$i], 'S' );
                            DW::Cache->request->clear_ns('rel');
                            is( $prepare->( $commenters[$i] ),
                                'S', "selectively screened $names[$i]" );
                            LJ::clear_rel( $journal, $commenters[$i], 'S' );
                            DW::Cache->request->clear_ns('rel');
                            is(
                                $prepare->( $commenters[$i] ),
                                $states{$effective}[$i],
                                "clearing selective screening restores $names[$i]"
                            );
                        }
                    };
                }
            }
        };
    }

}

done_testing();
