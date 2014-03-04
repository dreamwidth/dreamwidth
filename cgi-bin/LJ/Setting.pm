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

package LJ::Setting;
use strict;
use warnings;
use Carp qw(croak);
use LJ::ModuleLoader;

# require all settings
LJ::ModuleLoader->require_subclasses( "LJ::Setting" );
LJ::ModuleLoader->require_subclasses( "DW::Setting" );

# ----------------------------------------------------------------------------

sub should_render { 1 }
sub is_conditional_setting { 0 }
sub disabled { 0 }
sub selected { 0 }
sub label { "" }
sub actionlink { "" }
sub helpurl { "" }
sub option { "" }
sub htmlcontrol { "" }
sub htmlcontrol_label { "" }

sub error_check {
    my ($class, $u, $args) = @_;
    my $val = $class->get_arg($args, "foo");
    #unless ($val =~ /blah/) {
    #   $class->errors("foo" => "Invalid foo");
    #}

    die "No 'error_check' configured for settings module '$class'\n";
}

sub as_html {
    my ($class, $u, $errmap) = @_;
    return "No 'as_html' implemented for $class.";
}

sub save {
    my ($class, $u, $postargs, @classes) = @_;
    if ($class ne __PACKAGE__) {
        die "No 'save' implemented for '$class'\n";
    } else {
        die "No classes given to save\n" unless @classes;
    }

    my %posted;  # class -> key -> value
    while (my ($k, $v) = each %$postargs) {
        my ( $class, $key ) = class_from_key( $k );
        $posted{$class}{$key} = $v;
    }

    foreach my $setclass (@classes) {
        my $args = $posted{$setclass} || {};
        $setclass->save($u, $args);
    }
}

# ----------------------------------------------------------------------------

# Don't override:

# Internal method to do *proper* argument -> class/key mapping.
sub class_from_key {
    my ( $val ) = @_;

    my ( $class, $key ) = $val =~ /^((?:[a-zA-Z0-9]+__)+[a-zA-Z0-9]+)_([\w\[\]]+)$/;
    $class =~ s/__/::/g if $class;

    return ( $class, $key );
}

sub pkgkey {
    my $class = shift;
    $class =~ s/::/__/g;
    return $class . "_";
}

sub errdiv {
    my ($class, $errs, $key) = @_;
    return "" unless $errs;

    # $errs can be a hashref of { $class => LJ::Error::SettingSave::Foo } or a map of
    # { $errfield => $errtxt }.  this converts the former to latter.
    if (my $classerr = $errs->{$class}) {
        $errs = $classerr->field('map');
    }

    my $err = $errs->{$key}   or return "";
    # TODO: red is temporary.  move to css.
    return "<div style='color: red' class='ljinlinesettingerror'>$err</div>";
}

# don't override this.
sub errors {
    my ( $class, %map ) = @_;

    my $errclass = $class;
    $errclass =~ s/^([a-zA-Z0-9]+)::Setting:://;
    $errclass = "$1::Error::SettingSave::" . $errclass;
    eval "\@${errclass}::ISA = ( 'LJ::Error::SettingSave' );";

    my $eo = eval { $errclass->new( map => \%map ) };
    $eo->log;
    $eo->throw;
}

# gets a key out of the $args hash, which can be either \%POST or a class-specific one
sub get_arg {
    my ($class, $args, $which) = @_;
    my $key = $class->pkgkey;
    return $args->{"${key}$which"} || $args->{$which} || "";
}

# called like:
#   LJ::Setting->error_map($u, \%POST, @multiple_setting_classnames)
# or:
#   LJ::Setting::SpecificOption->error_map($u, \%POST)
# returns:
#   undef if no errors found,
#   LJ::SettingErrors object if any errors.
sub error_map {
    my ($class, $u, $post, @classes) = @_;
    if ($class ne __PACKAGE__) {
        croak("Can't call error_map on LJ::Setting subclass with \@classes set.") if @classes;
        @classes = ($class);
    }

    my %errors;
    foreach my $setclass (@classes) {
        my $okay = eval {
            $setclass->error_check($u, $post);
        };
        next if $okay;
        $errors{$setclass} = $@;
    }
    return undef unless %errors;
    return \%errors;
}

# save all of the settings that were changed
# $u: user whose settings we're changing
# $post: reference to %POST hash
# $all_settings: reference to array of all settings that are on this page
# returns any errors and the post args for each setting
sub save_all {
    shift if $_[0] eq __PACKAGE__;
    my ( $u, $post, $all_settings ) = @_;
    my %posted;  # class -> key -> value
    my %returns;

    while ( my ( $k, $v ) = each %$post ) {
        my ( $class, $key ) = class_from_key( $k );
        next unless $class;
        $posted{$class}{$key} = $v;
    }

    foreach my $class (@$all_settings) {
        my $post_args = $posted{$class};
        $post_args ||= {};
        my $save_errors;
        if ($post_args) {
            my $sv = eval {
                $class->save($u, $post_args);
            };
            if (my $err = $@) {
                $save_errors = $err->field('map') if ref $err;
            }
        }

        $returns{$class}{save_errors} = $save_errors;
        $returns{$class}{post_args} = $post_args;
    }

    return \%returns;
}

sub save_had_errors {
    my $class = shift;
    my $save_rv = shift;
    return 0 unless ref $save_rv;

    my @settings = @_; # optional, for specific settings
    @settings = keys %$save_rv unless @settings;

    foreach my $setting (@settings) {
        my $errors = $save_rv->{$setting}->{save_errors} || {};
        return 1 if %$errors;
    }

    return 0;
}

sub errors_from_save {
    my $class = shift;
    my $save_rv = shift;

    return $save_rv->{$class}->{save_errors};
}

sub args_from_save {
    my $class = shift;
    my $save_rv = shift;

    return $save_rv->{$class}->{post_args};
}

sub ml {
    my ($class, $code, $vars) = @_;

    # can pass in a string and check 2 places in order:
    # 1) setting.foo.text => general .setting.foo.text (overridden by current page)
    # 2) setting.foo.text => general setting.foo.text  (defined in en(_LJ).dat)

    # whether passed with or without a ".", eat that immediately
    $code =~ s/^\.//;

    # 1) try with a ., for current page override in 'general' domain
    # 2) try without a ., for global version in 'general' domain
    foreach my $curr_code (".$code", $code) {
        my $string = LJ::Lang::ml($curr_code, $vars);
        return "" if $string eq "_none";
        return $string unless LJ::Lang::is_missing_string($string);
    }

    # return the class name if we didn't find anything
    $class =~ /.+::(\w+)$/;
    return $1;
}

package LJ::Error::SettingSave;
use base 'LJ::Error';

sub user_caused { 1 }
sub fields      { qw(map); }  # key -> english  (keys are LJ::Setting:: subclass-defined)

sub as_string {
    my $self = shift;
    my $map   = $self->field('map');
    return join(", ", map { $_ . '=' . $map->{$_} } sort keys %$map);
}

1;
