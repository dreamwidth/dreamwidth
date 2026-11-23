# t/export-comments.t
#
# Test /export_comments: comment_body output must match the original
# load-everything-at-once implementation for every window, and the shipped
# jbackup must back up every comment.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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
use LJ::Protocol;
use LJ::Talk;
use LJ::Test qw( temp_user );
use DW::Request::Standard;
use HTTP::Request;
use HTTP::Request::Common;
use Plack::Test;

my $u         = temp_user();
my $poster    = temp_user();
my $suspended = temp_user();
my $entry     = $u->t_post_fake_entry( subject => 'export test' );
my $entry2    = $u->t_post_fake_entry( subject => 'second entry' );

# Enough comments to span several 250-comment load batches, mixing short ones,
# long ones that need escaping, a suspended poster, screened and deleted
# comments, and replies.
my @comments;
my $long = q{<b>"long" & 'quoted'</b> } x 600;
for my $i ( 1 .. 520 ) {
    my $who  = $i % 3 == 0  ? $u    : $i % 7 == 0 ? $suspended : $poster;
    my $body = $i % 50 == 0 ? $long : "comment $i " . ( 'x' x ( $i % 40 ) );
    push @comments,
        $entry->t_enter_comment(
        u    => $who,
        body => $body,
        ( @comments && $i % 4 == 0 ? ( parent => $comments[-1] ) : () )
        );
}
push @comments, $entry2->t_enter_comment( u => $poster, body => 'on another entry' );
my $deleted_with_reply = $comments[10];    # comment 12 replies to it
my $deleted_leaf       = $comments[400];
$_->delete foreach $deleted_with_reply, $deleted_leaf;
my $screened = $comments[20];
LJ::Talk::screen_comment( $u, $entry->jitemid, $screened->jtalkid );
$suspended->set_suspended( $u, 'export test' );

my @all_ids = map { $_->jtalkid } @comments;
my ( $first, $last ) = ( $all_ids[0], $all_ids[-1] );

# Log in the journal owner the way jbackup does, via a protocol session.
my $sess = do {
    DW::Request->reset;
    DW::Request::Standard->new( HTTP::Request->new( GET => 'http://www.dw.test/' ) );
    my $err;
    my $res =
        LJ::Protocol::do_request( 'sessiongenerate',
        { username => $u->user, expiration => 'short' },
        \$err, { noauth => 1 } );
    DW::Request->reset;
    $res->{ljsession} or die "sessiongenerate: $err";
};

my $app  = do "$ENV{LJHOME}/app.psgi" or die $@;
my $test = Plack::Test->create($app);

my $fetch = sub {
    my ( $mode, $startid, $numitems, $extra ) = @_;
    $extra //= '';
    my $res = $test->request(
        GET
"http://www.dw.test/export_comments?get=$mode&startid=$startid&numitems=$numitems$extra",
        Cookie => "ljsession=$sess"
    );
    die "HTTP " . $res->code unless $res->is_success;
    return $res->content;
};

# comment_body as rendered before posters, text and props were loaded in
# batches: everything for the window at once, with suspended posters filtered
# after loading text.
my $reference_body = sub {
    my ( $startid, $numitems, $want_props ) = @_;
    my $dbcr   = LJ::get_cluster_reader($u);
    my $userid = $u->userid;
    my $rows   = $dbcr->selectall_arrayref(
        'SELECT jtalkid, nodeid, parenttalkid, posterid, state, datepost '
            . "FROM talk2 WHERE nodetype = 'L' AND journalid = ? AND "
            . "                 jtalkid >= ? AND jtalkid < ?",
        undef, $userid, $startid, $startid + $numitems
    );
    my ( %posterids, %comments );
    foreach my $r (@$rows) {
        $comments{ $r->[0] } = {
            nodeid       => $r->[1],
            parenttalkid => $r->[2],
            posterid     => $r->[3],
            state        => $r->[4],
            datepost     => $r->[5],
        };
        $posterids{ $r->[3] } = 1 if $r->[3];
    }
    my $us    = LJ::load_userids( keys %posterids );
    my @ids   = sort { $a <=> $b } keys %comments;
    my $texts = LJ::get_talktext2( $u, @ids );
    my $props = {};
    LJ::load_talk_props2( $userid, \@ids, $props ) if $want_props;

    my $xml = qq{<?xml version="1.0" encoding='utf-8'?>\n<livejournal>\n<comments>\n};
    foreach my $id (@ids) {
        my $data = $comments{$id};
        my ( $subject, $body ) = @{ $texts->{$id} || [] };
        LJ::text_uncompress( \$body );
        LJ::text_out( \$subject );
        LJ::text_out( \$body );
        $subject = LJ::exml($subject);
        $body    = LJ::exml($body);
        my $date = LJ::time_to_w3c( LJ::mysqldate_to_time( $data->{datepost} ), 'Z' );
        $data->{state} = 'D'
            if $data->{posterid}
            && $data->{posterid} != $userid
            && $us->{ $data->{posterid} }->is_suspended;

        my $ret = "<comment id='$id' jitemid='$data->{nodeid}'";
        $ret .= " posterid='$data->{posterid}'"     if $data->{posterid};
        $ret .= " state='$data->{state}'"           if $data->{state} ne 'A';
        $ret .= " parentid='$data->{parenttalkid}'" if $data->{parenttalkid};
        if ( $data->{state} eq 'D' ) {
            $ret .= " />\n";
        }
        else {
            $ret .= ">\n";
            $ret .= "<subject>$subject</subject>\n" if $subject;
            $ret .= "<body>$body</body>\n" if $body;
            $ret .= "<date>$date</date>\n";
            foreach my $propkey ( keys %{ $props->{$id} || {} } ) {
                $ret .= "<property name='$propkey'>";
                $ret .= LJ::exml( $props->{$id}->{$propkey} );
                $ret .= "</property>\n";
            }
            $ret .= "</comment>\n";
        }
        $xml .= $ret;
    }
    return $xml . "</comments>\n</livejournal>\n";
};

