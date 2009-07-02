#!/usr/bin/perl -wT

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
use LWP::MediaTypes;


my $DEBUG = 0;
my $DOCROOT = '/home/arun/downloads/';

my (@files, @request, $req, $client, $seen, $uri, $status_code);

my %error = (
	403 => [ 'Forbidden',       $DOCROOT.'403.html'],
	404 => [ 'Not Found',       $DOCROOT.'404.html'],
	406 => [ 'Not Acceptable',  $DOCROOT.'406.html'],
	501 => [ 'Not Implemented', $DOCROOT.'501.html']
);

$SIG{'INT'} = \&cleanup;

my $socket = new IO::Socket::INET ( 
	LocalAddr => '172.17.1.50',
	LocalPort => (shift || 1337),
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
	logme("[debug] --- HTTP Request ---\n") if $DEBUG;
	while (<$client>) {
		last if /^\r\n$/;
		logme("[debug] $_") if $DEBUG;
		push @request, $_;
	}
	logme("[debug] --- END ---\n") if $DEBUG;
	$req = $request[0];
	if (defined $req) {
		logme($client->peerhost()." ".$req);
		handle_req($req);
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
		$status_code = 501;
	} else {
		$uri =~ s/\/(.*)/$1/;			# strip the first slash
		sanitize_uri() if defined $uri;
		logme("[debug] URI: $uri\n") if $DEBUG;

		if (-e $DOCROOT.$uri) {
			if (-f $DOCROOT.$uri) {
				if (-r $DOCROOT.$uri) {
					logme("200 HTTP OK\n");
					$status_code = 200;
				} else {
					logme("403 Forbidden\n");
					$status_code = 403;
				}
			} elsif (-d $DOCROOT.$uri) {
				if (-r $DOCROOT.$uri && -x $DOCROOT.$uri) {
					logme("200 HTTP OK\n");
					$status_code = 200;
				} else {
					logme("403 Forbidden\n");
					$status_code = 403;
				}
			} else {
				logme("406 Not Acceptable\n");
				$status_code = 406;
			}
		} else {
			logme("404 Not Found\n");
			$status_code = 404;
		}
	}

	unless ($status_code == 200) {
		if (-f $error{$status_code}->[1]) {
			send_file($error{$status_code}->[1]);
		} else {
			logme($error{$status_code}->[1]." missing\n");
			send_resp_headers("text/plain");
			print $client $status_code." ".$error{$status_code}->[0];
		}
		return 0;
	}

	chomp($uri);
	my $path = $DOCROOT.$uri;

	if (-f $path) {
		#XXX what if the file isn't redable anymore ?
		send_file($path) ;
	}
	if (-d $path) {
		if (-f $path.'index.html') {
			send_file($path.'index.html');
		} else {
			send_dir_list($uri, getfiles($path));
		}
	}
	return 0;
}

sub send_file {
	my $file = shift;
	my $buffer;
	my $media_type = guess_media_type( $file );

	send_resp_headers( $media_type );

	open RES, '<', $file or die "open: $file: $!";
	if (-B $file) {
		binmode RES;
		binmode $client;
		logme("Sending B $file\n");
		while (my $len = read(RES, $buffer, 256)) { 
			die "read(): $!" unless defined $len;
			print $client $buffer;
		}
	} else {
		logme("Sending T $file\n");
		print $client $_ while (<RES>);
	}
	close RES;
}

sub send_dir_list {
	my ($uri, $files) = @_;
	logme("[info] dir listing request\n");
	send_resp_headers("text/html");

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

	logme("[debug] Dirs: @dirs \n") if $DEBUG;

	my $num = grep { $_ eq '..' } @dirs;
	logme("[debug] Number of ..: $num\n") if $DEBUG;

	while ($seen < $num) {
		if ( $dirs[0] eq '..' ) { 
			logme("[debug] show root\n") if $DEBUG;
			$uri = '';
			return $uri;
		} else {
			logme("[debug] Sx: @dirs\n") if $DEBUG;
			reduce_path(\@dirs);
			logme("[debug] Rx: @dirs\n") if $DEBUG;
			logme("[debug] Seen: $seen\n") if $DEBUG;
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
sub send_resp_headers {
	my $media_type = shift;
	logme("$media_type:$status_code: ".$error{$status_code}->[0]."\n");
	my @response = (
		"HTTP/1.0 $status_code ".$error{$status_code}->[0]."\r\n",
		"Content-Type: $media_type; charset=ISO-8859-4\r\n",
		"\r\n"
	);
	print $client $_ foreach (@response);
	return 0;
}
