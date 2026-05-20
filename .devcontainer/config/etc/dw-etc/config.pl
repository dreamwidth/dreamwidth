#!/usr/bin/perl

# Standard configuration for the .devcontainer; this should work out of the box.
# You should not need to modify this file.
#
# This is where you define general configuration items that would be shared
# across anybody who is using your code (but isn't your site.)
#
# The file order is loading config-private.pl first, config-local.pl next, and
# lastly config.pl here. So you can depend on either of those.

{
    package LJ;

    ###
    ### Site Information
    ###

    $HOME = $ENV{'LJHOME'};
    $HTDOCS = "$HOME/htdocs";
    $STATDOCS = "$HOME/build/static";
    $BIN = "$HOME/bin";
    $TEMP = "$HOME/temp";
    $VAR = "$HOME/var";
}

1;
