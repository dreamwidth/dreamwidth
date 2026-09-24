#!/usr/bin/perl
use strict;
use warnings;
use JSON qw(encode_json decode_json);
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
use LJ::Entry;
use LJ::MemCache;
my $u        = temp_user();
my $password = "edit-modes-" . LJ::rand_chars(12);
$u->set_password($password);
$u->update_self( { status => "A" } );
my @cases = (
    { name => "casual HTML", editor => "html_casual1", body => "<strong>casual original</strong>" },
    { name => "raw HTML",    editor => "html_raw0",    body => "<i>raw original</i>" },
    { name => "Markdown",    editor => "markdown0",    body => "*markdown original*" },
    {
        name   => "legacy Markdown detection",
        editor => undef,
        body   => "!markdown\n*legacy original*",
        legacy => 1
    },
    { name => "Rich Text Editor", editor => "rte0", body => "<p>RTE original</p>" }
);
my @ids;

for my $c (@cases) {
    my $e = $u->t_post_fake_entry(
        subject  => "mode",
        body     => $c->{legacy} ? "temp" : $c->{body},
        security => "private"
    );
    $e->set_prop( editor => $c->{editor} ) if defined $c->{editor};
    if ( $c->{legacy} ) {
        $u->do(
            "UPDATE logtext2 SET event=? WHERE journalid=? AND jitemid=?",
            undef, LJ::text_compress( $c->{body} ),
            $u->id, $e->jitemid
        );
        LJ::MemCache::set(
            [ $u->id, "logtext:" . $u->clusterid . ":" . $u->id . ":" . $e->jitemid ],
            [ "mode", $c->{body} ] );
        LJ::Entry::reset_singletons();
    }
    push @ids, $e->ditemid;
}
$| = 1;
my @browser_cases = map {
    {
        name            => $_->{name},
        legacy          => $_->{legacy} ? JSON::true : JSON::false,
        rendered_editor => $_->{editor} || 'markdown0',
        rendered_body   => $_->{legacy} ? "*legacy original*" : $_->{body},
        stored_editor   => $_->{editor} || '',
        stored_body     => $_->{body},
    }
} @cases;
print encode_json(
    { user => $u->user, password => $password, ids => \@ids, cases => \@browser_cases } )
    . "\n";
while (<STDIN>) {
    my $q = decode_json($_);
    LJ::Entry::reset_singletons();
    my $e = LJ::Entry->new( $u, ditemid => $ids[ $q->{index} ] );
    print encode_json( { body => $e->event_raw, editor => $e->prop("editor") || "" } ) . "\n";
}
