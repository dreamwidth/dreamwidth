# A small LiveJournal-compatible site for the importer tests: what its XML-RPC interface
# answers for the account 'someone'. The pages and the comment export are in the XML files
# beside this one. Group 1 ("Family") is the only friend group, so a group-locked entry
# that mentions group 2 can't be mapped.
{
    username => 'someone',
    hostname => 'livejournal.com',

    tags => [ { name => 'travel', display => 1 }, { name => 'food', display => 0 } ],

    friendgroups => [ { id => 1, name => 'Family', sortorder => 10, public => 0 } ],

    friends => [
        { username => 'pal',    groupmask => 3 },
        { username => 'hidden', groupmask => 1, status => 'suspended' },
        { username => 'feed',   groupmask => 1, type => 'syndicated' },
    ],

    events => [
        {
            itemid    => 1,
            anum      => 7,
            subject   => 'A public entry',
            security  => 'public',
            allowmask => 0,
            event     => 'Hello <lj user="friend"> and welcome',
            eventtime => '2009-03-01 10:00:00',
            logtime   => '2009-03-01 10:00:05',
            props     => { picture_keyword => 'happy', current_mood => 'busy' },
        },
        {
            itemid    => 2,
            anum      => 9,
            subject   => 'A private entry',
            security  => 'private',
            allowmask => 0,
            event     => 'Just for me',
            eventtime => '2009-03-02 10:00:00',
            logtime   => '2009-03-02 10:00:05',
            props     => {},
        },
        {
            itemid    => 3,
            anum      => 11,
            subject   => 'Friends only',
            security  => 'usemask',
            allowmask => 1,
            event     => 'Friends can read this',
            eventtime => '2009-03-03 10:00:00',
            logtime   => '2009-03-03 10:00:05',
            props     => {},
        },
        {
            itemid    => 4,
            anum      => 13,
            subject   => 'Family only',
            security  => 'usemask',
            allowmask => 2,
            event     => 'The Family group',
            eventtime => '2009-03-04 10:00:00',
            logtime   => '2009-03-04 10:00:05',
            props     => {},
        },
        {
            itemid    => 5,
            anum      => 15,
            subject   => 'A group that is gone',
            security  => 'usemask',
            allowmask => 4,
            event     => 'Only group 2 could read this',
            eventtime => '2009-03-05 10:00:00',
            logtime   => '2009-03-05 10:00:05',
            props     => {},
        },
        {
            itemid    => 6,
            anum      => 17,
            subject   => 'Crossposted from here',
            security  => 'public',
            allowmask => 0,
            event     => 'We posted this to them',
            eventtime => '2009-03-06 10:00:00',
            logtime   => '2009-03-06 10:00:05',
            props     => {},
        },
    ],
}
