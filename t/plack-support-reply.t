# t/plack-support-reply.t
#
# Tests that someone who filed a support request without being logged in can
# follow up on it from the reply form on /support/see_request, using the auth
# code from their confirmation email, and that the reply form only carries the
# request's real auth code.
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
use LJ::Support;
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# ?as= impersonation is dev-only.
local $LJ::IS_DEV_SERVER = 1;

# Email requests can arrive by mail even where the web form is logged-in only.
local $LJ::DISABLED{loggedout_support_requests} = 0;

# Don't queue staff notifications for the requests made here.
no warnings 'redefine';
local *LJ::Support::support_notify = sub { 1 };
use warnings 'redefine';

my $dbh = LJ::get_db_writer();

my $spcatid = LJ::Support::define_cat(
    {
        catkey         => "t-reply-$$",
        catname        => 'Reply test',
        sortorder      => 0,
        basepoints     => 1,
        is_selectable  => 0,
        public_read    => 0,
        public_help    => 0,
        allow_screened => 0,
        hide_helpers   => 0,
        user_closeable => 1,
        no_autoreply   => 1,
        scope          => 'general',
    }
);

my @spids;

END {
    if ($dbh) {
        foreach my $spid (@spids) {
            $dbh->do( "DELETE FROM $_ WHERE spid=?", undef, $spid )
                for qw( supportlog supportprop support_youreplied support );
        }
    }
    LJ::Support::delete_cat($spcatid) if $spcatid;
}

sub file_request {
    my %opts = @_;
    my @errors;
    my $spid = LJ::Support::file_request(
        \@errors,
        {
            spcatid          => $spcatid,
            subject          => 'Reply test request',
            body             => 'Original request body',
            uniq             => 'supportReplyTest',
            useragent        => 'support reply test',
            no_autoreply     => 1,
            ignore_dup_check => 1,
            %opts,
        }
    );
    die "couldn't file a test request: @errors" unless $spid;
    push @spids, $spid;
    return $spid;
}

sub replies {
    my $spid = shift;
    return $dbh->selectcol_arrayref(
        "SELECT message FROM supportlog WHERE spid=? AND type='comment' ORDER BY splid",
        undef, $spid );
}

# The hidden fields of the reply form on a /support/see_request page.
sub reply_form_fields {
    my $content = shift;
    my ($form) = $content =~ m{(<form[^>]+action='[^']*/support/append_request'.*?</form>)}s;
    return unless $form;

    my %fields;
    while ( $form =~ /<input\b([^>]*)>/g ) {
        my $attrs = $1;
        next unless $attrs =~ /type=["']hidden["']/;
        my ($name)  = $attrs =~ /name=["']([^"']*)["']/;
        my ($value) = $attrs =~ /value=["']([^"']*)["']/;
        $fields{$name} = $value // '' if defined $name;
    }
    return \%fields;
}

with_fake_memcache {
    test_psgi $app, sub {
        my $cb = shift;

        # 1. A logged-out requester follows the link in their confirmation
        #    email and submits the page's reply form as a browser would.
        my $spid = file_request(
            reqtype  => 'email',
            reqname  => 'Logged-out requester',
            reqemail => 'support-reply-test@example.com',
        );
        my $auth = LJ::Support::mini_auth( LJ::Support::load_request($spid) );

        my $res = $cb->( GET "http://localhost/support/see_request?id=$spid&auth=$auth" );
        is( $res->code, 200, 'requester can view their request with the emailed auth code' );

        my $fields = reply_form_fields( $res->content );
        ok( $fields, 'request page offers the requester a reply form' );

        $res = $cb->(
            POST "http://localhost/support/append_request",
            Content => [ %{ $fields // {} }, reply => 'Follow-up from the requester' ],
        );
        is( $res->code, 200, 'reply is accepted rather than sent to the login page' )
            or diag( 'Location: ' . ( $res->header('Location') // '' ) );
        is_deeply(
            replies($spid),
            ['Follow-up from the requester'],
            'reply is added to the request'
        );

        # Without the right auth code a logged-out reply is still refused.
        my $before = replies($spid);
        my %wrong  = ( %{ $fields // {} }, auth => 'nope', reply => 'Reply from a stranger' );
        $res = $cb->( POST "http://localhost/support/append_request", Content => [%wrong] );
        is( $res->code, 302, 'reply with a wrong auth code is refused' );
        like( $res->header('Location') // '', qr{/login\?}, '... and sent to the login page' );
        is_deeply( replies($spid), $before, '... without adding anything to the request' );

        # 2. The reply form doesn't carry a code that belongs to another request.
        my $u = temp_user();
        $spid = file_request(
            reqtype   => 'user',
            requserid => $u->id,
            reqname   => $u->user,
            reqemail  => $u->email_raw,
        );
        my $as = $u->user;

        $res = $cb->( GET "http://localhost/support/see_request?id=$spid&as=$as&auth=$auth" );
        is( $res->code, 200, 'logged-in requester can view their request' );
        $fields = reply_form_fields( $res->content ) // {};
        ok( %$fields, '... with a reply form' );
        is( $fields->{auth} // '', '', "... that doesn't carry another request's code" );
    };
};

done_testing();
