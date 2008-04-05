# these are the email gateway functions needed from web land.  they're
# also available from ljemailgateway.pl (which contains the full
# libraries)

package LJ::Emailpost;
use strict;

# Retreives an allowed email addr list for a given user object.
# Returns a hashref with addresses / flags.
# Used for ljemailgateway and manage/emailpost.bml
sub get_allowed_senders {
    my $u = shift;
    my (%addr, @address);

    LJ::load_user_props($u, 'emailpost_allowfrom');
    @address = split(/\s*,\s*/, $u->{emailpost_allowfrom});
    return undef unless scalar(@address) > 0;

    my %flag_english = ( 'E' => 'get_errors' );

    foreach my $add (@address) {
        my $flags;
        $flags = $1 if $add =~ s/\((.+)\)$//;
        $addr{$add} = {};
        if ($flags) {
            $addr{$add}->{$flag_english{$_}} = 1 foreach split(//, $flags);
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
    my ($u, $addr) = @_;
    my %flag_letters = ( 'get_errors' => 'E' );

    my @addresses;
    foreach (keys %$addr) {
        my $email = $_;
        my $flags = $addr->{$_};
        if (%$flags) {
            $email .= '(';
            foreach my $flag (keys %$flags) {
                $email .= $flag_letters{$flag};
            }
            $email .= ')';
        }
        push(@addresses, $email);
    }
    $u->set_prop("emailpost_allowfrom", join(", ", @addresses));
}

1;

