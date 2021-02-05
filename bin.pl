#!/bin/perl
use warnings;
use strict;
use constant BIN_DUMP_PATH => "/tmp/dump_bin";
use constant SERVER_HOSTNAME => "cname.mydomain.tld";
use constant CGI_LOCATION => "cgi-gateway";
use Digest::MD5 qw/md5_base64/;
use File::Basename;

my $request_method = $ENV{REQUEST_METHOD};
my $bin_auth_header = "HTTP_X_BIN_AUTH";
my $bin_auth_value = "SecurePassword";
my $file_content_length = $ENV{CONTENT_LENGTH};
my @http_response_headers = (
        "Content-Type: text/plain"
);
my $script_name = basename($0);
my $http_response_body = "";
my @error_responses = <DATA>;
my $http_id_error_msg = "";
my $http_auth_error_msg = "";
my $http_unknown_error_msg = "";

open (LOGHANDLER, ">", "/usr/lib/cgi-gateway/log.txt") or system("logger Log ERROR $!");

unless(-d BIN_DUMP_PATH){ mkdir(BIN_DUMP_PATH); }

_populate_error_msg();

if($request_method eq "GET"){
        print LOGHANDLER "logger GET Request\n";
        http_get_processor();
}elsif($request_method eq "POST"){
        print LOGHANDLER "logger POST Request\n";
        http_post_processor();
}else{
        print LOGHANDLER "logger ERROR Request\n";
        http_error_handler("UNKNOWN");
}

http_responder();

sub http_post_processor {
        unless(exists $ENV{$bin_auth_header}){
                http_error_handler("AUTH");
                return;
        }
        if($ENV{$bin_auth_header} eq $bin_auth_value){
                read(STDIN, my $file_content_data, $file_content_length);
                my $content_digest = md5_base64($file_content_data);
                open(FILEHANDLER, ">", BIN_DUMP_PATH."/".$content_digest) or die "filehandler error, dump";
                print FILEHANDLER $file_content_data;
                print LOGHANDLER "POST Data: $file_content_data\n";
                close FILEHANDLER;
                $http_response_body .= "https://".SERVER_HOSTNAME."/".CGI_LOCATION."/".$script_name."?id=".$content_digest."\n";
        }else{
                http_error_handler("AUTH");
        }
}

sub http_get_processor {
        unless(exists $ENV{QUERY_STRING}){
                http_error_handler("ID");
                return;
        }
        my ($query_key, $query_value) = split("=", $ENV{QUERY_STRING}) or die("split error");
        print LOGHANDLER "\nID: $query_key";
        my $file_path = BIN_DUMP_PATH."/".$query_value;
        if($query_key eq "id"){
                if(-e $file_path){
                        open(FILEHANDLER, "<", $file_path) or die "filehandler error, get";
                        my @read_file_contentsRef = <FILEHANDLER>;
                        my $read_file_contents = "";
                        for (@read_file_contentsRef){
                                $read_file_contents .= $_;
                        }
                        $http_response_body .= $read_file_contents;
                        close FILEHANDLER;
                }else{
                        print LOGHANDLER "logger Error Log";
                        http_error_handler("ID");
                }
        }else{
                print LOGHANDLER "logger Error Log";
                http_error_handler("ID");
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
        print LOGHANDLER "logger http-message: $http_message";
        $http_message .= "\n\r$http_response_body";
        print LOGHANDLER "logger http-message: $http_message";
        print LOGHANDLER "Message: $http_message";
        print LOGHANDLER "HTTP Request method: $request_method\n";
        print LOGHANDLER "Content-Legth: $file_content_length";
        print $http_message;
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
