#!/usr/bin/perl
# Disposable fixture for saved-draft restore and decline parity coverage.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use JSON qw(encode_json);
use Storable qw(nfreeze thaw);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Userpic;
use LJ::Test qw(temp_user);

sub file_contents {
    my ($path) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    binmode $fh;
    local $/;
    my $contents = <$fh>;
    return \$contents;
}

sub make_user {
    my ( $name, $subject, $body ) = @_;
    my $user     = temp_user();
    my $password = "draft-parity-$name-" . LJ::rand_chars(12);
    $user->set_password($password);
    $user->update_self( { status => 'A' } );
    $user->entry_editor2('markdown0');
    my $pic =
        LJ::Userpic->create( $user,
        data => file_contents("$ENV{LJHOME}/t/data/userpics/good.jpg"), )
        or die "userpic fixture failed";
    $pic->set_keywords('draft-parity-icon');
    $user->set_draft_text($body);
    $user->set_prop( 'draft_properties', nfreeze( { subject => $subject } ) );
    return {
        name     => $name,
        user     => $user->user,
        password => $password,
        body     => $body,
        subject  => $subject,
        props    => { subject => $subject },
    };
}

my %users = (
    accept  => make_user( 'accept',  'Legacy accept subject',  "!markdown\n*legacy accept body*" ),
    decline => make_user( 'decline', 'Legacy decline subject', "!markdown\n*legacy decline body*" ),
    preload => make_user( 'preload', 'Legacy preload subject', "!markdown\n*legacy preload body*" ),
);

$| = 1;
print encode_json( \%users ) . "\n";
while (<STDIN>) {
    next unless /^state\s+(accept|decline|preload)\s*$/;
    my $key  = $1;
    my $info = $users{$key};
    my $user = LJ::load_user( $info->{user}, force => 1 );
    my $props =
        $user->prop('draft_properties')
        ? Storable::thaw( $user->prop('draft_properties') )
        : {};
    print encode_json( { draft => $user->draft_text, properties => $props } ) . "\n";
}
