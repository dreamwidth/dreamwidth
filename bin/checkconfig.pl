#!/usr/bin/perl
#
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


use strict;
use lib "$ENV{LJHOME}/extlib/lib/perl5";
use Getopt::Long;

my $debs_only = 0;
my ($only_check, $no_check, $opt_nolocal, $opt_cpanm);

my %dochecks;   # these are the ones we'll actually do
my @checks = (  # put these in the order they should be checked in
    "timezone",
    "modules",
    "env",
    "database",
    "secrets",
);
foreach my $check (@checks) { $dochecks{$check} = 1; }

sub usage {
    die "Usage: checkconfig.pl
checkconfig.pl --needed-debs
checkconfig.pl --only=<check> | --no=<check>
checkconfig.pl --cpanm

Checks are:
 " . join(', ', @checks);
}

usage() unless GetOptions(
                          'needed-debs' => \$debs_only,
                          'only=s'      => \$only_check,
                          'no=s'        => \$no_check,
                          'nolocal'     => \$opt_nolocal,
                          'cpanm'       => \$opt_cpanm,
                          );

if ($debs_only) {
    $dochecks{database} = 0;
    $dochecks{timezone} = 0;
    $dochecks{secrets} = 0;
}

usage() if $only_check && $no_check;

%dochecks = ( $only_check => 1)
    if $only_check;

$dochecks{$no_check} = 0
    if $no_check;

my @errors;
my $err = sub {
    return unless @_;
    die "\nProblem:\n" . join('', map { "  * $_\n" } @_);
};

# base packages we need installed
my @packages = ('apache2-mpm-prefork');

# packages we need if we're building from source (using cpanm)
my @cpanm_packages = ('libexpat1-dev', 'g++', 'make', 'libgtop2-dev', 'libgmp3-dev',
        'libxml2-dev');

