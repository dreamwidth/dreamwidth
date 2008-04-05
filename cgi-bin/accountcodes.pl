#!/usr/bin/perl

package LJ;

# <LJFUNC>
# name: LJ::acid_encode
# des: Given a decimal number, returns base 30 encoding
#      using an alphabet of letters & numbers that are
#      not easily mistaken for each other.
# returns: Base 30 encoding, alwyas 7 characters long.
# args: number
# des-number: Number to encode in base 30.
# </LJFUNC>
sub acid_encode
{
    my $num = shift;
    my $acid = "";
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    while ($num) {
        my $dig = $num % 30;
        $acid = substr($digits, $dig, 1) . $acid;
        $num = ($num - $dig) / 30;
    }
    return ("a"x(7-length($acid)) . $acid);
}

# <LJFUNC>
# name: LJ::acid_decode
# des: Given an acid encoding from [func[LJ::acid_encode]],
#      returns the original decimal number.
# returns: Integer.
# args: acid
# des-acid: base 30 number from [func[LJ::acid_encode]].
# </LJFUNC>
sub acid_decode
{
    my $acid = shift;
    $acid = lc($acid);
    my %val;
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    for (0..30) { $val{substr($digits,$_,1)} = $_; }
    my $num = 0;
    my $place = 0;
    while ($acid) {
        return 0 unless ($acid =~ s/[$digits]$//o);
        $num += $val{$&} * (30 ** $place++);
    }
    return $num;
}

# <LJFUNC>
# name: LJ::acct_code_generate
# des: Creates invitation code(s) from an optional userid
#      for use by anybody.
# returns: Code generated (if quantity 1),
#          number of codes generated (if quantity>1),
#          or undef on failure.
# args: dbarg?, userid?, quantity?
# des-userid: Userid to make the invitation code from,
#             else the code will be from userid 0 (system)
# des-quantity: Number of codes to generate (default 1)
# </LJFUNC>
sub acct_code_generate
{
    &nodb;
    my $userid = int(shift);
    my $quantity = shift || 1;

    my $dbh = LJ::get_db_writer();

    my @authcodes = map {LJ::make_auth_code(5)} 1..$quantity;
    my @values = map {"(NULL, $userid, 0, '$_')"} @authcodes;
    my $sql = "INSERT INTO acctcode (acid, userid, rcptid, auth) "
            . "VALUES " . join(",", @values);
    my $num_rows = $dbh->do($sql) or return undef;

    if ($quantity == 1) {
        my $acid = $dbh->{'mysql_insertid'} or return undef;
        return acct_code_encode($acid, $authcodes[0]);
    } else {
        return $num_rows;
    }
}

# <LJFUNC>
# name: LJ::acct_code_encode
# des: Given an account ID integer and a 5 digit auth code, returns
#      a 12 digit account code.
# returns: 12 digit account code.
# args: acid, auth
# des-acid: account ID, a 4 byte unsigned integer
# des-auth: 5 random characters from base 30 alphabet.
# </LJFUNC>
sub acct_code_encode
{
    my $acid = shift;
    my $auth = shift;
    return lc($auth) . acid_encode($acid);
}

# <LJFUNC>
# name: LJ::acct_code_decode
# des: Breaks an account code down into its two parts
# returns: list of (account ID, auth code)
# args: code
# des-code: 12 digit account code
# </LJFUNC>
sub acct_code_decode
{
    my $code = shift;
    return (acid_decode(substr($code, 5, 7)), lc(substr($code, 0, 5)));
}

# <LJFUNC>
# name: LJ::acct_code_check
# des: Checks the validity of a given account code
# returns: boolean; 0 on failure, 1 on validity. sets $$err on failure.
# args: dbarg?, code, err?, userid?
# des-code: account code to check
# des-err: optional scalar ref to put error message into on failure
# des-userid: optional userid which is allowed in the rcptid field,
#             to allow for htdocs/create.bml case when people double
#             click the submit button.
# </LJFUNC>
sub acct_code_check
{
    &nodb;
    my $code = shift;
    my $err = shift;     # optional; scalar ref
    my $userid = shift;  # optional; acceptable userid (double-click proof)

    my $dbh = LJ::get_db_writer();

    unless (length($code) == 12) {
        $$err = "Malformed code; not 12 characters.";
        return 0;
    }

    my ($acid, $auth) = acct_code_decode($code);

    my $ac = $dbh->selectrow_hashref("SELECT userid, rcptid, auth ".
                                     "FROM acctcode WHERE acid=?",
                                     undef, $acid);

    unless ($ac && $ac->{'auth'} eq $auth) {
        $$err = "Invalid account code.";
        return 0;
    }

    if ($ac->{'rcptid'} && $ac->{'rcptid'} != $userid) {
        $$err = "This code has already been used: $code";
        return 0;
    }

    # is the journal this code came from suspended?
    my $u = LJ::load_userid($ac->{'userid'});
    if ($u && $u->{'statusvis'} eq "S") {
        $$err = "Code belongs to a suspended account.";
        return 0;
    }

    return 1;
}


1;
