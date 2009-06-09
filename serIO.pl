#!/usr/local/bin/perl -w

use strict;
use IO::Socket;

my @files;

$SIG{'INT'} = \&cleanup;

my $socket = new IO::Socket::INET ( 
	LocalAddr => '172.17.1.50',
	LocalPort => (shift || 4321),
	Proto => 'tcp',
	Listen => 5,
	ReuseAddr => 1
) or die "$! \n";

$socket->listen();
print 'Listening on ', $socket->sockhost(),":", $socket->sockport, "\n";

while (my $client = $socket->accept()) {
	print 'Connected ', $client->peerhost(),":", $client->peerport(), "\n";
	print $client scalar localtime,"\n";
	$, = "\n";
	print $client &getfiles(shift || '.'), "\n";

	close $client;
}

sub cleanup { close $socket; die "Interrupted. Exiting...\n"; }
sub getfiles {
	my $dir = shift; 
	opendir DIR, $dir or die "open:$!\n";
	@files = grep { !/^\.(\.)?$/ } readdir DIR;
	closedir DIR;
	return @files;
}