my %modules = (
    "Date::Parse" => { 'deb' => 'libtimedate-perl' },
    "DateTime" => { 'deb' => 'libdatetime-perl' },
    "DBI" => { 'deb' => 'libdbi-perl', 'system' => 1, },
    "DBD::mysql" => { 'deb' => 'libdbd-mysql-perl', 'system' => 1, },
    "DBD::SQLite" => {
        deb => 'libdbd-sqlite3-perl',
        opt => 'Required for tests',
    },
    "Class::Autouse" => { 'deb' => 'libclass-autouse-perl', },
    "Digest::MD5" => { 'deb' => 'libmd5-perl', },
    "Digest::SHA1" => { 'deb' => 'libdigest-sha1-perl', },
    "Digest::SHA" => { 'deb' =>'libdigest-sha-perl' },
    "Image::Size" => { 'deb' => 'libimage-size-perl', },
    "MIME::Lite" => { 'deb' => 'libmime-lite-perl', },
    "MIME::Words" => { 'deb' => 'libmime-perl', },
    "Compress::Zlib" => { 'deb' => 'libcompress-zlib-perl', },
    "Net::DNS" => { 'deb' => 'libnet-dns-perl', },
    "Template" => { 'deb' => 'libtemplate-perl', },
    "CGI" => { deb => 'libcgi-pm-perl', },
    "Net::OpenID::Server" => {
        opt => 'Required for OpenID server support.'
    },
    "Net::OpenID::Consumer" => {
        opt => 'Required for OpenID consumer support.'
    },
    "Net::OAuth" => {
        #opt => 'Required for OAuth support.' # FIXME: Not optional
    },
    "URI::URL" => { 'deb' => 'liburi-perl' },
    "HTML::Tagset" => { 'deb' => 'libhtml-tagset-perl' },
    "HTML::Parser" => { 'deb' => 'libhtml-parser-perl', },
    "LWP::Simple" => { 'deb' => 'libwww-perl', },
    "LWP::UserAgent" => { 'deb' => 'libwww-perl', },
    "GD" => { 'deb' => 'libgd-gd2-perl', 'system' => 1, },
    "GD::Graph" => {
        'deb' => 'libgd-graph-perl',
        'opt' => 'Required for making graphs for the statistics page.',
        'system' => 1,
    },
    "Mail::Address" => { 'deb' => 'libmailtools-perl', },
    "Proc::ProcessTable" => {
        'deb' => 'libproc-process-perl',
        'opt' => "Better reliability for starting daemons necessary for high-traffic installations.",
    },
    "RPC::XML" => {
        'deb' => 'librpc-xml-perl',
        'opt' => 'Required for outgoing XML-RPC support',
    },
    "XMLRPC::Lite" => {},
    "SOAP::Lite" => {
        'deb' => 'libsoap-lite-perl',
        'opt' => 'Required for XML-RPC support.',
        'ver' => '0.710.8',
    },
    "Unicode::MapUTF8" => { 'deb' => 'libunicode-maputf8-perl', },
    "XML::RSS" => {
        'deb' => 'libxml-rss-perl',
        'opt' => 'Required for retrieving RSS off of other sites (syndication).',
    },
    "XML::Simple" => {
        'deb' => 'libxml-simple-perl',
        'ver' => 2.12,
    },
    "String::CRC32" => {
        'deb' => 'libstring-crc32-perl',
        'opt' => 'Required for palette-altering of PNG files.  Only necessary if you plan to make your own S2 styles that use PNGs, not GIFs.',
    },
    "IO::WrapTie" => { 'deb' => 'libio-stringy-perl' },
    "XML::Atom" => {
        'deb' => 'libxml-atom-perl',
    },
    "Math::BigInt::GMP" => {
        'deb' => 'libmath-bigint-gmp-perl',
        'opt' => 'Aides Crypt::DH so it is not crazy slow.',
    },
    "URI::Fetch" => {
        'deb' => 'liburi-fetch-perl',
        'opt' => 'Required for OpenID support.',
    },
    "Crypt::DH" => {
        'deb' => 'libcrypt-dh-perl',
        'opt' => 'Required for OpenID support.',
    },
    "Unicode::CheckUTF8" => {},
    "Captcha::reCAPTCHA" => {
        'deb' => 'libcaptcha-recaptcha-perl',
    },
    "Digest::HMAC_SHA1" => {
        'deb' => 'libdigest-hmac-perl',
    },
    "Image::Magick" => {
        'deb' => 'perlmagick',
        'opt' => "Required for the userpic factory.",
        'system' => 1,
    },
    "Class::Accessor" => {
        'deb' => 'libclass-accessor-perl',
    },
    "Class::Trigger" => {
        'deb' => 'libclass-trigger-perl',
    },
    "Class::Data::Inheritable" => {
        'deb' => 'libclass-data-inheritable-perl',
    },
    "Data::ObjectDriver" => {
        'deb' => 'libdata-objectdriver-perl',
    },
    "GnuPG::Interface" => {
        'deb' => 'libgnupg-interface-perl',
        'opt' => "Required for email posting.",
    },
    "Mail::GnuPG" => {
        'deb' => 'libmail-gnupg-perl',
        'opt' => "Required for email posting.",
    },
    "GTop" => {},
    "Apache2::RequestRec"   => {
        'deb' => "libapache2-mod-perl2",
        #'opt' => "Required for modperl2",   # FIXME: actually required
        'system' => 1, # don't cpanm this
    },
    "Apache2::Request"      => {
        'deb' => "libapache2-request-perl",
        #'opt' => "Required for Apache2",    # FIXME: actually required
        'system' => 1, # don't cpanm this
    },
    "Test::Most" => {
        deb => "libtest-most-perl",
        opt => "Required for tests",
    },
    "Test::More" => {
        'deb' => "libtest-simple-perl",
        'opt' => "Required for subtest support.",
        'ver' => '0.96',
    },
    "HTML::TokeParser" => {
        'deb' => "libhtml-parser-perl",
        'opt' => "Required for clean-embed.t.",
        'ver' => '3.56',
    },
    "YAML" => { 'deb' => 'libyaml-perl', },
    "Business::CreditCard" => {
        'deb' => "libbusiness-creditcard-perl",
        'opt' => "Required for taking credit/debit cards in the shop.",
    },
    "Hash::MultiValue" => { ver => '0.10' },
    "DateTime::TimeZone" => { 'deb' => "libdatetime-timezone-perl", },
    "Sys::Syscall" => {
        deb => 'libsys-syscall-perl',
        opt => 'Required for Perlbal',
    },
    "Danga::Socket" => {
        deb => 'libdanga-socket-perl',
        opt => 'Required for Perlbal',
    },
    "IO::AIO" => {
        deb => 'libio-aio-perl',
        opt => 'Required for Perlbal',
        },
    "MogileFS::Client" => {
        ver => '1.12',
        opt => 'Used for legacy MogileFS support',
    },
    "TheSchwartz" => {
        deb => 'libtheschwartz-perl',
    },
    "TheSchwartz::Worker::SendEmail" => {},
    "Text::Markdown" => {
        deb => 'libtext-markdown-perl',
        opt => 'Required to allow using Markdown in entries.',
    },
    "Cache::Memcached" => {
        deb => 'libcache-memcached-perl',
    },
    "Gearman::Client" => {
        deb => 'libgearman-client-perl',
    },
    "File::Type" => {
        deb => 'libfile-type-perl',
    },
    "JSON" => {
        deb => 'libjson-perl',
        ver => '2.53',
    },
    "Image::ExifTool" => {
        deb => 'libimage-exiftool-perl',
    },
    "Net::SSL" => { ver => "2.85" },
    "MIME::Base64::URLSafe" => {
        deb => 'libmime-base64-urlsafe-perl',
    },
    "List::MoreUtils" => {},
    "Locale::Country" => { ver => '3.32' },
    "Net::SMTPS" => {},
    "IO::Socket::SSL" => {},
    "LWP::UserAgent::Paranoid" => {},
    "Mozilla::CA" => {},
    "File::Find::Rule" => {
        deb => 'libfile-find-rule-perl',
        opt => "Used by t/00-compile.t test.",
    },
    "Log::Log4perl" => {
        deb => 'liblog-log4perl-perl',
    },
    "Params::Validate" => {
        ver => '1.2',
    },
    "List::Util" => {
        ver => '1.45',
    },
    "Params::Util" => {
        opt => "Used for BlobStore support of S3",
    },
    "Paws::S3" => {
        opt => "Used for BlobStore support of S3",
    },
    "Text::Wrap" => {
        ver => '2013.0523', # issue #1447
    },
    "Moose" => {
        opt => "Used for BlobStore support of S3",
    },
    "Text::Fuzzy" => {
        ver => '0.27',
    }
);


