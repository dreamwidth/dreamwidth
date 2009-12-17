#!/usr/bin/perl
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
use vars qw(%maint %maintinfo);

use LJ::Captcha::Generate;

use LJ::Blob    qw{};
use File::Temp  qw{tempdir};
use File::Path  qw{rmtree};
use File::Spec  qw{};

our ( $FakeUserId, $ClusterId, $Digits, $DigitCount,
      $ExpireThresUser, $ExpireThresNoUser, $TmpRoot );

# Data for code-generation
$Digits = "abcdefghknpqrstuvxz23456789";
$DigitCount = length( $Digits );

# Maximum age of answered captchas.  this is just
# for double-click protection.
$ExpireThresUser   = 2 * 60;   # two minutes

# 24 hours for captchas which were given out but not answered.
# (they might leave their browser window open or something)
$ExpireThresNoUser = 24 * 3600;  # 1 day

# parent directory under which temporary files and directories
# should be created... anything placed in this directory will
# be automatically cleaned
$TmpRoot = "/tmp";

#####################################################################
### F U N C T I O N S
#####################################################################

### Read a file in as a scalar and return it
sub readfile ($) {
    my ( $filename ) = @_;
    open my $fh, "<$filename" or die "open: $filename: $!";
    local $/ = undef;
    my $data = <$fh>;

    return $data;
}

### Generate an n-character challenge code
sub gencode ($) {
    my ( $digits ) = @_;
    my $code = '';
    for ( 1..$digits ) {
        $code .= substr( $Digits, int(rand($DigitCount)), 1 );
    }

    return $code;
}



#####################################################################
### M A I N T E N A N C E   T A S K S
#####################################################################
$maintinfo{gen_audio_captchas}{opts}{locking} = "per_host";
$maint{gen_audio_captchas} = sub {
    my (
        $u,                     # Fake user record for Blob::put
        $dbh,                   # Database handle (writer)
        $count,                 # Count of currently-extant audio challenges
        $need,                  # How many we need to still create
        $make,                  # how many we're actually going to create this round
        $tmpdir,                # Temporary working directory
        $code,                  # The generated challenge code
        $wav,                   # Wav file
        $data,                  # Wav file data
        $err,                   # Error-message ref for Blob::put calls
        $capid,                 # Captcha row id
        $anum,                  # Deseries-ifier value
       );

    print "-I- Generating new audio captchas...\n";

    # fail if we're not doing uploads right now
    die "Unable to generate captchas: media uploads disabled.\n"
        if $LJ::DISABLE_MEDIA_UPLOADS;

    $dbh = LJ::get_dbh({raw=>1}, "master") or die "Failed to get_db_writer()";
    $dbh->do("SET wait_timeout=28800");

    # Count how many challenges there are currently
    $count = $dbh->selectrow_array(q{
        SELECT COUNT(*)
        FROM captchas
        WHERE
            type = 'audio'
            AND issuetime = 0
    });


    my $MaxItems = $LJ::CAPTCHA_AUDIO_PREGEN || 500;

    # If there are enough, don't generate any more
    print "Current count is $count of $MaxItems...";
    if ( $count >= $MaxItems ) {
        print "already have enough.\n";
        return;
    } else {
        $make = $need = $MaxItems - $count;
        $make = $LJ::CAPTCHA_AUDIO_MAKE
            if defined $LJ::CAPTCHA_AUDIO_MAKE && $make > $LJ::CAPTCHA_AUDIO_MAKE;
        print "generating $make new audio challenges.\n";
    }

    # Clean up any old audio directories lying about from failed generations
    # before. In theory, File::Temp::tempdir() is supposed to clean them up
    # itself, but it doesn't appear to be doing so.
    foreach my $olddir ( glob "$TmpRoot/audio_captchas_*" ) {

        # If it's been more than an hour since it's been changed from the
        # starting time of the script, kill it
        if ( (-M $olddir) * 24 > 1 ) {
            print "cleaning up old working temp directory ($olddir).\n";
            rmtree( $olddir ) or die "rmtree: $olddir: $!";
        }
    }

    # Load the system user for Blob::put() and create an auto-cleaning temp
    # directory for audio generation
    $u = LJ::load_user( "system" )
        or die "Couldn't load the system user.";
    $tmpdir = tempdir( "audio_captchas_XXXXXX", CLEANUP => 0, DIR => $TmpRoot );

    # target location
    my $location = $LJ::CAPTCHA_MOGILEFS ? 'mogile' : 'blob';

    # Generate the challenges
    for ( my $i = 0; $i < $make; $i++ ) {
        print "Generating audio $i...";
        ( $wav, $code ) = LJ::Captcha::Generate->generate_audio( $tmpdir );
        $data = readfile( $wav );
        unlink $wav or die "unlink: $wav: $!";

        # Generate the capid + anum
        print "generating new capid/anum...";
        $capid = LJ::alloc_global_counter( 'C' );
        die "Couldn't allocate capid" unless $capid;
        $anum = int( rand 65_535 );

        # Insert the blob
        print "uploading (capid = $capid, anum = $anum)...";
        if ($location eq 'mogile') {
            my $mogfs = LJ::mogclient(); # force load
            die "Requested to store captchas on MogileFS, but it's not loaded.\n"
                unless $mogfs;
            my $fh = $mogfs->new_file("captcha:$capid", 'captcha')
                or die("Unable to contact MogileFS server for storage: " .
                       $mogfs->last_tracker . ": ".
                       $mogfs->errstr . "\n");

            $fh->print($data);
            $fh->close
                or die "Unable to save captcha to MogileFS server: $@\n";
        } else {
            LJ::Blob::put( $u, 'captcha_audio', 'wav', $capid, $data, \$err )
                  or die "Error uploading to media server: $err";
        }

        # Insert the captcha into the DB. If it fails for some reason, delete
        # the just-uploaded file from the media storage system too.
        print "inserting (code = $code)...";
        my $rval = eval {
            $dbh->do(q{
                INSERT INTO captchas( capid, type, location, answer, anum )
                VALUES ( ?, 'audio', ?, ?, ? )
            }, undef, $capid, $location, $code, $anum);
        };
        if ( !$rval || $@ ) {
            my $err = $@ || $dbh->errstr;
            if ( $location eq 'mogile' ) {
                LJ::mogclient()->delete( "captcha:$capid" );
            } else {
                LJ::Blob::delete( $u, 'captcha_audio', 'wav', $capid );
            }
            die "audio captcha insert error on ($capid, $location, $code, $anum): $err";
        }

        print "done.\n";
    }

    print "cleaning up working temporary directory ($tmpdir).\n";
    rmtree( $tmpdir ) or die "Failed directory cleanup: $!";

    print "done. Created $make new audio captchas.\n";
    return 1;
};

