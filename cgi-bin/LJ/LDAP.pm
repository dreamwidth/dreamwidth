#!/usr/bin/perl
#

package LJ::LDAP;

use strict;
use Net::LDAP;
use Digest::MD5 qw(md5);
use Digest::SHA1 qw(sha1);
use MIME::Base64;

sub load_ldap_user {
    my ($user) = @_;
    return undef unless $user =~ /^[\w ]+$/;

    my $ldap = Net::LDAP->new($LJ::LDAP_HOST)
        or return undef;
    my $mesg = $ldap->bind;    # an anonymous bind

    my $uid = $LJ::LDAP_UID || "uid";

    my $urec = $ldap->search( # perform a search
                              base   => $LJ::LDAP_BASE,
                              scope  => "sub",
                              filter => "$uid=$user",
                              #filter => "(&(sn=Barr) (o=Texas Instruments))"
                              )->pop_entry
                              or return undef;

    my $up = $urec->get_value('userPassword')
        or return undef;

    my ($nick, $email) = ($urec->get_value('gecos'), $urec->get_value('mailLocalAddress'));
    unless ($nick && $email) {
        $@ = "Necessary information not found in LDAP record: name=$nick; email=$email";
        return undef;
    }

    # $res comes out as...?
    my $res = {
        name => $user,
        nick => $nick,
        email => $email,
        ldap_pass => $up,
    };

    return $res;
}

sub is_good_ldap
{
    my ($user, $pass) = @_;
    my $lrec = load_ldap_user($user)
        or return undef;

    # get auth type and data, then decode it
    return undef unless $lrec->{ldap_pass} =~ /^\{(\w+)\}(.+)$/;
    my ($auth, $data) = ($1, decode_base64($2));

    if ($auth eq 'MD5') {
        unless ($data eq md5($pass)) {
            $@ = "Password mismatch (MD5) from LDAP server; is your password correct?";
            return undef;
        }
    } elsif ($auth eq 'SSHA') {
        my $salt = substr($data, 20);
        my $orig = substr($data, 0, 20);
        unless ($orig eq sha1($pass, $salt)) {
            $@ = "Password mismatch (SSHA) from LDAP server; is your password correct?";
            return undef;
        }

    } elsif ($auth eq 'SMD5') {
        # this didn't work
        my $salt = substr($data, 16);
        my $orig = substr($data, 0, 16);
        unless ($orig eq md5($pass, $salt)) {
            $@ = "Password mismatch (SMD5) from LDAP server; is your password correct?";
            return undef;
        }

    } else {
        print STDERR "Unsupported LDAP auth method: $auth\n";
        $@ = "userPassword field from LDAP server not of supported format; type: $auth"
;
        return undef;
    }

    return $lrec;
}


1;