sub check_modules {
    print "[Checking for Perl Modules....]\n"
        unless $debs_only;

    my (@debs, @mods);

    foreach my $mod (sort keys %modules) {
        my $rv = eval "use $mod ();";
        if ($@) {
            my $dt = $modules{$mod};
            unless ($debs_only) {
                if ($dt->{'opt'}) {
                    print STDERR "Missing optional module $mod: $dt->{'opt'}\n";
                } else {
                    push @errors, "Missing perl module: $mod";
                }
            }
            if ($opt_cpanm) {
                push @debs, $dt->{'deb'} if $dt->{'deb'} && $dt->{'system'};
                push @mods, $mod unless $dt->{system};
                die "Cannot use system module: $_" if $dt->{system} and ! $dt->{deb};
            } else {
                push @debs, $dt->{'deb'} if $dt->{'deb'};
            }
            next;
        }

        my $ver_want = $modules{$mod}{ver};
        my $ver_got = $mod->VERSION;

        # handle version strings with multiple decimal points
        # assumes there will never be a version part prepended
        # only appended
        if ( $ver_want && $ver_got ) {
            my @parts_want = split( /\./, $ver_want );
            my @parts_got  = split( /\./, $ver_got  );
            my $invalid = 0;

            while ( scalar @parts_want ) {
                my $want_part = shift @parts_want || 0;
                my $got_part = shift @parts_got || 0;

                # If want_part is greater then got_part, older
                # If got_part is greater then want_part, newer
                # If they are the same, look at the next part pair
                if ( $want_part != $got_part ) {
                    $invalid = $want_part > $got_part ? 1 : 0;
                    last;
                }
            }
            if ( $invalid ) {
                if ( $modules{$mod}->{opt} ) {
                    print STDERR "Out of date optional module: $mod (need $ver_want, $ver_got installed)\n";
                } else {
                    push @errors, "Out of date module: $mod (need $ver_want, $ver_got installed)";
                }
            }
        }
    }
    if (@debs && -e '/etc/debian_version') {
        if ($debs_only) {
            print join(' ', @debs);
        } else {
            print STDERR "\n# apt-get install ", join(' ', @debs), "\n\n";
        }
    }
    if (@mods) {
        print "\n# curl -L http://cpanmin.us | sudo perl - --self-upgrade\n";
        print "# cpanm -L \$LJHOME/extlib/ " . join(' ', @mods) . "\n\n";
    }

    $err->(@errors);
}

