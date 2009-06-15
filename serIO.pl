#!/usr/local/bin/perl -w

#Caution: Big mess ahead
#TODO: 
#	get .. working in dir listing
#	implement Getopt::Long
#	usage() function
#	log to syslog
#	daemonize 
#	persistent connections

use strict;
use IO::Socket;

my ($socket, @files, $req, $client);

my $DOCROOT = '/home/arun/site/';
my %error_page = (
	403 => $DOCROOT.'403.html',	# forbidden
	404 => $DOCROOT.'404.html',	# not found
	406 => $DOCROOT.'406.html',	# not acceptable
	501 => $DOCROOT.'501.html'	# not implemented
);

#$SIG{'INT'} = \&cleanup;

$socket = new IO::Socket::INET ( 
	LocalAddr => '172.17.1.50',
	LocalPort => (shift || 4321),
	Proto     => 'tcp',
	Listen    => 5,
	ReuseAddr => 1
) or die "$! \n";

$socket->listen();
&log("Listening on ".$socket->sockhost().":".$socket->sockport."\n");

while ($client = $socket->accept()) {
	&log("Connection from ".$client->peerhost().":".$client->peerport()."\n");

	# get http request - first line
	$req = <$client>;
	&log($client->peerhost()." ".$req);
	&respond_to( &handle_req($req) );

	close $client;
}

sub cleanup { close $socket; die "Interrupted. Exiting...\n"; }
sub log {
	my $msg = shift;
	print scalar localtime," ", $msg;
}
sub getfiles {
	my $dir = shift; 
	opendir DIR, $dir or die "open:$!\n";
	# remove . and .. from list of files
	@files = grep { !/^\.(\.)?$/ } readdir DIR;
	closedir DIR;
	return \@files;
}
sub handle_req {
	my ($method, $uri) = split / +/, shift;

	if ($method !~ /^GET/) {
		&log("501 Not Implemented\nr");
		return 501;	
	}

	$uri =~ s/\/(.*)/$1/;								# strip the first slash

	if (-e $DOCROOT.$uri) {
		if (-f $DOCROOT.$uri) {
			&log("200 HTTP OK\n");
			return 200;
		} elsif (-d $DOCROOT.$uri) {
			&log("200 HTTP OK\n");
			return 200;
		} else {
			&log("406 Not Acceptable\n");
			return 406;
		}
	} else {
		&log("404 Not Found\n");
		return 404;
	}
}
sub respond_to {
	my $status_code = shift; 
	unless ($status_code == 200) {
		&display($error_page{$status_code}) if (-f $error_page{$status_code});
		return;
	}

	my $uri = (split / +/, $req)[1];
	$uri =~ s/\/(.*)/$1/;

	my $path = $DOCROOT.$uri;
	if (-f $path) {
		&display($path) ;
		return;
	}
	if (-d $path) {
		if (-f $path.'index.html') {
			&display($path.'index.html');
		} else {
			&gen_dir_list($uri, &getfiles($path));
		}
	}
}
sub display {
	my $file = shift;
	open RES, $file or die "open: $file: $!";
	&log("Sending $file\n");
	print $client $_ while (<RES>);
	close RES;
}
sub gen_dir_list {
	my ($uri, $files) = @_;
	&log("[info] dir listing request\n");

	# print html header
	print $client <<HEADER;
	<html>
		<head><title>dir listing for: /$uri</title></head>
		<body>
		<table cellpadding=5>
HEADER

	my ($count, $modification_time);
	foreach my $f (@$files) {

		# open $f to get its modification time
		if (-f $DOCROOT.$uri.'/'.$f) {
			open my $handle, $DOCROOT.$uri.'/'.$f or &log("open: $!\n");
			$modification_time = scalar localtime((stat $handle)[9]); 
		} else {
			opendir my $handle, $DOCROOT.$uri.'/'.$f or &log("opendir: $!\n");
			$modification_time = scalar localtime((stat $handle)[9]); 
		}

		printf $client "%s<td><a href=\"%s\">%s</a></td><td>%s</td></tr>",
				# different colours for alternate rows
				(++$count % 2 ? '<tr bgcolor="#e0ffd6">' : '<tr bgcolor="#ffdcd6">'),
				# genereate href links
			   	(-d $DOCROOT.$uri.'/'.$f ?  '/'.$uri.$f.'/' : '/'.$uri.$f),
				# append a '/' to the end of dirs
			   	(-d $DOCROOT.$uri.'/'.$f ?  $f.'/' : $f),
			  	$modification_time;
	}

	#print html footer
	print $client <<FOOTER;
	</table>
	<p>-- httpserv v0.1 --</p>
	</body>
	</html>
FOOTER
}
