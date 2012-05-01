#!/usr/bin/perl

# A client for uploading S2 layers to servers v1.0
# By Martin Atkins, 2004-05-21 

# This script is public domain. Do with it what you will!

use strict;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use MIME::Base64;
use Getopt::Long;

my $url = "";
my $help = "";
my $auth = "";
my $authfile = "";
my $noninter = 0;

Getopt::Long::GetOptions('url=s' => \$url,
                         'help' => \&usage,
                         'auth=s' => \$auth,
                         'authfile=s' => \$authfile,
                         'noninteractive' => \$noninter) || usage();

($main::username, $main::password) = split(/:/, $auth, 2);

if ($authfile && ! $auth) {
    if (open(AF, '<', $authfile)) {
        my $auth = <AF>;
        chomp $auth;
        ($main::username, $main::password) = split(/:/, $auth, 2);
    }
    else {
        error("Couldn't open auth file $authfile");
    }
}

{
    # Specialised LWP::UserAgent to handle the username/password
    package UA;
    our @ISA = qw(LWP::UserAgent);

    sub new
    { 
        my $self = LWP::UserAgent::new(@_);
        $self->agent("s2up/1.0");
        return bless($self, $_[0]);
    }

    sub get_basic_credentials
    {
        my ($self, $realm, $uri) = @_;
        
        my ($user, $passwd) = ($main::username, $main::password);
        
        unless ($noninter) {
            unless (defined $user) {
                # FIXME: Maybe use readline here?
                print "Username for $realm($uri): ";
                $user = <STDIN>;
                chomp($user);
            }

            if ($user && ! defined $passwd) {
                # Ask the user for a password with no echo, if we can
                #  (ReadPassword doesn't work on Win32 at the time of writing)
                eval {
                    require Term::ReadPassword;
                };
                if ($@) {
                    print "Password for $user: ";
                    $passwd = <STDIN>;
                    chomp($passwd);
                } else {
                    $passwd = Term::ReadPassword::read_password("Password for $user: ", 0, 1);
                }
            }
        }
        return ($user, $passwd);
    }
}



my $ua = new UA;
$ua->env_proxy();

# Slurp up the input
my $code = join('', <>);

# Look for a URL
unless ($url) {
    if ($code =~ s/\burl\s*=\s*"([^\"]+)"//i) {
        # NOTE: The URL specification gets eaten, in case
        # it has username/password in it, which would be
        # a nasty thing to leave lying around.
        $url = $1;
    }
}
unless ($url) {
    error("Unable to determine layer URL");
    exit(1);
}

unless ($auth) {  # Auth on the command line "wins"

    if ($code =~ s/\bauthfile\s*=\s*"([^\"]+)"//i) {
        # NOTE: The authfile specification also gets eaten,
        #     just for cleanliness' sake.
        my $authfile = $1;
        if (open(AF, '<', $authfile)) {
            my $auth = <AF>;
            chomp $auth;
            ($main::username, $main::password) = split(/:/, $auth);
        }
        else {
            warning("Couldn't open authfile $authfile");
        }
    }
}


my $req = new HTTP::Request ( 'PUT' => $url );

$req->content($code);
$req->content_length(length($code));
$req->content_type('application/x-danga-s2-layer');

my $res = $ua->request($req);

my $status = $res->code();

if ($status == 201 || $status == 202) {
    # Success! Exit silently
    exit(0);
}
else {
    if ($res->content_type() =~ m!^\s*text/plain\b!) {
        my ($short, $long, $extra) = split(/\n/, $res->content(), 3);
        error($long);
        print "$extra\n" if $extra;
        exit(3);
    }
    else {
        error("Unparsable response. Server or intermediate proxy says: ".$res->status_line());
        exit(3);
    }
}

sub usage {
print "\n" unless $_[0];
print <<EOT;
Usage: s2up [options] [filename]
    
    Options:
        --url="..."       Specify a URL to use for uploading
        --help            Read this help message
        --auth            Specify username:password to use for authentication
        --authfile        Specify a file containing username:password
        --noninteractive  No entry prompts for any reason
        
     If no filename is specified, stdin will be used.
     If no URL is specified, the program will try to find
    a string url="..." in the layer code, which you can place
    in a comment.
     If no auth or authfile are specified, we'll look for the
    string authfile="..." in the layer code, too.
EOT
exit();
}

sub error {
    print STDERR "$0: $_[0]\n";
}

sub warning {
    error("warning: ".$_[0]);
}
