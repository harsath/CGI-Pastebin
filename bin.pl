#!/bin/perl
use warnings;
use strict;
use constant BIN_DUMP_PATH => "/tmp/dump_bin";
use constant SERVER_HOSTNAME => "cname.mydomain.tld";
use constant CGI_LOCATION => "cgi-gateway";
use constant LOG_DUMP_PATH => "/var/log/cgi_bin_log";
use Digest::MD5 qw/md5_base64/;
use File::Basename;

my $request_method = $ENV{REQUEST_METHOD};
my $file_content_length = $ENV{CONTENT_LENGTH};
my $client_ip = $ENV{REMOTE_ADDR};
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime(time);
my $bin_auth_header = "HTTP_X_BIN_AUTH";
my $bin_auth_value = "Secure Password";
my @http_response_headers = (
        "Content-Type: text/plain"
);
my $script_name = basename($0);
my $http_response_body = "";
my @error_responses = <DATA>;
my $http_id_error_msg = "";
my $http_auth_error_msg = "";
my $http_unknown_error_msg = "";
my $log_message = "$client_ip - [$hour:$min:$sec | $mday:$wday:$year] $request_method ";

unless(-d BIN_DUMP_PATH){ mkdir(BIN_DUMP_PATH); }

_populate_error_msg();

if($request_method eq "GET"){
        http_get_processor();
}elsif($request_method eq "POST"){
        http_post_processor();
}else{
        http_error_handler("UNKNOWN");
}

http_responder();

sub http_post_processor {
        unless(exists $ENV{$bin_auth_header}){
                http_error_handler("AUTH");
                return;
        }
        if($ENV{$bin_auth_header} eq $bin_auth_value){
		eval {
			read(STDIN, my $file_content_data, $file_content_length);
			my $content_digest = md5_base64($file_content_data);
			open(FILEHANDLER, ">", BIN_DUMP_PATH."/".$content_digest) or die "$!";
			print FILEHANDLER $file_content_data;
			close FILEHANDLER;
			$http_response_body .= "https://".SERVER_HOSTNAME."/".CGI_LOCATION."/".$script_name."?id=".$content_digest."\n";
			$log_message .= " Successfully served POST ";
		}; if($@){ system("logger POST FILEHANDLER die: $@"); die; }
        }else{
                http_error_handler("AUTH");
		$log_message .= " Post Invalid Auth Error ";
        }
}

sub http_get_processor {
        unless(exists $ENV{QUERY_STRING}){
                http_error_handler("ID");
                return;
        }
        my ($query_key, $query_value) = split("=", $ENV{QUERY_STRING}) or die("split error");
	$log_message .= " ID: $query_key";
        my $file_path = BIN_DUMP_PATH."/".$query_value;
        if($query_key eq "id"){
                if(-e $file_path){
			eval {
				open(FILEHANDLER, "<", $file_path) or die "filehandler error, get";
				my @read_file_contentsRef = <FILEHANDLER>;
				my $read_file_contents = "";
				for (@read_file_contentsRef){
					$read_file_contents .= $_;
				}
				$http_response_body .= $read_file_contents;
				close FILEHANDLER;
				$log_message .= " Successfully served GET ";
			}; if($@){ system("logger GET FILEHANDLER error: $@"); die; }
                }else{
                        http_error_handler("ID");
			$log_message .= " File not exist ";
                }
        }else{
                http_error_handler("ID");
		$log_message .= " Invalid query key ";
        }
}

sub http_error_handler {
        my $error_type = $_[0];
        chomp($error_type);
        if($error_type eq "ID"){
                $http_response_body .= $http_id_error_msg;
        }elsif($error_type eq "AUTH"){
                $http_response_body .= $http_auth_error_msg;
        }else{
                $http_response_body .= $http_unknown_error_msg;
        }
}

sub http_responder {
        my $http_message = "";
        for (@http_response_headers){
                $http_message .= "$_\n\r";
        }
        $http_message .= "\n\r$http_response_body";
        print $http_message;
	eval {
		open (LOGHANDLER, ">>", LOG_DUMP_PATH) or die "$!";
		print LOGHANDLER $log_message."\n";
		close LOGHANDLER;
	}; if($@){ system("logger LOGHANDLER: $@"); die; }
}

sub _populate_error_msg {
        for (@error_responses){
                my ($key, $strings) = split("!");
                chomp($key); chomp($strings);
                if($key eq "ID"){
                        $http_id_error_msg .= $strings;
                }elsif($key eq "AUTH"){
                        $http_auth_error_msg .= $strings;
                }else{
                        $http_unknown_error_msg .= $strings;
                }
        }
}

__END__
ID!Target Bin-ID Does Not Exist, Recheck your ID
AUTH!You are NOT authorized
UNKNOWN!Do not send invalid data to the CGI Gateway