$maintinfo{gen_image_captchas}{opts}{locking} = "per_host";
$maint{gen_image_captchas} = sub {
    my (
        $u,                     # Fake user record for Blob::put
        $dbh,                   # Database handle (writer)
        $count,                 # Count of currently-extant audio challenges
        $need,                  # How many we need to still create
        $code,                  # The generated challenge code
        $png,                   # PNG data
        $err,                   # Error-message ref for Blob::put calls
        $capid,                 # Captcha row id
        $anum,                  # Deseries-ifier value
       );

    print "-I- Generating new image captchas...\n";

    # fail if we're not doing uploads right now
    die "Unable to generate captchas: media uploads disabled.\n"
        if $LJ::DISABLE_MEDIA_UPLOADS;

    $dbh = LJ::get_dbh({raw=>1}, "master") or die "Failed to get_db_writer()";
    $dbh->do("SET wait_timeout=28800");

    # Count how many challenges there are currently
    $count = $dbh->selectrow_array(q{
        SELECT COUNT(*)
        FROM captchas
        WHERE
            type = 'image'
            AND issuetime = 0
    });

    my $MaxItems = $LJ::CAPTCHA_IMAGE_PREGEN || 1000;

    # If there are enough, don't generate any more
    print "Current count is $count of $MaxItems...";
    if ( $count >= $MaxItems ) {
        print "already have enough.\n";
        return;
    } else {
        $need = $MaxItems - $count;
        print "generating $need new image challenges.\n";
    }

    # Load system user for Blob::put()
    $u = LJ::load_user( "system" )
        or die "Couldn't load the system user.";

    $dbh = LJ::get_db_writer() or die "Failed to get_db_writer()";

    # target location
    my $location = $LJ::CAPTCHA_MOGILEFS ? 'mogile' : 'blob';

    # Generate the challenges
    for ( my $i = 0; $i < $need; $i++ ) {
        print "Generating image $i...";
        $code = gencode( 7 );
        ( $png ) = LJ::Captcha::Generate->generate_visual( $code );

        # Generate the capid + anum
        print "generating new capid/anum...";
        $capid = LJ::alloc_global_counter( 'C' );
        die "Couldn't allocate capid" unless $capid;
        $anum = int( rand 65_535 );

        # Insert the blob
        print "uploading (capid = $capid, anum = $anum)...";
        if ($location eq 'mogile') {
            my $mogfs = LJ::mogclient(); # force load
            die "Requested to store captchas on MogileFS, but it's not loaded.\n"
                unless $mogfs;
            my $fh = $mogfs->new_file("captcha:$capid", 'captcha')
                or die("Unable to contact MogileFS server for storage: " .
                       $mogfs->last_tracker . ": ".
                       $mogfs->errstr . "\n");

            $fh->print($png);
            $fh->close
                or die "Unable to save captcha to MogileFS server: $@\n";
        } else {
            LJ::Blob::put( $u, 'captcha_image', 'png', $capid, $png, \$err )
                  or die "Error uploading to media server: $err";
        }

        # Insert the captcha into the DB. If it fails for some reason, delete
        # the just-uploaded file from the media storage system too.
        print "inserting (code = $code)...";
        my $rval = eval {
            $dbh->do(q{
                INSERT INTO captchas( capid, type, location, answer, anum )
                VALUES ( ?, 'image', ?, ?, ? )
            }, undef, $capid, $location, $code, $anum);
        };
        if ( !$rval || $@ ) {
            my $err = $@ || $dbh->errstr;
            if ( $location eq 'mogile' ) {
                LJ::mogclient()->delete( "captcha:$capid" );
            } else {
                LJ::Blob::delete( $u, 'captcha_image', 'png', $capid );
            }
            die "image captcha insert error on ($capid, $location, $code, $anum): $err";
        }

        print "done.\n";
    }

    print "done. Created $need new image captchas.\n";
    return 1;
};

