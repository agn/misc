#!/usr/local/bin/perl -w

use strict;
use IO::Socket;

my (@files, $req, $res);

$SIG{'INT'} = \&cleanup;
my $DOCROOT = '/home/arun/site/';

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
# print HTTP request headers
#	while (($req = <$client>)) {
#		print $req;
#		last if $req =~ /^\r\n$/;
#	}
	#get http request - first line
	$req = <$client>;
	print scalar localtime," - ", $client->peerhost()," - ", $req;
	$res = &handle_req($req);
	print $client $_ while (<$res>);
	close $client;
}

sub cleanup { close $socket; die "Interrupted. Exiting...\n"; }
#sub getfiles {
#	my $dir = shift; 
#	opendir DIR, $dir or die "open:$!\n";
#	@files = grep { !/^\.(\.)?$/ } readdir DIR;
#	closedir DIR;
#	return @files;
#}
sub handle_req {
	my ($method, $URI) = split / +/, shift;
	my ($file, $invalid_req);
	if ($method !~ /GET/) {
		$invalid_req = 1;
		$file = '404.html';
	}
	unless ($invalid_req) {
		$URI =~ s/\/(.*)/$1/;				# strip the first slash
		$file = $URI || 'index.html';
		-f $DOCROOT.$file or $file = '404.html';
	}
	open $res, $DOCROOT.$file or die "open: $!";
	print "Sending $file...\n";
	return $res;
}
