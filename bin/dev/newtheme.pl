#!/usr/bin/perl
#
# newtheme
# Automatic parsing of new Themes into Dreamwidth-required format
#
# By Ricky Buchanan and Momijizukamori
#

use strict;

my ( $author_name, $layout_human, $is_nonfree ) = @ARGV;

my ( $layout_name, $theme_name, $theme_human );

sub diehelp {
    warn "Syntax: newtheme AuthorName LayoutName IsNonfree";
    exit;
}

if ( !$layout_human ) {
    warn "No layout name provided.";
    diehelp;
}

( $layout_name = lc($layout_human) ) =~ s/\s|'//g;

####################
# Input section
# - collect input, do very basic parsing/checking as we collect it
####################
my ( @dropped, @css, @set, $in_css, $in_css_2 );
my $line_number = 0;
while (<STDIN>) {
    my $line = $_;
    $line_number++;

    # Warn for anything that looks like an HTML colour code but doesn't have 3 or 6 digits
    if ( ( $line =~ m/#[\da-f]+/ )
        && !( ( $line =~ m/#[\da-f]{3}\W/ ) || ( $line =~ m/#[\da-f]{6}\W/ ) ) )
    {
        print "Possibly malformed colour code detected on input line $line_number:\n";
        print ">    " . $line . "\n";
    }

    # Shorten HTML colour codes of the form #aabbcc to #abc
    $line =~ s/#([0-9a-f])\1([0-9a-f])\2([0-9a-f])\3/#\L$1$2$3/ig;

    if ($in_css) {    # Type 1 CSS insert
        if ( $line =~ m/"""; }/ ) {    # last line
            $in_css = 0;
            next;
        }
        push( @css, $line );
    }
    elsif ($in_css_2) {                # Type 2 CSS insert
        if ( $line =~ m/^(.*)";$/ ) {    # last line
            $in_css = 0;
            push( @css, $1 );
            next;
        }
        push( @css, $line );
    }
    elsif ( $line =~ m/function Page::print_theme_stylesheet/ ) {

        # Type 1 CSS insert
        $in_css = 1;
    }
    elsif ( $line =~ m/custom_css = "(.*)$/ ) {

        # Type 2 CSS insert
        $in_css_2 = 1;
        push( @css, $1 );
    }
    elsif (/^\.$/) {
        last;
    }
    else {
        next unless $line;
        if ( $line =~ m/^layerinfo / || $line =~ m/ "";/ ) {
            if (m/layerinfo "?name"? = "(.+)"/) {
                $theme_human = $1;
                ( $theme_name = lc($theme_human) ) =~ s/\s//g;
                warn "WARNING: $theme_name contains non-ascii characters"
                    if $theme_name =~ m/[^\x01-\x7f]/;
            }
            push( @dropped, $line );
            next;
        }

        push( @set, $line );
    }
}

####################
# Processing Section
####################

# sort @set lines into categories
my ( @unknown, @presentation, @page, @entries, @modules, @fonts, @images );
foreach (@set) {

    if ( /userlite_interaction_links = / || /_management_links = / || /module.*show/ ) {
        push( @dropped, $_ );
    }
    elsif (/font/) {
        push( @fonts, $_ );
    }
    elsif (/image/) {
        push( @images, $_ );
    }
    elsif (/entry/) {
        push( @entries, $_ );
    }
    elsif (/comment/) {
        push( @entries, $_ );
    }
    elsif (/layout/) {
        push( @presentation, $_ );
    }
    elsif (/module/) {
        push( @modules, $_ );
    }
    elsif (/color/) {
        push( @page, $_ );
    }
    else {
        push( @unknown, $_ );
    }
}

# TODO fix quoting in @font lines
# Font family formatting should be properly capitalised and inner quoting added
# eg
#    input: "arial black, verdana, helvetica, serif"
#    output: "'Arial Black', Verdana, Helvetica, serif";
foreach my $line (@fonts) {
    if ( $line =~ m/_size / || $line =~ m/_units / ) {

        # Nothing - these aren't font names so leave them alone
    }
    else {
        #warn "Processing font line: $line";
        if ( $line =~ m/^set (font_[a-z_]+) = "(.*)";$/ ) {
            my $setting   = $1;
            my @fontnames = split( ", ", $2 );
            foreach (@fontnames) {

                # Unquote it if it's already quoted
                s/^'(.*)'$/$1/;
                s/^"(.*)"$/$1/;

                # Capitalise each word
                # TODO don't capitalize font-family names
                s/ ( (^\w)    #at the beginning of the line
                      |       # or
                     (\s\w)   #preceded by whitespace
                      )/\U$1/xg;

                # Single-quote multi-word font names
                if (m/ /) {
                    $_ = "'" . $_ . "'";
                }
            }
            $line = "set $setting = " . '"' . join( ", ", @fontnames ) . '";' . "\n";

            #warn "Post-processed line: $line";
        }
        else {
            print "ERROR: Font setting line may be malformed - check output thoroughly:\n";
            print ">    " . $line . "\n";
        }
    }
}

####################
# Output section
# - push everything out in new format
####################

my $filename = "temp_themes/$layout_name-$theme_name.s2";
open TMP_FILE, "> $filename" or die "Could not open file $filename. Make sure the directory exists";

# Print theme headers
print TMP_FILE <<"EOT";
#NEWLAYER: $layout_name/$theme_name
layerinfo type = "theme";
layerinfo name = "$theme_human";
layerinfo redist_uniq = "$layout_name/$theme_name";
layerinfo author_name = "$author_name";

set theme_authors = [ { "name" => "$author_name", "type" => "user" } ];
EOT

# print @set lines
sub print_section {
    my ( $name, @lines ) = @_;

    if (@lines) {
        print TMP_FILE<<"EOT";

##===============================
## $name
##===============================

EOT
        foreach (@lines) {
            print TMP_FILE $_;
        }
    }
}

print_section( "Presentation", @presentation );
print_section( "Page",         @page );
print_section( "Entry",        @entries );
print_section( "Module",       @modules );
print_section( "Fonts",        @fonts );
print_section( "Images",       @images );
if (@css) {
    print TMP_FILE "\n";
    print TMP_FILE 'function Page::print_theme_stylesheet() { """' . "\n";
    foreach (@css) {
        print TMP_FILE "    " . $_;
    }
    print TMP_FILE '"""; }' . "\n";
}
print_section( "Unknown - DELETE THIS SECTION after reclassifying lines",            @unknown );
print_section( "Dropped - DELETE THIS SECTION after verifying none of it is needed", @dropped );
print TMP_FILE "\n";
close TMP_FILE;

# Output reminders to screen
print "Parsed theme now saved in file: $filename\n";
print "Be sure to check this for hardcoded font sizes.\n";
print "This new text needs to be put into the existing file named:\n";
print "$ENV{LJHOME}/bin/upgrading/s2layers/$layout_name/theme.s2\n\n";
if (@images) {
    print
"This layout appears to have image(s). Change their url to $layout_name/$theme_name(_imagename, if multiple), rename the image to $theme_name(_imagename), and put in:\n";
    print "$ENV{LJHOME}/htdocs/stc/$layout_name/$theme_name.png\n\n";
}
print "Theme also needs a preview screenshot. Resize to 150x114px and put in:\n";
print "$ENV{LJHOME}/htdocs/img/customize/previews/$layout_name/$theme_name.png\n\n";
print
"(for additional reference on cleaning themes, see http://wiki.dreamwidth.net/notes/Newbie_Guide_for_People_Patching_Styles#Adding_a_New_Color_Theme )\n";