$maint{clean_captchas} = sub {
    my (
        $u,                     # System user
        $expired,               # arrayref of arrayrefs of expired captchas
        $dbh,                   # Database handle (writer)
        $sql,                   # SQL statement
        $sth,                   # Statement handle
        $count,                 # Deletion count
        $err,                   # Error message reference for Blob::delete calls
       );

    print "-I- Cleaning captchas.\n";

    # fail if we're not doing uploads right now
    die "Unable to clean captchas: media uploads disabled.\n"
        if $LJ::DISABLE_MEDIA_UPLOADS;

    # Find captchas to delete
    $sql = q{
        SELECT
            capid, type, location
        FROM captchas
        WHERE
        ( issuetime <> 0 AND issuetime < ? )
        OR
            ( userid > 0
          AND ( issuetime <> 0 AND issuetime < ? )
          )
        LIMIT 2500
    };
    $dbh = LJ::get_db_writer()
        or die "No master DB handle";
    $expired = $dbh->selectall_arrayref( $sql, undef,
                     time() - $ExpireThresNoUser,
                     time() - $ExpireThresUser );
    die "selectall_arrayref: $sql: ", $dbh->errstr if $dbh->err;

    if ( @$expired ) {
        print "found ", scalar @$expired, " captchas to delete...\n";
    } else {
        print "Done: No captchas to delete.\n";
        return;
    }

    # Prepare deletion statement
    $sql = q{ DELETE FROM captchas WHERE capid = ? };
    $sth = $dbh->prepare( $sql );

    # Fetch system user
    $u = LJ::load_user( "system" )
        or die "Couldn't load the system user.";

    # Now delete each one from the DB and the media server
    foreach my $captcha ( @$expired ) {
        my ( $capid, $type, $location ) = @$captcha;
        $location ||= 'blob';
        print "Deleting captcha $capid ($type, $location)\n";
        my $ext = $type eq 'audio' ? 'wav' : 'png';

        if ($location eq 'mogile') {
            my $mogfs = LJ::mogclient(); # force load
            die "Requested to delete captchas from MogileFS, but it's not loaded.\n"
                unless $mogfs;
            $mogfs->delete("captcha:$capid")
                or die "Unable to delete captcha from MogileFS server for capid = $capid.\n";
        } else {
            LJ::Blob::delete( $u, "captcha_$type", $ext, $capid, \$err )
                  or die "Failed to delete $type file from media server for ".
                      "capid = $capid: $err";
        }
        $sth->execute( $capid )
            or die "execute: $sql ($capid): ", $sth->errstr;
        $count++;
    }

    print "Done: deleted $count expired captchas.\n";
    return 1;
};