# Property order follows hash order, so compare it order-insensitively.
my $sort_props = sub {
    my ($xml) = @_;
    $xml =~ s{((?:<property name='[^']*'>.*?</property>\n)+)}
             {join '', sort split /(?<=<\/property>\n)/, $1}sge;
    return $xml;
};

subtest 'comment_body matches the original rendering for every window' => sub {
    my @windows = (
        [ $first, 1000 ],    # whole journal, several batches
        [ $first, 250 ],     # exactly one batch
        [ $first + 249, 2 ],       # straddles a batch boundary
        [ $first + 100, 300 ],
        [ $first + 495, 1000 ],    # tail, including the other entry's comment
        [ $last + 1,    1000 ],    # past the end: empty
        [ 0, 1 ],
    );
    foreach my $w (@windows) {
        my ( $start, $num ) = @$w;
        is(
            $fetch->( 'comment_body', $start, $num ),
            $reference_body->( $start, $num, 0 ),
            "window $start+$num identical"
        );
        is(
            $sort_props->( $fetch->( 'comment_body', $start, $num, '&props=1' ) ),
            $sort_props->( $reference_body->( $start, $num, 1 ) ),
            "window $start+$num with props identical"
        );
    }

    my $full = $fetch->( 'comment_body', $first, 1000 );
    my $n = () = $full =~ /<comment id=/g;
    is( $n, scalar @all_ids, 'every comment is listed' );
    unlike( $full, qr/<nextid>/, 'no nextid in comment_body' );
};

subtest 'comment rendering' => sub {
    my $full = $fetch->( 'comment_body', $first, 1000 );
    my %c    = map { /^<comment id='(\d+)'/ ? ( $1 => $_ ) : () }
        $full =~ m!(<comment id='\d+'[^>]*/>\n|<comment id='\d+'.*?</comment>\n)!sg;

    my ($by_suspended) = grep { $_->posterid == $suspended->userid } @comments;
    like( $c{ $by_suspended->jtalkid }, qr/state='D' \/>/, 'suspended poster shown as deleted' );
    like( $c{ $deleted_leaf->jtalkid }, qr/state='D' \/>/, 'deleted comment shown without text' );
    like(
        $c{ $deleted_with_reply->jtalkid },
        qr/state='D' \/>/,
        'deleted comment with a reply shown without text'
    );
    like( $c{ $screened->jtalkid }, qr/state='S'.*<body>/s, 'screened comment keeps its text' );
    like(
        $c{ $comments[49]->jtalkid },
        qr/&lt;b&gt;&quot;long&quot; &amp; &apos;quoted&apos;&lt;\/b&gt;/,
        'long body is XML-escaped'
    );
};

subtest 'comment_meta' => sub {
    my $xml = $fetch->( 'comment_meta', $first, 2 );
    my $n = () = $xml =~ /<comment id=/g;
    is( $n, 2, 'whole meta window returned' );
    like( $xml, qr!<maxid>$last</maxid>!, 'maxid reported' );
    like( $xml, qr!<nextid>${\ ( $first + 2 ) }</nextid>!, 'meta nextid steps by the window' );
    like( $xml, qr!<usermap id='\d+' user='\Q${\ $poster->user }\E' />!, 'usermap present' );
};

# Run the shipped jbackup against a real server and check it saved everything.
SKIP: {
    skip 'jbackup requires Term::ReadKey', 2 unless eval { require Term::ReadKey; 1 };
    require Plack::Test::Server;
    require GDBM_File;
    require DW::API::Key;

    $u->update_self( { status => 'A' } );
    my $key    = DW::API::Key->new_for_user($u);
    my $backup = "$ENV{HOME}/" . $u->user . '.jbak';
    unlink $backup;

    my $server = Plack::Test::Server->new($app);
    my $out    = do {
        open my $fh, '-|', $^X, "$ENV{LJHOME}/src/jbackup/jbackup.pl", '--sync', '--quiet',
            '--protocol=http', '--server=127.0.0.1', '--port=' . $server->port,
            '--user=' . $u->user, '--password=' . $key->hash
            or die $!;
        local $/;
        my $text = <$fh>;
        close $fh;
        $text;
    };
    is( $?, 0, 'jbackup completes' ) or diag($out);

    my %saved;
    tie %saved, 'GDBM_File', $backup, GDBM_File::GDBM_READER(), 0600 or die $!;
    my @missing =
        grep { ( $saved{"comment:state:$_"} // '' ) !~ /^\w:\d+:[1-9]\d*:/ } @all_ids;
    is_deeply( \@missing, [], 'jbackup saved every comment' );
    untie %saved;
    unlink $backup;
}

done_testing();