sub check_env {
    print "[Checking LJ Environment...]\n"
        unless $debs_only;

    $err->("\$LJHOME environment variable not set.")
        unless $ENV{'LJHOME'};
    $err->("\$LJHOME directory doesn't exist ($ENV{'LJHOME'})")
        unless -d $ENV{'LJHOME'};

    # before config.pl is called, we want to call the site-local checkconfig,
    # otherwise config.pl might load config-local.pl, which could load
    # new modules to implement site-specific hooks.
    my $local_config = "$ENV{'LJHOME'}/bin/checkconfig-local.pl";
    $local_config .= ' --needed-debs' if $debs_only;
    if (!$opt_nolocal && -e $local_config) {
        my $good = eval { require $local_config; };
        exit 1 unless $good;
    }

    eval { require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl"; };
    $err->("Failed to load ljlib.pl: $@") if $@;

    $err->("No config-local.pl file found at etc/config-local.pl")
        unless LJ::resolve_file( 'etc/config-local.pl' );

}

sub check_database {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
    my $dbh = LJ::get_dbh("master");
    unless ($dbh) {
        $err->("Couldn't get master database handle.");
    }
    foreach my $c (@LJ::CLUSTERS) {
        my $dbc = LJ::get_cluster_master($c);
        next if $dbc;
        $err->("Couldn't get db handle for cluster \#$c");
    }
}

foreach my $check (@checks) {
    next unless $dochecks{$check};
    my $cn = "check_".$check;
    no strict 'refs';
    &$cn;
}

unless ($debs_only) {
    print "All good.\n";
    print "NOTE: checkconfig.pl doesn't check everything yet\n";
}

sub check_timezone {
    print "[Checking Timezone...]\n";
    my $rv = eval "use DateTime::TimeZone;";
    if ($@) {
        $err->( "Missing required perl module: DateTime::TimeZone" );
    }

    my $timezone = DateTime::TimeZone->new( name => 'local' );

    $err->( "Timezone must be UTC." ) unless $timezone->is_utc;
}

sub check_secrets {
    print "[Checking Secrets...]\n";

    foreach my $secret ( keys %LJ::Secrets::secret ) {
        my $def = $LJ::Secrets::secret{$secret};
        my $req_len = exists $def->{len} || exists $def->{min_len} || exists $def->{max_len};
        my $rec_len = exists $def->{rec_len} || exists $def->{rec_min_len} || exists $def->{rec_max_len};

        my $req_min = $def->{len} || $def->{min_len} || 0;
        my $req_max = $def->{len} || $def->{max_len} || 0;

        my $rec_min = $def->{rec_len} || $def->{rec_min_len} || 0;
        my $rec_max = $def->{rec_len} || $def->{rec_max_len} || 0;
        my $val = $LJ::SECRETS{$secret} || '';
        my $len = length( $val );

        if ( ! defined( $LJ::SECRETS{$secret} ) || ! $LJ::SECRETS{$secret} ) {
            if ( $def->{required} ) {
                $err->( "Missing requred secret '$secret': $def->{desc}" );
            } else {
                print STDERR "Missing optional secret '$secret': $def->{desc}\n";
            }
        } elsif ( $req_len && ( $len < $req_min || $len > $req_max ) ) {
            if ( $req_min == $req_max ) {
                $err->( "Secret '$secret' not of required length: is $len, must be $req_min" );
            } else {
                $err->( "Secret '$secret' not of required length: is $len, must be between $req_min and $req_max" );
            }
        } elsif ( $rec_len && ( $len < $rec_min || $len > $rec_max ) ) {
            if ( $rec_min == $rec_max ) {
                print STDERR "Secret '$secret' not of recommended length: is $len, should be $rec_min\n";
            } else {
                print STDERR "Secret '$secret' not of recommended length: is $len, should be between $rec_min and $rec_max\n";
            }
        }
    }
}
