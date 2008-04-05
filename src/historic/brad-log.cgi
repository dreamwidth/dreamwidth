#!/usr/bin/perl

use DBI;
$dbh = DBI->connect("DBI:mysql:bradfitz", "bradfi2", "");

&get_form_data;

print "Content-type: text/plain\n\n";

unless ($dbh)
{
	print "ERROR: cannot connect to database.";
	exit;
}

unless ($FORM{'event'})
{
	print "ERROR: no event.";
	exit;
}

unless ($FORM{'password'} eq "mylog")
{
	print "ERROR: incorrect password";
	exit;
}

$qevent = $dbh->quote($FORM{'event'});

$dbh->do("INSERT INTO bradlog (eventtime, type, event) VALUES (UNIX_TIMESTAMP(), 'event', $qevent)");

if ($dbh->err)
{
	print "ERROR: dbh->errstr = ", $dbh->errstr;
	exit;
}

print "Success.";


sub get_form_data 
{
	my $buffer;
	if ($ENV{'REQUEST_METHOD'} eq 'POST') {
	    read(STDIN, $buffer, $ENV{'CONTENT_LENGTH'});
	} else {
		$buffer = $ENV{'QUERY_STRING'};
	}

	# Split the name-value pairs
	my $pair;
	my @pairs = split(/&/, $buffer);
	my ($name, $value);
	foreach $pair (@pairs)
	{
		($name, $value) = split(/=/, $pair);
		$value =~ tr/+/ /;
        $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
        $name =~ tr/+/ /;
        $name =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
       	$FORM{$name} .= $FORM{$name} ? "\0$value" : $value;
    }
}

