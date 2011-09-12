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

package LJ::Setting::MailEncoding;
use base 'LJ::Setting';
use strict;
use warnings;

sub as_html {
    my ($class, $u, $errs) = @_;
    my $key = $class->pkgkey;
    local $BML::ML_SCOPE = "/editinfo.bml";
    my %mail_encnames;
    LJ::load_codes({ "encname" => \%mail_encnames } );

    my $ret = "<?h2 $BML::ML{'.translatemailto.header'} h2?>\n";
    $ret .= LJ::html_select({ 'name' => "${key}mailencoding",
                              'selected' => $u->prop('mailencoding')},
                              map { $_, $mail_encnames{$_} } sort keys %mail_encnames);
    $ret .= "<br />\n$BML::ML{'.translatemailto.about'}";
    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;
    my $val = $args->{'mailencoding'};

    my %mail_encnames;
    LJ::load_codes({ "encname" => \%mail_encnames } );
    $class->errors(oldenc => "Invalid") unless ! $val || $mail_encnames{$val};

    return 1 if $val eq $u->prop('mailencoding');
    return 0 unless $u->set_prop('mailencoding', $val);
    return 1;
}

1;



