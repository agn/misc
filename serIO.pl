#!/usr/local/bin/perl

#Caution: Big mess ahead

use strict;
use warnings;

use IO::Socket;

my (@files, $method, $req, $res, $URI);


#$SIG{'INT'} = \&cleanup;
my $DOCROOT = '/home/arun/site/';

my $socket = new IO::Socket::INET ( 
	LocalAddr => '172.17.1.50',
	LocalPort => (shift || 4321),
	Proto     => 'tcp',
	Listen    => 5,
	ReuseAddr => 1
) or die "$! \n";

$socket->listen();
&log("Listening on ".$socket->sockhost().":".$socket->sockport."\n");

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
		my $path = shift @$res;
		$path =~ s/$DOCROOT(.*)/$1/;
		print $client <<HEADER;
		<html>
			<head><title>dir_index</title></head>
			<body>
			<table cellpadding=5>
HEADER
		my $count;
		foreach my $file (@$res) {
			my $handle;
			if (-f "$DOCROOT$path/$file") {
			   open $handle, "$DOCROOT$path/$file" or &log("open: $!\n");
			} else {
			   opendir $handle, "$DOCROOT$path/$file" or &log("opendir: $!\n");
			}
			printf $client 
				"%s<td><a href=\"%s\">%s</a></td><td>%s</td></tr>",
					# pretty pretty colours
					(++$count % 2 ? '<tr bgcolor="#e0ffd6">' : '<tr bgcolor="#ffdcd6">'),
				   	(-d "$DOCROOT$path/$file" ?  "/$path$file/" : "/$path$file"),
				   	(-d "$DOCROOT$path/$file" ?  $file.'/' : $file),
				  	scalar localtime((stat $handle)[9]); 
			close $handle;
		}
		print $client <<FOOTER;
		</table>
		<p>-- httpserv v0.1 --</p>
		</body>
		</html>
FOOTER
	}
	close $client;
}

#sub cleanup { close $socket; die "Interrupted. Exiting...\n"; }
sub log { 
	my $msg = shift;
	print scalar localtime," ", $msg;
}
sub getfiles {
	my $dir = shift; 
	opendir DIR, $dir or die "open:$!\n";
	@files = grep { !/^\.(\.)?$/ } readdir DIR;
	closedir DIR;
	unshift @files, $dir;
	return \@files;
}
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
			   	&log('[info] dir_index request'."\n"); 
			}
		} else {
			-f $DOCROOT.$URI || &log('404'."\n") && ($URI = '404.html');
		}
	}
	if (-f $DOCROOT.$URI) {
#	   	open $res, $DOCROOT.$URI or die "open: $DOCROOT$URI : $!"; 
		$res = $DOCROOT.$URI;
	}
	-d $DOCROOT.$URI and $res = &getfiles($DOCROOT.$URI);
	&log("Sending $DOCROOT$URI\n");
	return $res;
}
#sub build_dirindex {
#	my $dir = shift;
#	opendir DIR, $dir or die "open:$!\n";
#	@files = grep { !/^\.(\.)?$/ } readdir DIR;
#	closedir DIR;
#	\@files;
#}
