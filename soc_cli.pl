#!/usr/local/bin/perl -l
#

use warnings;
use strict;

use Socket;

my $port = shift || 4321;

socket(SOCKET, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "socket: $!";
connect(SOCKET, sockaddr_in($port, inet_aton('127.0.0.1'))) or die "connect: $!";

while (<SOCKET>) {
	print;
}
close SOCKET;


