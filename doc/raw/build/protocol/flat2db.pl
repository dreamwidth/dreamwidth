#!/usr/bin/perl
#

 use strict;

$LJ::HOME = $ENV{'LJHOME'};

 unless (-d $LJ::HOME) { die "\$LJHOME not set.\n"; }

 require "$LJ::HOME/doc/raw/build/docbooklib.pl";
 require "$LJ::HOME/cgi-bin/propparse.pl";

 my @vars;
 LJ::load_objects_from_file("$LJ::HOME/htdocs/protocol.dat", \@vars);

 foreach my $mode (sort { $a->{'name'} cmp $b->{'name'} } @vars)
 {
     my $name = $mode->{'name'};
     my $des = $mode->{'props'}->{'des'};
     cleanse(\$des);

     unshift (@{$mode->{'props'}->{'request'}},
              { 'name' => "mode", 'props' => { 'des' => "The protocol request mode: <tt>$name</tt>", } },
              { 'name' => "user", 'props' => { 'des' => "Username.  Leading and trailing whitespace is ignored, as is case.", } },
              { 'name' => "auth_method", 'props' => { 'des' => "The authentication method used for this request. Default is 'clear', for plain-text authentication. 'cookie' or any of the challenge-response methods are also acceptable.", } },
              { 'name' => "password", 'props' => { 'des' => "<strong>Deprecated</strong>. Password in plain-text. For the default authentication method, either this needs to be sent, or <tt>hpassword</tt>.", } },
              { 'name' => "hpassword", 'props' => { 'des' => "<strong>Deprecated</strong>. Alternative to plain-text <tt>password</tt>.  Password as an MD5 hex digest.  Not perfectly secure, but defeats the most simple of network sniffers.", } },
              { 'name' => "auth_challenge", 'props' => { 'des' => "If using challenge-response authentication, this should be the challenge that was generated for your client.", } },
              { 'name' => "auth_response", 'props' => { 'des' => "If using challenge-response authentication, this should be the response hash you generate based on the challenge's formula.", } },
              { 'name' => "ver", 'props' => { 'des' => "Protocol version supported by the client; assumed to be 0 if not specified.  See [special[cspversion]] for details on the protocol version.", 'optional' => 1, } },
              ) unless $name eq "getchallenge";
     unshift (@{$mode->{'props'}->{'response'}},
              { 'name' => "success", 'props' => { 'des' => "<b><tt>OK</tt></b> on success or <b><tt>FAIL</tt></b> when there's an error.  When there's an error, see <tt>errmsg</tt> for the error text.  The absence of this variable should also be considered an error.", } },
              { 'name' => "errmsg", 'props' => { 'des' => "The error message if <tt>success</tt> was <tt>FAIL</tt>, not present if <tt>OK</tt>.  If the success variable is not present, this variable most likely will not be either (in the case of a server error), and clients should just report \"Server Error, try again later.\".", } },
              );
     print "<refentry id=\"ljp.csp.flat.$name\">\n";
     print "  <refnamediv>\n    <refname>$name</refname>\n";
     print "    <refpurpose>$des</refpurpose>\n  </refnamediv>\n";

     print "  <refsect1>\n    <title>Mode Description</title>\n";
     print "    <para>$des</para>\n  </refsect1>\n";
     foreach my $rr (qw(request response))
     {
         print "<refsect1>\n";
         my $title = $rr eq "request" ? "Arguments" : "Return Values";
         print "  <title>$title</title>\n";
         print "  <variablelist>\n";
         foreach (@{$mode->{'props'}->{$rr}})
         {
             print "    <varlistentry>\n";
             cleanse(\$_->{'name'});
             print "      <term><literal>$_->{'name'}</literal></term>\n";
             print "      <listitem><para>\n";
             if ($_->{'props'}->{'optional'}) {
                 print "<emphasis>(Optional)</emphasis>\n";
             }
             cleanse(\$_->{'props'}->{'des'});
             print "$_->{'props'}->{'des'}\n";
             print "      </para></listitem>\n";
             print "    </varlistentry>\n";
         }
         print "  </variablelist>\n";
         print "</refsect1>\n";
     }
     print "</refentry>\n";
 }

