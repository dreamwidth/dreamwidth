#!/usr/bin/perl
# Disposable owned RTE entry for native spellcheck browser acceptance.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json decode_json);
use Storable qw(nfreeze thaw);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Entry;
use LJ::Test qw(temp_user);

my $u        = temp_user();
my $password = 'spellcheck-browser-' . LJ::rand_chars(12);
$u->set_password($password);
$u->update_self( { status => 'A' } );
$u->set_draft_text('Spellcheck draft body');
$u->set_prop( 'draft_properties',
    nfreeze( { subject => 'Spellcheck draft subject', editor => 'rte0' } ) );
my $entry = $u->t_post_fake_entry(
    subject  => 'Stored spellcheck browser subject',
    body     => '<p>Stored spellcheck browser body</p>',
    security => 'private',
);
$entry->set_prop( editor => 'rte0' );
$| = 1;
print encode_json( { user => $u->user, password => $password, ditemid => $entry->ditemid } ) . "\n";

while (<STDIN>) {
    next unless /^verify\s*$/;
    LJ::Entry::reset_singletons();
    my $fresh = LJ::Entry->new( $u, ditemid => $entry->ditemid );
    my $draft = $u->prop('draft_properties');
    my $props = $draft ? thaw($draft) : {};
    print encode_json(
        {
            subject       => $fresh->subject_raw,
            body          => $fresh->event_raw,
            editor        => $fresh->prop('editor') || '',
            draft_body    => $u->draft_text || '',
            draft_subject => $props->{subject} || '',
        }
    ) . "\n";
}
