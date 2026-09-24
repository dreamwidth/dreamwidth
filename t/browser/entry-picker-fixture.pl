#!/usr/bin/perl
# Disposable real entries for picker browser characterization.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON::MaybeXS qw(encode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);
die 'Development server required' unless $LJ::IS_DEV_SERVER;
my $user     = temp_user();
my $comm     = temp_comm();
my $password = 'picker-browser-' . LJ::rand_chars(12);
$user->set_password($password);
$user->update_self( { status => 'A' } );
LJ::set_rel( $comm, $user, 'A' );
my $groupid = $user->create_trust_group( groupname => 'Picker browser custom security' );
my @ids;

for my $day ( 1 .. 6 ) {
    my %res;
    LJ::do_request(
        {
            mode      => 'postevent',
            ver       => $LJ::PROTOCOL_VER,
            user      => $user->user,
            subject   => "Picker browser $day",
            event     => "Visible picker body $day",
            year      => 2020,
            mon       => 1,
            day       => $day,
            hour      => 12,
            min       => 0,
            security  => $day == 1 ? 'private' : $day == 2 || $day == 3 ? 'usemask' : 'public',
            allowmask => $day == 2 ? 1 : $day == 3 ? 1 << $groupid : undef,
        },
        \%res,
        { noauth => 1, nomod => 1 }
    );
    die "Fixture posting failed: $res{errmsg}" unless $res{success} eq 'OK';
    push @ids, ( $res{itemid} << 8 ) + $res{anum};
}
my $comm_entry = $user->t_post_fake_comm_entry( $comm, body => 'Community picker body' );
$| = 1;
print encode_json(
    {
        user         => $user->user,
        password     => $password,
        community    => $comm->user,
        ids          => \@ids,
        community_id => $comm_entry->ditemid
    }
) . "\n";
<STDIN>;
