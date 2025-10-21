# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

# these are the email gateway functions needed from web land.  they're
# also available from LJ/Emailpost.pm (which contains the full libraries)

package LJ::Emailpost::Web;
use strict;

# Retrieves an allowed email addr list for a given user object.
# Returns a hashref with addresses / flags.
# Used for ljemailgateway and manage/emailpost.bml
sub get_allowed_senders {
    my ( $u, $include_user_email ) = @_;
    return undef unless LJ::isu($u);
    my ( %addr, @address );

    @address = split( /\s*,\s*/, $u->prop('emailpost_allowfrom') || '' );

    # add their personal email, and assume we want to receive errors here
    unshift @address, $u->email_raw . "(E)" if $include_user_email;

    return undef unless scalar(@address) > 0;

    my %flag_english = ( 'E' => 'get_errors' );

    foreach my $add (@address) {
        my $flags;
        $flags = $1 if $add =~ s/\((.+)\)$//;
        $addr{$add} = {};
        if ($flags) {
            $addr{$add}->{ $flag_english{$_} } = 1 foreach split( //, $flags );
        }
    }

    return \%addr;
}

# Inserts email addresses into the database.
# Adds flags if needed.
# Used in manage/emailpost.bml
#  $addr is hashref of { $email_address -> {$flag -> 1} } where possible values of $flag
#  currently include only 'get_errors', to receive errors at that email address
sub set_allowed_senders {
    my ( $u, $addr ) = @_;
    my %flag_letters = ( 'get_errors' => 'E' );

    my @addresses;
    foreach ( keys %$addr ) {
        my $email = $_;
        my $flags = $addr->{$_};
        if (%$flags) {
            $email .= '(';
            foreach my $flag ( keys %$flags ) {
                $email .= $flag_letters{$flag};
            }
            $email .= ')';
        }
        push( @addresses, $email );
    }
    $u->set_prop( "emailpost_allowfrom", join( ", ", @addresses ) );
}

1;

