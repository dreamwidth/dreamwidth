# t/importer-admin.t
#
# Tests the importer history admin page: the actions on it only work for an administrator
# with a valid form, they change the import, and a log can only be read as the user it
# belongs to.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );
use HTTP::Request;
use HTTP::Request::Common;

use DW::Controller::Admin::Importer;
use DW::Importer::LogStore;
use DW::Importer::Registry;
use DW::Request::Standard;

my $reg = 'DW::Importer::Registry';

{

    package Test::AdminImport::Worker;
    use base 'DW::Importer::Job';
    sub run { }

    package Test::AdminImport::First;
    use base 'Test::AdminImport::Worker';

    package Test::AdminImport::Second;
    use base 'Test::AdminImport::Worker';
}
$reg->register_source( name => 'admintest', kind => 'file', enabled => sub { 1 } );
$reg->register_item(
    name   => 'at_first',
    source => 'admintest',
    class  => 'Test::AdminImport::First',
    typeid => 9420,
);
$reg->register_item(
    name       => 'at_second',
    source     => 'admintest',
    class      => 'Test::AdminImport::Second',
    typeid     => 9421,
    depends_on => ['at_first'],
);
END { $reg->unregister_source('admintest') }

# The statushistory table can't be written with every MySQL setting the tests run under.
{
    no warnings 'redefine';
    *LJ::statushistory_add = sub { 1 };
}

my $admin = temp_user();
$admin->grant_priv( 'siteadmin', 'importhistory' );
my $other_admin = temp_user();    # an administrator of something else
$other_admin->grant_priv( 'siteadmin', 'theschwartz' );

# an import in the given statuses
sub setup {
    my ( $u, %status ) = @_;
    my $dbh = LJ::get_db_writer();
    $dbh->do(
'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5, options) '
            . 'VALUES (?, 1, ?, ?, ?, ?)',
        undef, $u->id, 'remote.example', 'someone', 'x', Storable::nfreeze( {} )
    );
    foreach my $name ( keys %status ) {
        $dbh->do(
            'INSERT INTO import_items (userid, item, status, created, last_touch, import_data_id, '
                . 'priority) VALUES (?, ?, ?, UNIX_TIMESTAMP(), 0, 1, 0)',
            undef, $u->id, "at_$name", $status{$name}
        );
    }
}

sub statuses {
    my ($u) = @_;
    my $rows =
        LJ::get_db_writer()
        ->selectall_arrayref(
        'SELECT item, status FROM import_items WHERE userid = ? AND import_data_id = 1',
        undef, $u->id );
    return { map { my $n = $_->[0]; $n =~ s/^at_//; $n => $_->[1] } @$rows };
}

# Runs a controller as $remote with a request built by $request->( $form_auth ), and returns
# the page it printed.
sub visit {
    my ( $controller, $remote, $request ) = @_;

    LJ::start_request();
    DW::Request->reset;
    DW::Request::Standard->new( HTTP::Request->new( GET => 'http://www.dw.test/' ) );
    LJ::set_remote($remote);

    my $auth = LJ::form_auth(1);

    DW::Request->reset;
    my $r = DW::Request::Standard->new( $request->($auth) );
    LJ::set_remote($remote);
    {
        no strict 'refs';
        &{"DW::Controller::Admin::Importer::$controller"}();
    }
    return $r->{res}->content;
}

sub act {
    my ( $remote, $u, $action, %extra ) = @_;
    my $form_auth = delete $extra{form_auth};
    return visit(
        'history_controller',
        $remote,
        sub {
            POST 'http://www.dw.test/admin/importer/history',
                Content => [
                user           => $u->user,
                import_data_id => 1,
                action         => $action,
                lj_form_auth   => $form_auth // $_[0],
                %extra
                ];
        }
    );
}

# an administrator with a valid form can cancel and retry
{
    my $u = temp_user();
    setup( $u, first => 'queued', second => 'init' );
    act( $admin, $u, 'cancel' );
    is_deeply(
        statuses($u),
        { first => 'aborted', second => 'aborted' },
        'cancel aborts the import'
    );

    act( $admin, $u, 'retry' );
    is_deeply( statuses($u), { first => 'ready', second => 'init' }, 'retry resets it' );

    LJ::get_db_writer()
        ->do( "UPDATE import_items SET status = 'succeeded' WHERE userid = ?", undef, $u->id );
    act( $admin, $u, 'rerun', item => 'at_second' );
    is_deeply(
        statuses($u),
        { first => 'succeeded', second => 'ready' },
        'rerun runs one item again'
    );
}

# without the privilege, or without a valid form, nothing happens
{
    my $u = temp_user();
    setup( $u, first => 'queued', second => 'init' );
    my $before = statuses($u);

    act( temp_user(), $u, 'cancel' );
    is_deeply( statuses($u), $before, 'a user with no privileges can not cancel' );

    act( $other_admin, $u, 'cancel' );
    is_deeply( statuses($u), $before, 'nor an administrator with other privileges' );

    act( $admin, $u, 'cancel', form_auth => 'forged' );
    is_deeply( statuses($u), $before, 'a bad form token does not cancel' );

    my $other_token;
    visit( 'history_controller', $other_admin,
        sub { $other_token = $_[0]; GET 'http://www.dw.test/' } );
    act( $admin, $u, 'cancel', form_auth => $other_token );
    is_deeply( statuses($u), $before, "nor does another user's form token" );

    act( $admin, $u, 'cancel', import_data_id => 7 );
    is_deeply( statuses($u), $before, 'an import that is not the user\'s is not touched' );

    act( $admin, $u, 'cancel' );
    is_deeply( statuses($u), { first => 'aborted', second => 'aborted' }, 'with both it works' );
}

# logs are only shown as the user they belong to
{
    my $u     = temp_user();
    my $other = temp_user();
    my %meta  = ( import_data_id => 1, item => 'at_first', started => time, updated => time );

    $DW::Importer::LogStore::LOGS{9001} = {
        meta => {
            %meta,
            logid  => 9001,
            userid => $u->id,
            chunks => 1,
            bytes  => 11,
            host   => 'h',
            pid    => 1
        },
        text => "zzmarker <one>\n",
    };

    my $get = sub {
        my ( $remote, $user, $logid ) = @_;
        return visit(
            'log_controller',
            $remote,
            sub {
                GET "http://www.dw.test/admin/importer/log?user=" . $user->user . "&logid=$logid";
            }
        );
    };

    like(
        $get->( $admin, $u, 9001 ),
        qr/zzmarker &lt;one&gt;/,
        'the owner\'s log is shown, escaped'
    );
    unlike( $get->( $admin, $other, 9001 ), qr/zzmarker/, 'a log is not shown under another user' );
    unlike( $get->( temp_user(), $u, 9001 ), qr/zzmarker/, 'nor to someone without the privilege' );
    unlike( $get->( $admin, $u, 'x' ), qr/zzmarker/,
        'a log id that is not a number shows nothing' );
}

done_testing();
