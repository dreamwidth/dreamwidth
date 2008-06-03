#!/usr/bin/perl
#

use strict;

unless (-d $LJ::HOME) {
    die "\$LJHOME not set.\n";
}

use vars qw(%hooks);

my $LJHOME = $LJ::HOME;

require "$LJHOME/doc/raw/build/docbooklib.pl";

$hooks{'canonicalize_url'} = {
    desc => "Cleans up a &url; into its canonical form.",
    args => [
        {
            'desc' => "&url; to be cleaned.",
            'name' => "\$url",
        }
    ],
    source => ["bin/maint/stats.pl"],
};

$hooks{'emailconfirmed'} = {
    desc => "After a user has confirmed their &email; address, this hook is called ".
            "with a dbs/dbh and a user object.  This is useful to update a ".
            "database alias table which you also have your mail system using for ".
            "address lookups.",
    args => [
        {
            'desc' => "Either a dbs or dbh resource object.",
            'name' => "\$dbarg",
        },
        {
            'desc' => "User object.",
            'name' => "\$u",
        },
    ],
    source => ["htdocs/register.bml"],
};

$hooks{'login_formopts'} = {
    desc => "Returns extra &html; for login options on <filename>login.bml</filename>.",
    args => [
        {
            'desc' => "Hash of arguments.",
            'name' => "\%args",
            'keys' => [
                {
                    'desc' => "Scalar return reference.",
                    'name' => "ret",
                },
            ],
        },
    ],
    source => ["htdocs/login.bml"],
};

$hooks{'modify_login_menu'} = {
    desc => "Modifies or resets entirely the web menu data structure that is sent to the client.",
    args => [
        {
            'desc' => "Hash of arguments.",
            'name' => "\%args",
            'keys' => [
                {
                    'desc' => "Menu item.",
                    'name' => "menu",
                },
                {
                    'desc' => "User object.",
                    'name' => "u",
                },
                {
                    'desc' => "Resource object.",
                    'name' => "dbs",
                },
                {
                    'desc' => "Username string.",
                    'name' => "user",
                },
            ],
        },
    ],
    source => ["cgi-bin/ljprotocol.pl"],
};

$hooks{'post_login'} = {
    desc => "Action to take after logging in, before &html; is sent to ".
            "to client (possibly to print &http; headers directly).",
    args => [
        {
            'desc' => "Hash of arguments.",
            'name' => "\%args",
            'keys' => [
                {
                    'desc' => "User object.",
                    'name' => "u",
                },
                {
                    'desc' => "Hash of form elements.",
                    'name' => "form",
                },
                {
                    'desc' => "Used for cookies. Can either be a &unix; timestamp, or '0' for session cookies.",
                    'name' => "expiretime",
                },
            ],
        },
    ],
    source => ["htdocs/login.bml", "htdocs/talkread_do.bml"],
};

$hooks{'post_changepassword'} = {
    desc => "Action to take after changing password, before &html; is sent to ".
            "to client (possibly to print &http; headers directly).",
    args => [
        {
            'desc' => "Hash of arguments.",
            'name' => "\%args",
            'keys' => [
                {
                    'desc' => "User object.",
                    'name' => "u",
                },
                {
                    'desc' => "Resource object.",
                    'name' => "dbs",
                },
                {
                    'desc' => "New password.",
                    'name' => "newpassword",
                },
                {
                    'desc' => "Old password.",
                    'name' => "oldpassword",
                },
            ],
        },
    ],
    source => ["htdocs/changepassword.bml", "ssldocs/changepassword.bml"],
};

$hooks{'post_create'} = {
    desc => "Action to take after creating an account.",
    args => [
        {
            'desc' => "Hash of arguments.",
            'name' => "\%args",
            'keys' => [
                {
                    'desc' => "Resource object.",
                    'name' => "dbs",
                },
                {
                    'desc' => "Username string.",
                    'name' => "user",
                },
                {
                    'desc' => "Integer",
                    'name' => "userid",
                },
                {
                    'desc' => "Auth code, if in use.",
                    'name' => "code",
                },
            ],
        },
    ],
    source => ["cgi-bin/ljlib.pl"],
};

$hooks{'userinfo_html_by_user'} = {
    desc => "Extra &html; to show next to username &amp; id on <filename>userinfo.bml</filename>",
    args => [
        {
            'desc' => "Hash of arguments.",
            'name' => "\%args",
            'keys' => [
                {
                    'desc' => "Scalar return reference.",
                    'name' => "ret",
                },
                {
                    'desc' => "User object.",
                    'name' => "u",
                },
            ],
        },
    ],
    source => ["htdocs/userinfo.bml"],
};

$hooks{'userinfo_rows'} = {
    desc => "Returns a two-element arrayref for a row on a userinfo page, ".
            "containing first the left side label, then the body.",
    args => [
        {
            'desc' => "Hash of arguments.",
            'name' => "\%args",
            'keys' => [
                {
                    'desc' => "Resource Object (read-only).",
                    'name' => "dbr",
                },
                {
                    'desc' => "User object",
                    'name' => "u",
                },
                {
                    'desc' => "Remote user object.",
                    'name' => "remote",
                },
            ],
        },
    ],
    source => ["htdocs/userinfo.bml"],
};

