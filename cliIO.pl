#!/usr/local/bin/perl -w

use strict;

use IO::Socket;

my $client = new IO::Socket::INET ( 
	Proto => 'tcp',
	PeerAddr => (shift || '172.17.1.50'),
	PeerPort => 80
) or die "$!";
$| = 1;
print $client "GET / HTTP/1.0\n\n";
print while (<$client>);
close $client;
