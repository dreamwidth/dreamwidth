use strict;
use Test::More tests => 3;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user);

use DW::Worker::ContentImporter::LiveJournal;

note("check a username we know exists on livejournal.com");
{
    my $uid = DW::Worker::ContentImporter::LiveJournal->remap_username_friend(
        {
            hostname => "livejournal.com",
        },
        "system"
    );
    ok( $uid, "Got back a userid ($uid) for system\@livejournal.com" );
}

note(
"check an openid username on the remote site (that is, they're not local to the site we're importing from)"
);
{
    my $uid = DW::Worker::ContentImporter::LiveJournal->remap_username_friend(
        {
            hostname => "livejournal.com",
        },
        "ext_1662783"
    );

    ok( $uid, "Got back a userid ($uid) for ext_1662783\@livejournal.com" );
    is(
        LJ::load_userid($uid)->openid_identity,
        "http://ext-1662783.livejournal.com/",
        "Local user's openid URL is of format ext-1234.imported-from-site.com"
    );
}
