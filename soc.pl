#!/usr/local/bin/perl 

use warnings;
use strict;

use Socket;


my $port = shift || 4321;
my $proto = getprotobyname('tcp');
socket(SERVER, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
my $addr = sockaddr_in($port, INADDR_ANY);

bind(SERVER, $addr) or die "bind: $!";
listen(SERVER, 5) or die "listen: $!";
print "$$ listening on $port\n";

while (my $client_addr = accept(CLIENT, SERVER)) {
    my ($client_port, $client_ip) = sockaddr_in($client_addr);
    my $client_ipnum = inet_ntoa($client_ip);	# coz $client_ip is packed
    my $client_host = gethostbyaddr($client_ip, AF_INET);
    print "got a connection from: $client_host", "[$client_ipnum]\n";
	print CLIENT "Hello from server";
    close CLIENT;
}
close SERVER;
