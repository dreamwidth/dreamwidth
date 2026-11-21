#!/usr/bin/perl
#
# Test the admin sendmail form manager and compose integration.
#
# Authors:
#      Alex Southwell <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Encode qw(encode_utf8);
use HTML::Entities qw(decode_entities);
use HTTP::Request::Common qw(GET POST);
use Plack::Test;
use Test::More;
use URI;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $client = Plack::Test->create($app);

my $admin  = temp_user();
my $viewer = temp_user();
$admin->grant_priv( 'siteadmin', 'sendmail' ) or die 'Could not grant sendmail privilege';
$viewer->grant_priv( 'siteadmin', 'users' ) or die 'Could not grant unrelated privilege';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'sendmailForms01';
local %LJ::SENDMAIL_ACCOUNTS          = ( support => 'siteadmin:sendmail' );

my $forms = '/admin/sendmail/forms';
my $index = '/admin/sendmail/index';

sub url {
    my ( $path, $user, @query ) = @_;
    my $uri = URI->new("http://localhost$path");
    $uri->query_form( $user ? ( as => $user->user, @query ) : @query );
    return $uri;
}

sub token {
    my ($res)  = @_;
    my ($auth) = $res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    return decode_entities( $auth // '' );
}

sub field {
    my ( $res, $name ) = @_;
    my ($input) = $res->content =~ /(<input\b[^>]*\bname="$name"[^>]*>)/;
    my ($value) = ( $input // '' ) =~ /\bvalue="([^"]*)"/;
    return decode_entities( $value // '' );
}

sub body_field {
    my ($res)   = @_;
    my ($value) = $res->content =~ /<textarea\b[^>]*\bname="message"[^>]*>(.*?)<\/textarea>/s;
    return decode_entities( $value // '' );
}

sub submit {
    my ( $path, $user, @fields ) = @_;
    return $client->request( POST url( $path, $user ), Content => \@fields );
}

my $anonymous = $client->request( GET url($forms) );
is( URI->new( $anonymous->header('Location') // '' )->path, '/login', 'requires login' );

my $unauthorized = $client->request( GET url( $forms, $viewer ) );
like(
    $unauthorized->content,
    qr/necessary privilege.*siteadmin:sendmail/,
    'requires sendmail privilege'
);

my $list = $client->request( GET url( $forms, $admin ) );
is( $list->code, 200, 'admin can view the form manager' ) or BAIL_OUT('Form manager unavailable');
my $auth = token($list);
ok( $auth, 'renders a form-auth token' ) or BAIL_OUT('Form manager has no form token');

my $dbh = LJ::get_db_writer() or die 'No database';
my $formid;

END {
    if ($formid) {
        $dbh->do( 'DELETE FROM siteadmin_email_forms WHERE formid = ?',     undef, $formid );
        $dbh->do( 'DELETE FROM siteadmin_email_history WHERE remoteid = ?', undef, $admin->id );
    }
}

my $name    = 'Account <img src="invalid"> ' . $admin->user;
my $subject = 'A "test" & <subject>';
my $body    = "First line\n</textarea><script>sendmail_test()</script>\nLast line";
my %fields  = ( action => 'save', name => $name, subject => $subject, message => $body );

sub stored {
    return $dbh->selectrow_arrayref(
        'SELECT formid, name, subject, message FROM siteadmin_email_forms WHERE name = ?',
        undef, $name );
}

my $no_priv = submit( $forms, $viewer, %fields, lj_form_auth => $auth );
like(
    $no_priv->content,
    qr/necessary privilege.*siteadmin:sendmail/,
    'cannot write without permission'
);
my $forged = submit( $forms, $admin, %fields, lj_form_auth => 'forged' );
like( $forged->content, qr/Invalid form submission/, 'forged form token rejected' );
ok( !stored(), 'rejected creates do not write a row' );

my $invalid = submit( $forms, $admin, %{ { %fields, message => ' ' } }, lj_form_auth => $auth );
like( $invalid->content, qr/Enter a message/, 'blank body is rejected' );
ok( !stored(), 'invalid form is not stored' );

my $long_subject = submit(
    $forms, $admin,
    %{ { %fields, subject => encode_utf8( "\x{e9}" x 130 ) } },
    lj_form_auth => $auth
);
like( $long_subject->content, qr/Enter a single-line subject/, 'rejects an oversized subject' );
ok( !stored(), 'oversized subject is not stored' );

my $create = submit( $forms, $admin, %fields, lj_form_auth => $auth );
is( $create->code, 303, 'create redirects to GET' );
my $row = stored();
ok( $row, 'created form is persisted' ) or BAIL_OUT('No saved form');
$formid = $row->[0];
is_deeply( $row, [ $formid, $name, $subject, $body ], 'stores plain text without HTML encoding' );

$list = $client->request( GET url( $forms, $admin ) );
like( $list->content, qr/Account &lt;img /, 'list label is escaped' );
unlike( $list->content, qr/<img src="invalid">/, 'stored markup does not become an image' );
my $edit = $client->request( GET url( $forms, $admin, id => $formid ) );
is( field( $edit, 'subject' ), $subject, 'editor prefills subject' );
is( body_field($edit), $body, 'editor prefills body as text' );
unlike( $edit->content, qr/<script>sendmail_test\(\)<\/script>/, 'editor cannot execute body' );

my $updated = encode_utf8("R\x{e9}vis\x{e9}") . ' ' . $subject;
my $save    = submit(
    $forms, $admin, %{ { %fields, subject => $updated } },
    id           => $formid,
    lj_form_auth => token($edit)
);
is( $save->code, 303, 'edit redirects to GET' );
is_deeply( stored(), [ $formid, $name, $updated, $body ], 'edit updates the same form' );

my $compose = $client->request( GET url( $index, $admin ) );
like( $compose->content, qr{href="(?:/admin/sendmail/)?forms"}, 'compose links to manager' );
like(
    $compose->content,
    qr/<option value="$formid"[^>]*>Account &lt;img /,
    'saved form is offered with an escaped label'
);

my ($sent_before) =
    $dbh->selectrow_array( 'SELECT COUNT(*) FROM siteadmin_email_history WHERE remoteid = ?',
    undef, $admin->id );
my @draft = (
    account => 'support',
    sendto  => 'recipient@example.invalid',
    request => 17,
    notes   => 'Keep this',
    subject => 'Draft subject',
    message => 'Draft body'
);
my $load = submit(
    $index, $admin, @draft,
    load_form    => 1,
    form_id      => $formid,
    lj_form_auth => token($compose)
);
is( $load->code, 200, 'load renders the compose form' );
is( field( $load, 'subject' ), $updated, 'loads saved subject' );
is( body_field($load), $body, 'loads saved body' );
is( field( $load, 'sendto' ), 'recipient@example.invalid', 'keeps recipient' );
is( field( $load, 'request' ), '17', 'keeps support request' );
unlike( $load->content, qr/<script>sendmail_test\(\)<\/script>/, 'compose cannot execute body' );
my ($sent_after) =
    $dbh->selectrow_array( 'SELECT COUNT(*) FROM siteadmin_email_history WHERE remoteid = ?',
    undef, $admin->id );
is( $sent_after, $sent_before, 'loading does not create send history' );

my $bad_delete = submit( $forms, $admin, action => 'delete', id => $formid );
like( $bad_delete->content, qr/Invalid form submission/, 'delete requires a token' );
ok( stored(), 'rejected delete leaves form intact' );
my $delete = submit( $forms, $admin, action => 'delete', id => $formid, lj_form_auth => $auth );
is( $delete->code, 303, 'delete redirects to GET' );
ok( !stored(), 'delete removes the row' );

my $gone = $client->request( GET url( $forms, $admin, id => $formid ) );
like( $gone->content, qr/form message could not be found/i,
    'missing form does not open an editor' );
my $stale = submit( $forms, $admin, %fields, id => $formid, lj_form_auth => $auth );
like( $stale->content, qr/form message could not be found/i,
    'edit cannot recreate a deleted form' );
ok( !stored(), 'stale edits do not write a row' );
my $missing = submit(
    $index, $admin, @draft,
    load_form    => 1,
    form_id      => $formid,
    lj_form_auth => token($compose)
);
like(
    $missing->content,
    qr/form message could not be found/i,
    'missing selection reports an error'
);
is( field( $missing, 'subject' ), 'Draft subject', 'missing selection keeps subject' );
is( body_field($missing), 'Draft body', 'missing selection keeps body' );

done_testing;
