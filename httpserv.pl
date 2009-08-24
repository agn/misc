#!/usr/bin/perl -w

use strict;

use POSIX;
use IO::Socket;
use LWP::MediaTypes;
use URI::Escape;

my $DEBUG   = 1;
my $DOCROOT = '/home/arun/downloads'; 

my ($uri, $status_code);

my %msgs = (
	200 => [ 'OK'                                     ],
	301 => [ 'Moved Permanently', $DOCROOT.'/301.html'],
	403 => [ 'Forbidden',         $DOCROOT.'/403.html'],
	404 => [ 'Not Found',         $DOCROOT.'/404.html'],
	406 => [ 'Not Acceptable',    $DOCROOT.'/406.html'],
	501 => [ 'Not Implemented',   $DOCROOT.'/501.html']
);

$SIG{'INT'}  = \&cleanup;
$SIG{'CHLD'} = \&reaper;

my $socket = new IO::Socket::INET ( 
	LocalAddr => '127.0.0.1',
	LocalPort => (shift || 4321),
	Proto     => 'tcp',
	Listen    => 5,
	ReuseAddr => 1
) or die "socket(): $@\n";

$socket->listen();
logmsg("Listening on ".$socket->sockhost().":".$socket->sockport."\n");

while (my $client = $socket->accept()) {
	spawn($client);
}

sub spawn { 
	my $client = shift;
	defined (my $pid = fork()) or die "fork(): $!\n";

	unless ($pid) {
		### child ###
		# close the listening socket
		close $socket;
		$| = 1;
		my @request = ();
		logmsg("Connection from ".$client->peerhost().":".$client->peerport()."\n");

		# get http request - first line
		logmsg("[debug] --- HTTP Request ---\n") if $DEBUG;
		while (<$client>) {
			last if /^\r\n$/;
			logmsg("[debug] $_") if $DEBUG;
			push @request, $_;
		}
		logmsg("[debug] --- END ---\n") if $DEBUG;
		my $req = $request[0];
		if (defined $req) {
			logmsg($client->peerhost()." ".$req);
			handle_req($client, $req);
		}
		logmsg("[debug] $$ exiting...\n") if $DEBUG;
		# exit child when request is served
		close($client);
		exit;
	} else {
		close($client);
	}
}

sub cleanup { 
	close $socket;
   	die "Interrupted. Exiting...\n"; 
}

sub reaper {
	my $child;
	do {
		$child = waitpid(-1, 0);
	} while $child > 0;
}

sub logmsg {
	my $msg = shift;
	my $ts  = strftime "%b %e %H:%M:%S", localtime;
	print $ts," $0\[$$\]: $msg";
}

sub getfiles {
	my $dir = shift; 

	opendir DIR, $dir or die "open:$!\n";
	# remove . from list of files
	my @files = grep { !/^\.$/ } readdir DIR;
	closedir DIR;

	return \@files;
}

sub set_status_code {
	(my $method, $uri) = @_;

	$uri ||= '/';		# default if $uri is not defined

	if ($method !~ /^GET/i) {
		logmsg("501 Not Implemented\n");
		$status_code = 501;
	} else {
		logmsg("[debug] URI original: $uri\n") if $DEBUG;
		sanitize_uri() if defined $uri;
		logmsg("[debug] URI: $uri\n") if $DEBUG;

		chomp(my $path = $DOCROOT.$uri);
		if (-e $path) {

			# is a file
			if (-f $path) {
				if (-r $path) {
					logmsg("200 HTTP OK\n");
					$status_code = 200;
				} else {
					logmsg("403 Forbidden\n");
					$status_code = 403;
				}

			# is a directory 
			} elsif (-d $path) {
				if (-r $path && -x $path) {

					# check for / at the end 
					if ($path !~ m/\/$/) {
						logmsg("301 Moved Permanently\n");
						$status_code = 301;
					} else {
						logmsg("200 HTTP OK\n");
						$status_code = 200;
					}

				} else {
					logmsg("403 Forbidden\n");
					$status_code = 403;
				}

			# not a file or directory
			} else {
				logmsg("406 Not Acceptable\n");
				$status_code = 406;
			}

		# doesn't exist
		} else {
			logmsg("404 Not Found\n");
			$status_code = 404;
		}
	}
	return 0;
}

sub handle_req {
	my $client = shift;
	(my $method, $uri) = split / +/, shift;

	set_status_code($method, $uri);

	unless ($status_code == 200) {
		if (-f $msgs{$status_code}->[1]) {
			send_file($msgs{$status_code}->[1]);
		} else {
			logmsg($msgs{$status_code}->[1]." missing\n");
			send_resp_headers($client, "text/plain", 
				length($status_code." ".$msgs{$status_code}->[0]));
			print $client $status_code." ".$msgs{$status_code}->[0]."\r\n";
		}
		return 0;
	}

	my $path = $DOCROOT.$uri;
	logmsg("\$path: $path\n");

	if (-f $path) {
		#XXX what if the file isn't readable anymore ?
		send_file($client, $path) ;
	}

	if (-d $path) {
		if (-f $path.'index.html') {
			send_file($client, $path.'index.html');
		} else {
			send_dir_list($client, $uri, getfiles($path));
		}
	}

	return 0;
}

