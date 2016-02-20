#!/usr/bin/perl

use warnings;
use strict;
use 5.010;

use Getopt::Long;

# first, try to determine the user's github username: see if they gave a
# --github-user arg, or if the env var GITHUB_USER is set

my $GITHUB_USER;
my $DW_NONFREE;

GetOptions(
    'github-user=s' => \$GITHUB_USER,
    'dw-nonfree!'   => \$DW_NONFREE,
);

$GITHUB_USER //= $ENV{GITHUB_USER} if exists $ENV{GITHUB_USER};

die "Can't find your github username! " .
    "Try bootstrap.pl --github-user <username>\n"
    unless defined $GITHUB_USER;

# github https user url: eg https://rahaeli@github.com/rahaeli
my $github_user_url = "https://$GITHUB_USER\@github.com/$GITHUB_USER";

# see if we can reach a git executable
system('bash', '-c', 'type git');
die "I can't find git on your system -- is it installed?" unless $? == 0;

# see if LJHOME is defined, if it's present, and if we can go there
my $LJHOME = $ENV{LJHOME};
die "Must set the \$LJHOME environment variable before running this.\n"
    unless defined $LJHOME;
mkdir $LJHOME unless -d $LJHOME;
chdir( $LJHOME ) or die "Couldn't chdir to \$LJHOME directory.\n";

# a .git dir in $LJHOME means dw-free is checked out. otherwise, get it
if ( -d '.git' ) {
    say "Looks like you already have dw-free checked out; skipping.";
}
else {
    say "Checking out dw-free to $LJHOME";

    say "Please enter the github password for $GITHUB_USER";
    git( 'clone', $github_user_url . '/dw-free.git', $LJHOME );

    configure_dw_upstream( 'dw-free' );
}

# now get dw-nonfree if it's not there *and* the user has asked for it
if ( -d "$LJHOME/ext/dw-nonfree/.git" ) {
    say "Looks like you already have dw-nonfree checked out; skipping.";
}
elsif ( $DW_NONFREE ) {
    say "Checking out dw-nonfree to $LJHOME/ext";
    say "Please use dw-nonfree for dreamwidth.org development only.";
    say "See $LJHOME/ext/dw-nonfree/README for details.";

    chdir( "$LJHOME/ext" ) or die "Couldn't chdir to ext directory.\n";
    say "Please enter the github password for $GITHUB_USER";
    git( 'clone', $github_user_url . '/dw-nonfree.git' );

    chdir( "$LJHOME/ext/dw-nonfree" )
        or die "Couldn't chdir to dw-nonfree directory.\n";

    configure_dw_upstream( 'dw-nonfree' );
}
else {
    say "dw-nonfree not installed since it wasn't requested.";
    say "If you are developing for dreamwidth.org, you can install";
    say "the Dreamwidth-specific items in dw-nonfree by running this";
    say "command again with the option --dw-nonfree:";
    say "    perl bootstrap.pl --github-user <username> --dw-nonfree";
}

# a little syntactic sugar: run a git command
sub git {
    system( 'git', @_ );
    die "failure trying to run: git @_: $!\n" unless $? == 0;
}

sub configure_dw_upstream {
    my ($repo) = @_;

    say "Configuring dreamwidth's $repo as the upstream of your $repo.";

    my $dw_repo_url = "https://github.com/dreamwidth/$repo";
    git( qw{remote add dreamwidth}, $dw_repo_url );
    git( qw{fetch dreamwidth} );
    git( qw{branch --set-upstream develop dreamwidth/develop} );
    git( qw{branch --set-upstream master dreamwidth/master} );
}

# finished :-)
say "Done! You probably want to set up the MySQL database next:";
say "http://wiki.dreamwidth.net/notes/Dreamwidth_Scratch_Installation#Database_setup";
