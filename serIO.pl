#!/usr/local/bin/perl

#Caution: Big mess ahead

use strict;
use warnings;

use IO::Socket;

my (@files, $method, $req, $res, $URI, $pipe);


#$SIG{'INT'} = \&cleanup;
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
	&log("Connected ".$client->peerhost().":".$client->peerport()."\n");
# print HTTP request headers
#	while (($req = <$client>)) {
#		print $req;
#		last if $req =~ /^\r\n$/;
#	}
# get http request - first line
	$req = <$client>;
	&log($client->peerhost()." ".$req);
	$res = &handle_req($req);
	if (-f $res) {
	   	open RES, $res, or die "open: $res: $!"; 
		print $client $_ while (<RES>);
	} else {
		$, = "\n";
		foreach (@$res) {
			print $client $_."\n";
		}
	}
	close $client;
}

#sub cleanup { close $socket; die "Interrupted. Exiting...\n"; }
sub log { 
	my $msg = shift;
	print scalar localtime," ", $msg;
}
#sub getfiles {
#	my $dir = shift; 
#	opendir DIR, $dir or die "open:$!\n";
#	@files = grep { !/^\.(\.)?$/ } readdir DIR;
#	closedir DIR;
#	return @files;
#}
sub handle_req {
	($method, $URI) = split / +/, shift;
	my ($file, $invalid_req);
	if ($method !~ /GET/) {
		$invalid_req = 1;
		$URI = '404.html';
	}
	unless ($invalid_req) {
		$URI =~ s/\/(.*)/$1/;								# strip the first slash
		# TODO: CLEAN UP THIS MESS
		if (!$URI || -d $DOCROOT.$URI) {
			if (-f "$DOCROOT$URI".'index.html') {
				$URI .= 'index.html';
			} else {
			   	&log('dir_index'."\n"); #&build_dirindex($DOCROOT.$URI);
			}
		} else {
			-f $DOCROOT.$URI || &log('404'."\n") && defined($URI = '404.html');
		}
	}
	if (-f $DOCROOT.$URI) {
#	   	open $res, $DOCROOT.$URI or die "open: $DOCROOT$URI : $!"; 
		$res = $DOCROOT.$URI;
	}
	-d $DOCROOT.$URI and $res = &build_dirindex($DOCROOT.$URI);
	&log("Sending $DOCROOT$URI...\n");
	return $res;
}
sub build_dirindex {
	my $dir = shift;
	opendir DIR, $dir or die "open:$!\n";
	@files = grep { !/^\.(\.)?$/ } readdir DIR;
	closedir DIR;
	\@files;
}