sub send_file {
	my ($client, $file) = @_;
	my $media_type      = guess_media_type( $file );
	my $size            = -s $file;
	my $buffer;

	send_resp_headers($client, $media_type, $size);

	open RES, '<', $file or die "open: $file: $!";
	if (-B $file) {
		binmode RES;
		binmode $client;
		logmsg("[debug] setting binmode on socket\n") if $DEBUG;
	}
	logmsg("Sending $file\n\n");
	while (my $len = read(RES, $buffer, 4096)) { 
		die "read(): $!" unless defined $len;
		if ($len != 0 && $client->connected()) {
			print $client $buffer;
		} else {
			last;
		}
	}
	close RES;
}

sub send_dir_list {
	my ($client, $uri, $files) = @_;
	logmsg("[info] dir listing request\n");
	send_resp_headers($client, "text/html");

	# print html header
	print $client <<HEADER;
	<html>
		<head><title>dir listing for: $uri</title></head>
		<body>
		<table cellpadding=5>
HEADER

	my $count;
	foreach my $f (sort @$files) {
		printf $client "%s<td><a href=\"%s\">%s</a></td><td>%s</td></tr>",

				# different colours for alternate rows
				(++$count % 2 
					? '<tr bgcolor="#cfcfcf">'
					: '<tr bgcolor="#dddddd">'
				),

				# generate href links
				(-d $DOCROOT.$uri.'/'.$f 
					? $uri.uri_escape($f).'/'
					: $uri.uri_escape($f)
				),

				# append a '/' to the end of dirs
			   	(-d $DOCROOT.$uri.'/'.$f 
					?  $f.'/'
					: $f
				),
			  	strftime "%d-%b-%Y %H:%S", localtime((stat $DOCROOT.$uri.'/'.$f)[9]);
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
	# strip GET variables
	$uri =~ s/([^\?]*).*/$1/;

	# decode URI
	$uri = uri_unescape($uri);

	my @dirs = split /\//, $uri;
	my $seen = 0;

	logmsg("[debug] Dirs: @dirs \n") if $DEBUG;

	my $num = grep { $_ eq '..' } @dirs;
	logmsg("[debug] Number of ..: $num\n") if $DEBUG;

	while ($seen < $num) {
		if ( $dirs[0] eq '..' ) { 
			logmsg("[debug] send $DOCROOT\n") if $DEBUG;
			$uri = '/';
			return 0;
		} else {
			logmsg("[debug] Tx: @dirs\n") if $DEBUG;
			$seen = reduce_path(\@dirs, $seen);
			logmsg("[debug] Rx: @dirs\n") if $DEBUG;
			logmsg("[debug] Seen: $seen\n") if $DEBUG;
		}   
	}
	return 0;
}

sub reduce_path {
    my ($dirs, $seen) = @_;
    for (1..((scalar @$dirs) - 1)) {
        if (@$dirs[$_] eq '..') {
            $seen++;
			# remove .. and parent dir if $_ is ..
            splice @$dirs, $_, 1;
            splice @$dirs, ($_ - 1), 1;
            return $seen;
        }
    }
}

sub send_resp_headers {
	my ($client, $media_type, $content_length) = @_;

	# HTTP uses GMT 
	my $date = strftime "%a, %d %b %Y %H:%M:%S GMT", gmtime();

	my @response = (
			"HTTP/1.1 $status_code ".$msgs{$status_code}->[0]."\r\n",
			"Date: $date\r\n"
		);

	if ($content_length) {
		logmsg("[debug] $media_type:$content_length:".$msgs{$status_code}->[0]."\n") if $DEBUG;
		push @response, (
			"Content-Length: $content_length\r\n"
		);
	} else {
		logmsg("[debug] $media_type:".$msgs{$status_code}->[0]."\n") if $DEBUG;
	}

	# pass Location with / appended to $uri
	if ($status_code == 301) {
		push @response, (
			'Location: http://'.inet_ntoa($socket->sockaddr()).':'.$socket->sockport()."${uri}/\r\n"
		);
	}

	push @response, (
		"Content-Type: $media_type; charset=iso-8859-1\r\n",
		"Connection: close\r\n",
		"\r\n"
	);

	logmsg("[debug] --- HTTP Response ---\n") if $DEBUG;

	# send http response headers
	foreach (@response) {
		logmsg("[debug] $_") if $DEBUG;
		print $client $_;
	}
	logmsg("[debug] --- END ---\n") if $DEBUG;

	return 0;
}
