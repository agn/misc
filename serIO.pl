#!/usr/bin/perl -w

#Caution: Big mess ahead
#TODO: 
#	binmode()
#	http response headers
#	http://perlmonks.org/index.pl?node_id=771769
#	implement Getopt::Long
#	usage() function
#	log to syslog
#	fork() children
#	daemonize 
#	persistent connections

use strict;
use IO::Socket;
use POSIX;


my $DEBUG = 1;
my $DOCROOT = '/home/arun/downloads/';

my (@files, @request, $req, $client, $seen, $uri);

my %error_page = (
	403 => $DOCROOT.'403.html',	# forbidden
	404 => $DOCROOT.'404.html',	# not found
	406 => $DOCROOT.'406.html',	# not acceptable
	501 => $DOCROOT.'501.html'	# not implemented
);

$SIG{'INT'} = \&cleanup;

my $socket = new IO::Socket::INET ( 
	LocalAddr => '172.17.1.50',
	LocalPort => (shift || 4321),
	Proto     => 'tcp',
	Listen    => 5,
	ReuseAddr => 1
) or die "socket(): $! \n";

$socket->listen();
logme("Listening on ".$socket->sockhost().":".$socket->sockport."\n");

while ($client = $socket->accept()) {
	@request = ();
	logme("Connection from ".$client->peerhost().":".$client->peerport()."\n");

	# get http request - first line
	logme("--- HTTP Request ---\n") if $DEBUG;
	while (<$client>) {
		last if /^\r\n$/;
		logme("$_") if $DEBUG;
		push @request, $_ if /./;
	}
	logme("--- END ---\n") if $DEBUG;
	$req = $request[0];
	if (defined $req) {
		logme($client->peerhost()." ".$req);
		respond_to( handle_req($req) );
	}

	close $client;
}

sub cleanup { close $socket; die "Interrupted. Exiting...\n"; }

sub logme {
	my $msg = shift;
	my $ts  = strftime "%b %e %H:%M:%S", localtime;
	print $ts," $0\[$$\]: $msg";
}

sub getfiles {
	my $dir = shift; 
	opendir DIR, $dir or die "open:$!\n";
	# remove . from list of files
	@files = grep { !/^\.$/ } readdir DIR;
	#@files = grep { !/^\.(\.)?$/ } readdir DIR;
	closedir DIR;
	return \@files;
}

sub handle_req {
	(my $method, $uri) = split / +/, shift;

	if ($method !~ /^GET/i) {
		logme("501 Not Implemented\nr");
		return 501;	
	}

	$uri =~ s/\/(.*)/$1/;			# strip the first slash
	sanitize_uri() if defined $uri;
	logme("URI: $uri\n") if $DEBUG;

	if (-e $DOCROOT.$uri) {
		if (-f $DOCROOT.$uri) {
			if (-r $DOCROOT.$uri) {
				logme("200 HTTP OK\n");
				return 200;
			} else {
				logme("403 Forbidden\n");
				return 403;
			}
		} elsif (-d $DOCROOT.$uri) {
			if (-r $DOCROOT.$uri && -x $DOCROOT.$uri) {
				logme("200 HTTP OK\n");
				return 200;
			} else {
				logme("403 Forbidden\n");
				return 403;
			}
		} else {
			logme("406 Not Acceptable\n");
			return 406;
		}
	}
	logme("404 Not Found\n");
	return 404;
}

sub respond_to {
	my $status_code = shift; 
	unless ($status_code == 200) {
		send_file($error_page{$status_code}) if (-f $error_page{$status_code});
		return;
	}

	chomp($uri);
	my $path = $DOCROOT.$uri;
	if (-f $path) {
		send_file($path) ;
		return;
	}
	if (-d $path) {
		if (-f $path.'index.html') {
			send_file($path.'index.html');
		} else {
			send_dir_list($uri, getfiles($path));
		}
	}
	return;
}

sub send_file {
	my $file = shift;
	if (-B $file) {
		open RES, '<', $file or die "open: $file: $!";
		binmode RES, ':raw';
		logme("Sending B $file\n");
	} else {
		open RES, '<', $file or die "open: $file: $!";
		logme("Sending T $file\n");
	}
	print $client $_ while (<RES>);
	close RES;
}

sub send_dir_list {
	my ($uri, $files) = @_;
	logme("[info] dir listing request\n");

	# print html header
	print $client <<HEADER;
	<html>
		<head><title>dir listing for: /$uri</title></head>
		<body>
		<table cellpadding=5>
HEADER

	my $count;
	foreach my $f (@$files) {
		printf $client "%s<td><a href=\"%s\">%s</a></td><td>%s</td></tr>",
				# different colours for alternate rows
				(++$count % 2 ? '<tr bgcolor="#e0ffd6">' : '<tr bgcolor="#ffdcd6">'),
				# genereate href links
			   	(-d $DOCROOT.$uri.'/'.$f ?  '/'.$uri.$f.'/' : '/'.$uri.$f),
				# append a '/' to the end of dirs
			   	(-d $DOCROOT.$uri.'/'.$f ?  $f.'/' : $f),
			  	scalar localtime((stat $DOCROOT.$uri.'/'.$f)[9]);
	}

	#print html footer
	print $client <<FOOTER;
	</table>
	<p>-- httpserv v0.1 --</p>
	</body>
	</html>
FOOTER
}

sub sanitize_uri {
	my @dirs = split /\//, $uri;
	$seen = 0;

	logme("Dirs: @dirs \n") if $DEBUG;

	my $num = grep { $_ eq '..' } @dirs;
	logme("Number of ..: $num\n") if $DEBUG;

	while ($seen < $num) {
		if ( $dirs[0] eq '..' ) { 
			logme("show root\n") if $DEBUG;
			$uri = '';
			return $uri;
		} else {
			logme("Sx: @dirs\n") if $DEBUG;
			reduce_path(\@dirs);
			logme("Rx: @dirs\n") if $DEBUG;
			logme("Seen: $seen\n") if $DEBUG;
		}   
	}
	return join('/', @dirs);
}

sub reduce_path {
    my $dirs = shift;
    for (1..((scalar @$dirs) - 1)) {
        if (@$dirs[$_] eq '..') {
            $seen++;
            splice @$dirs, $_, 1;
            splice @$dirs, ($_ - 1), 1;
            return $dirs;
        }
    }
}
