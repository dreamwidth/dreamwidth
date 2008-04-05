#!/usr/bin/perl
#

package LJ;

$verbose = 0;
@obs = ();

sub load_objects_from_file
{
    my ($file, $oblist) = @_;

    # hard-code these common (er, only) cases
    if ($file eq "views.dat" || $file eq "vars.dat") {
        $file = "$LJ::HOME/doc/raw/s1/$file";
    }

    open (FIL, $file);
    load_objects(\*FIL, $oblist);
    close FIL;
}

sub load_objects
{
    my ($fh, $oblist) = @_;
    my $l;

    while ($l = <$fh>)
    {
        chomp $l;
        next unless ($l =~ /\S/);
        next if ($l =~ /^\#/);
        if ($l =~ /^\{\s*(\S+)\s*$/)
        {
          &load_object($fh, $1, $oblist);
        }
        else
        {
          print STDERR "Unexpected line: $l\n";
        }
    }
}

sub load_object 
{
    my ($fh, $obname, $listref) = @_;
    my $var = "";
    my $vartype = "";
    my $ob = { name => $obname, props => {} };
    my $l;

    print "Loading object $obname ... \n" if $verbose;
  SUCKLINES:
    while ($l = <$fh>)
    {
        chomp $l;
        if ($l =~ /^\.(\S+)\s*$/)
        {
          $var = $1;
          print "current var = $var\n" if $verbose;
          next SUCKLINES;
        }
        if ($l =~ /^\}\s*$/)
        {
          print "End object $obname.\n" if $verbose;
          last SUCKLINES;
        }
        next unless $var;
        next unless ($l =~ /\S/);
        next if ($l =~ /^\#/);

        if ($l =~ /^\{\s*(\S+)\s*$/)
        {
          print "Encounted object ($1) as property.\n" if $verbose;
          if (defined $ob->{'props'}->{$var})
          {
              if (ref $ob->{'props'}->{$var} ne "ARRAY")
              {
                print STDERR "Object encountered where text expected.\n";
                my $blah = [];
                &load_object($fh, "blah", $blah); # ignore object
              }
              else
              {
                &load_object($fh, $1, $ob->{'props'}->{$var});
              }
          }
          else
          {
              $ob->{'props'}->{$var} = [];
              &load_object($fh, $1, $ob->{'props'}->{$var});
          }
        }
        else
        {
          print "Normal line.\n" if $verbose;
          if (defined $ob->{'props'}->{$var})
          {
              print "defined.\n" if $verbose;
              if (ref $ob->{'props'}->{$var} eq "ARRAY")
              {
                print STDERR "Scalar found where object expected!\n";
              }
              else
              {
                print "appending var \"$var\".\n" if $verbose;
                $ob->{'props'}->{$var} .= "\n$l";
              }
          }
          else
          {
              print "setting $var to $l\n" if $verbose;
              $ob->{'props'}->{$var} = $l;
          }
        }

    } # end while
    print "done loading object $obname\n" if $verbose;

    push @{$listref}, $ob;

} # end sub

sub xlinkify
{
    my ($a) = $_[0];
    $$a =~ s/\[var\[([A-Z0-9\_]{2,})\]\]/<a href=\"\/developer\/varinfo.bml?$1\">$1<\/a>/g;
    $$a =~ s/\[view\[(\S+?)\]\]/<a href=\"\/developer\/views.bml\#$1\">$1<\/a>/g;
}

sub dump_struct
{
    my ($ref, $depth) = @_;
    my $type = ref $ref;
    my $indent = "  "x$depth;
    if ($type eq "ARRAY")
    {
        print "ARRAY\n";
        my $count = 0;
        foreach (@{$ref})
        {
          print $indent, "[$count] = ";
          &dump_struct($_, $depth+1);
          $count++;
        }
    }
    elsif ($type eq "HASH")
    {
        print "HASH\n";
        my $k;
        foreach $k (sort keys %{$ref})
        {
          print $indent, "{$k} = ";
          &dump_struct($ref->{$k}, $depth+1);
        }
    }
    elsif ($type eq "")
    {
        print $ref, "\n";
    }
    else
    {
        print $indent, "UNKNOWN_TYPE";
    }
}

1;
