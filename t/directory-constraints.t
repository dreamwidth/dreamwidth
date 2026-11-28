# t/directory-constraints.t
#
# Test directory constraints and journal type filters without loading ljlib.pl.
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

use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

use Test::More;
use Test::Exception;
use Digest::SHA1 qw(sha1_hex);

use LJ::Directory::Constraint;
use LJ::Directory::SetHandle::JournalType;
use LJ::Keywords;
use LJ::TextUtil;

{

    package TestDirectoryUser;

    sub member_of_userids  { ( 12, 24 ) }
    sub trusted_userids    { ( 31, 43 ) }
    sub trusted_by_userids { ( 52, 66 ) }
}

my $constraint_class = 'LJ::Directory::Constraint';

subtest 'canonical constraint strings and cache keys' => sub {
    my $canonical  = 'Interest:interest=R%26D+%3D+C%2B%2B&intid=42';
    my $reordered  = 'Interest:intid=42&interest=R%26D+%3D+C%2B%2B';
    my $constraint = $constraint_class->deserialize($reordered);
    isa_ok( $constraint, "${constraint_class}::Interest" );
    is( $constraint->serialize, $canonical, 'reordered input produces canonical escaped text' );
    is( $constraint->memkey, 'dsh:' . sha1_hex($canonical), 'cache key uses canonical text' );

    my $direct = "${constraint_class}::Interest"->new( interest => 'R&D = C++', intid => 42 );
    is( $direct->memkey, $constraint->memkey, 'direct input and restored input share a cache key' );
    my $other = "${constraint_class}::Interest"->new( interest => 'R&D = C++', intid => 43 );
    isnt( $other->memkey, $direct->memkey, 'different constraints do not share a cache key' );
    is( $constraint_class->deserialize('interest=R%26D'), undef, 'missing type is rejected' );
};

subtest 'form arguments build only the requested constraints' => sub {
    is_deeply( [ $constraint_class->constraints_from_formargs( {} ) ],
        [], 'empty form does not apply any constraints' );

    my @constraints = $constraint_class->constraints_from_formargs(
        {
            int_like          => 'cats, R&D',
            user_is_member    => 'example',
            userid_trusted_by => 17,
            user_trusts       => 'ambiguous',
            userid_trusts     => 17,
            journaltype       => 'C',
        }
    );
    is_deeply(
        [ map { $_->serialize } @constraints ],
        [
            'Interest:interest=cats', 'Interest:interest=R%26D',
            'TrustedBy:userid=17',    'MemberOf:user=example',
            'JournalType:journaltype=C'
        ],
        'expands multiple interests and omits the ambiguous trust filter'
    );
};

subtest 'relationship filters resolve users and keep relationship directions distinct' => sub {
    my $user = bless {}, 'TestDirectoryUser';
    my @lookups;

    # Keep account lookups independent of the database; the constraints still resolve the filters.
    local *LJ::load_user = sub {
        push @lookups, [ name => $_[0] ];
        return $_[0] eq 'example' ? $user : undef;
    };
    local *LJ::load_userid = sub {
        push @lookups, [ id => $_[0] ];
        return $_[0] == 17 ? $user : undef;
    };

    for my $case (
        [ MemberOf  => 'is_member',  [ 12, 24 ] ],
        [ TrustedBy => 'trusted_by', [ 31, 43 ] ],
        [ Trusts    => 'trusts',     [ 52, 66 ] ]
        )
    {
        my ( $type, $suffix, $expected ) = @$case;
        my $class    = "${constraint_class}::$type";
        my $name_arg = "user_$suffix";
        my $id_arg   = "userid_$suffix";

        is( $class->new_from_formargs( {} ), undef, "$type rejects a missing user" );
        is( $class->new_from_formargs( { $name_arg => 'example', $id_arg => 17 } ),
            undef, "$type rejects supplying both identifiers" );
        throws_ok { $class->new( userid => 17, unexpected => 1 ) }
        qr/unknown args/, "$type rejects unknown constructor arguments";

        @lookups = ();
        my $by_name = $class->new_from_formargs( { $name_arg => 'example' } );
        my $by_id   = $class->new_from_formargs( { $id_arg   => 17 } );
        is_deeply( [ $by_name->matching_uids ], $expected, "$type matches by username" );
        is_deeply( [ $by_id->matching_uids ],   $expected, "$type matches by user ID" );
        is_deeply( [ $by_name->matching_uids ], $expected, "$type can repeat a match" );
        is_deeply(
            \@lookups,
            [ [ name => 'example' ], [ id => 17 ] ],
            "$type reuses its resolved user"
        );

        my $missing = $class->new_from_formargs( { $id_arg => 999 } );
        is_deeply( [ $missing->matching_uids ], [],
            "$type returns no matches for an unknown user" );
    }
};

subtest 'journal types select the correct search index category' => sub {
    my @categories;

    # The worker's native search index is not needed to check the numeric filter it receives.
    local *LJ::UserSearch::isect_journal_type = sub { push @categories, $_[0] };

    my $handle_class = 'LJ::Directory::SetHandle::JournalType';
    $handle_class->new($_)->filter_search for qw(P I C Y);
    is_deeply( \@categories, [ 0, 1, 2, 3 ], 'all four journal types reach the search index' );

    @categories = ();
    throws_ok { $handle_class->new('X')->filter_search }
    qr/Bogus type/, 'unsupported journal type is rejected';
    is_deeply( \@categories, [], 'unsupported type never reaches the search index' );
};

ok( !( grep { defined && m{(?:^|/)ljlib[.]pl\z} } keys %INC, values %INC ),
    'test runs without loading ljlib.pl' );

done_testing;