$hooks{'validate_get_remote'} = {
    desc => "This hook lets you ignore the remote user's cookies or flag them ".
            "as intentionally forged to LJ::get_remote().  If you return a ".
            "true value, no action is taken.  If you return false, <function>LJ::get_remote()</function> ".
            "returns undef.  You can optionally set <literal>\$criterr</literal> to something true as well.",
    args => [
        {
            'desc' => "Hash of arguments",
            'name' => "\%args",
            'keys' => [
                {
                    'desc' => "May be an empty string or undef.",
                    'name' => "user",
                },
                {
                    'desc' => "May be 0",
                    'name' => "userid",
                },
                {
                    'desc' => "Resource object",
                    'name' => "dbs",
                },
                {
                    'desc' => "Capabilities.",
                    'name' => "caps",
                },
                {
                    'desc' => "Scalar error reference.",
                    'name' => "criterr",
                },
                {
                    'desc' => "Sub reference which takes a cookie name and returns its value.",
                    'name' => "cookiesource",
                },
            ],
        },
    ],
    source => ["cgi-bin/ljlib.pl"],
};

$hooks{'bad_password'} = {
    desc => "Check the given password, and either return a string explaining why ".
            "the password is bad, or undef if the password is okay.",
    args => [
        {
            'desc' => "Hashref containing at least a password element.  Can also contain a u object and user, name, and &email; elements.",
            'name' => "\$arg",
        },
    ],
    source => ["cgi-bin/ljprotocol.pl","htdocs/changepassword.bml","htdocs/create.bml","htdocs/update.bml", "ssldocs/changepassword.bml"],
};

$hooks{'name_caps'} = {
    desc => "Returns the long name of the given capability bit.",
    args => [
        {
            'desc' => "Capability bit to check.",
            'name' => "\$cap",
        },
    ],
    source => ["cgi-bin/ljlib.pl", "cgi-bin/ljcapabilities.pl"],
};

$hooks{'name_caps_short'} = {
    desc => "Returns the short name of the given capability bit.",
    args => [
        {
            'desc' => "Capability bit to check.",
            'name' => "\$cap",
        },
    ],
    source => ["cgi-bin/ljlib.pl", "cgi-bin/ljcapabilities.pl"],
};

$hooks{'login_add_opts'} = {
    desc => "Appends options to the cookie value.  Each option should be short, and preceded by a period.",
    args => [
        {
            'desc' => "",
            'name' => '%args',
            'keys' => [
                {
                    'desc' => "User object.",
                    'name' => "u",
                },
                {
                    'desc' => "Login form elements.",
                    'name' => "form",
                },
                {
                    'desc' => "Hash reference of options to append to login cookie.",
                    'name' => "opts",
                },
            ],
        },
    ],
    source => ["htdocs/login.bml"],
};

$hooks{'set_s2bml_lang'} = {
    desc => "Given an S2 Context, return the correct &bml; language id.",
    args => [
        {
            'desc' => "S2 Context.",
            'name' => '$ctx',
        },
        {
            'desc' => "Language id reference.",
            'name' => '$langref',
        },
    ],
    source => ["cgi-bin/LJ/S2.pm"],
};

sub hooks
{
    my $hooks = shift;
    my $arg;
    print "<variablelist>\n";
    foreach my $hook (sort keys %$hooks)
    {
        print "  <varlistentry>\n";
        print "    <term><literal role=\"hook\">$hook</literal></term>\n";
        print "    <listitem><formalpara><title>Synopsis:</title><para>\n";
        print "      <funcsynopsis>\n";
        print "        <funcprototype><funcdef><function>$hook</function></funcdef>\n";
        if (@{$hooks->{$hook}->{'args'}})
        {
            print "        <paramdef>\n";
            foreach $arg (@{$hooks->{$hook}->{'args'}})
            {
                print "          <parameter>$arg->{'name'}</parameter>\n";
            }
            print "        </paramdef>\n";
        } else {
            print "        <void/>";
        }
        print "        </funcprototype>\n";
        print "      </funcsynopsis>\n";
        print "      $hooks->{$hook}->{'desc'}\n";
        print "    </para></formalpara>\n";
        if (@{$hooks->{$hook}->{'args'}})
        {
            print "    <formalpara><title>Arguments:</title><para>\n";
            print "      <variablelist>\n";
            foreach $arg (@{$hooks->{$hook}->{'args'}})
            {
                print "        <varlistentry>\n";
                print "          <term><literal>$arg->{'name'}</literal></term>\n";
                print "          <listitem>\n";
                print "          <para>$arg->{'desc'}</para>\n";
                if ($arg->{'keys'})
                {
                    print "          <itemizedlist><title>Keys</title>\n";
                    foreach my $key (@{$arg->{'keys'}})
                    {
                    print "          <listitem><simpara><literal>$key->{'name'}</literal>";
                    print " &mdash; $key->{'desc'}</simpara></listitem>\n";
                    }
                    print "          </itemizedlist>";
                }
                print "          </listitem>\n";
                print "        </varlistentry>\n";
            }
            print "      </variablelist>\n";
            print "    </para></formalpara>\n";
        }
        print "    <formalpara><title>Source:</title>\n";
        print "      <para><itemizedlist>";
        foreach my $i ( 0 .. $#{ $hooks->{$hook}->{'source'} } ) {
            print "<listitem><simpara><filename>";
            print $hooks->{$hook}->{'source'}[$i];
            print "</filename></simpara></listitem>";
        }
        print "    </itemizedlist></para></formalpara>\n";
        print "    </listitem>\n";
        print "  </varlistentry>\n";
    }
    print "</variablelist>\n";
}

hooks(\%hooks);

