#!/usr/bin/perl
#
# finger server.
#
# accepts two optional arguments, host and port.
# doesn't daemonize.
#
#
# <LJDEP>
# lib: Socket::, Text::Wrap, cgi-bin/ljlib.pl
# </LJDEP>

my $bindhost = shift @ARGV;
my $port = shift @ARGV;

unless ($bindhost) {
    $bindhost = "0.0.0.0";
}

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

use Socket;
use Text::Wrap;

$SIG{'INT'} = sub {
    print "Interrupt caught!\n";
    close FH;
    close CL;
    exit;
};

my $proto = getprotobyname('tcp');
socket(FH, PF_INET, SOCK_STREAM, $proto) || die $!;

$port ||= 79;
my $localaddr = inet_aton($bindhost);
my $sin = sockaddr_in($port, $localaddr);
setsockopt (FH,SOL_SOCKET,SO_REUSEADDR,1) or
    die "setsockopt() failed: $!\n";
bind (FH, $sin) || die $!;

listen(FH, 10);

while (LJ::start_request())
{
    accept(CL, FH) || die $!;

    my $line = <CL>;
    chomp $line;
    $line =~ s/\0//g;
    $line =~ s/\s//g;

    if ($line eq "") {
        print CL "Welcome to the $LJ::SITENAME finger server!

You can make queries in the following form:

   \@$LJ::DOMAIN              - this help message
   user\@$LJ::DOMAIN          - their userinfo
";
        close CL;
        next;
    }

    my $dbr = LJ::get_dbh("slave", "master");

    if ($line =~ /^(\w{1,15})$/) {
        # userinfo!
        my $user = $1;
        my $quser = $dbr->quote($user);
        my $sth = $dbr->prepare("SELECT user, has_bio, caps, userid, name, email, bdate, allow_infoshow FROM user WHERE user=$quser");
        $sth->execute;
        my $u = $sth->fetchrow_hashref;
        unless ($u) {
            print CL "\nUnknown user ($user)\n";
            close CL;
            next;
        }

        my $bio;
        if ($u->{'has_bio'} eq "Y") {
            $sth = $dbr->prepare("SELECT bio FROM userbio WHERE userid=$u->{'userid'}");
            $sth->execute;
            ($bio) = $sth->fetchrow_array;
        }
        delete $u->{'has_bio'};

        $u->{'accttype'} = LJ::name_caps($u->{'caps'});

        if ($u->{'allow_infoshow'} eq "Y") {
              LJ::load_user_props($dbr, $u, "opt_whatemailshow",
                                "country", "state", "city", "zip",
                                "aolim", "icq", "url", "urlname",
                                "yahoo", "msn");
        } else {
            $u->{'opt_whatemailshow'} = "N";
        }
        delete $u->{'allow_infoshow'};

        if ($u->{'opt_whatemailshow'} eq "L") {
            delete $u->{'email'};
        } 
        if ($LJ::USER_EMAIL && LJ::get_cap($u, "useremail")) {
            if ($u->{'email'}) { $u->{'email'} .= ", "; }
            $u->{'email'} .= "$user\@$LJ::USER_DOMAIN";
        }

        if ($u->{'opt_whatemailshow'} eq "N") {
            delete $u->{'email'};
        } 
        delete $u->{'opt_whatemailshow'};

        my $max = 1;
        foreach (keys %$u) {
            if (length($_) > $max) { $max = length($_); }
        }
        $max++;

        delete $u->{'caps'};

        print CL "\nUserinfo for $user...\n\n";
        foreach my $k (sort keys %$u) {
            printf CL "%${max}s : %s\n", $k, $u->{$k};
        }
        
        if ($bio) {
            $bio =~ s/^\s+//;
            $bio =~ s/\s+$//;
            print CL "\nBio:\n\n";
            $Text::Wrap::columns = 77;
            print CL Text::Wrap::wrap("   ", "   ", $bio);
        }
        print CL "\n\n";
        
        close CL;
        next;
        
    }

    print CL "Unsupported/unimplemented query type: $line\n";
    print CL "length: ", length($line), "\n";
    close CL;
    next;
}
