#!/bin/env perl
#----------------------------------------------------------------------
# PD 20160601
#
# Simple script to fetch the current WAN IP address from a
# Nighthawk R7000 router, and update a duckdns.org account.
#
# Note that one could simply add a crontab with :
#
# */10 * * * * curl 'https://www.duckdns.org/update?domains=DOMAIN&token=TOKEN'
#
# But then we wouldn't see when the IP Address changes, or catch any error.
#
#
# https://github.com/pdemarti/ddns-update
#
#----------------------------------------------------------------------
#
# MIT License
#
# Copyright (c) 2016 Pierre Demartines
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
#----------------------------------------------------------------------


use DB_File;
use File::Basename qw/dirname/;
use Getopt::Long qw/GetOptions/;
use HTML::TableExtract;
use HTML::TreeBuilder;
use Pod::Usage;
use POSIX qw/strftime/;

my $dir = dirname $0;
my $version = '0.3';
my $dbfile  = "$dir/.ip_hist";
my $curl_pass = "$dir/.curl-pass";
my $curl_pass_template = "$dir/curl-pass-template";
my $config_file = "$dir/.config";
my $config_file_template = "$dir/config-template";
my $verbose = '';
my $inspect = '';
my $help;
my $man;
my $runtime_str = pt(time);

GetOptions(
	   'help|?' => \$help,
	   'man'    => \$man,
	   'verbose|v+' => \$verbose,
	   'dbfile=s'  => \$dbfile,
	   'inspect!' => \$inspect,
	   'force|f!' => \$force,
	   'dry_run|n!' => \$dry_run) ||
  pod2usage(-verbose => 0);
pod2usage(-verbose => 1)  if ($help);
pod2usage(-verbose => 2)  if ($man);

# check .curl-pass and .config files exist
my $need_config = 0;
my $banner = '-'x80;
if (! -f $curl_pass) {
    qx{cp $curl_pass_template $curl_pass};
    $status = $? >> 8;
    exit $status if $status;
    chmod(0600, $curl_pass) || die "Couldn't chmod $curl_pass: $!";
    print STDERR "$banner\n";
    print STDERR "A new curl password file was created from template.\n";
    print STDERR "The format is (see man curl, option --netrc-file):\n\n";
    print STDERR "machine ROUTER-ADDRESS login USERNAME password PASSWORD\n\n";
    print STDERR "Please edit   $curl_pass\n\n\n";
    $need_config = 1;
}
if (! -f $config_file) {
    qx{cp $config_file_template $config_file};
    $status = $? >> 8;
    exit $status if $status;
    chmod(0600, $config_file) || die "Couldn't chmod $config_file: $!";
    print STDERR "$banner\n";
    print STDERR "A new config file was created from template.\n\n";
    print STDERR "Please edit   $config_file\n\n\n";
    $need_config = 1;
}
exit 0 if $need_config;

my %s = ();

open(CONFIG, $config_file) || die "Couldn't read $config_file: $!";
while (<CONFIG>) {
    chomp;
    s/#.*//;
    trim;
    my ($key, $value) = split(/\s*=\s*/, $_, 2);
    $s{$key} = $value if $key;
}
close CONFIG;

for my $k (qw/ddns_url router_url domain token/) {
    die "undefined value in $config_file: $k\n" unless $s{$k};
}

my %db;

# open or create the database
tie(%db, "DB_File", $dbfile) || die "Cannot open $dbfile: $!\n";

if ($inspect) {
    for my $k (keys %db) {
	printf("%s => %s\n", $k, $db{$k});
    }
}

my $pip = $db{'ip'};
my $ip;

open(R, "curl -s --netrc-file $curl_pass $s{router_url}|") || die "Couldn't open $s{router_url}: $!\n";
$/ = undef;
my $body = <R>;
close R;

$ip = get_ip_from_html_body($body);
unless ($ip =~ /^\d+\.\d+\.\d+\.\d+$/) {
    $body_text = HTML::TreeBuilder->new()->parse_content($body)->as_text();
    $body_text =~ s/^(.{130}).*/$1 (...)\n/m;
    die "Couldn't obtain WAN IP address:\n$body_text";
}

printf("%s got WAN IP Address = %s\n", $runtime_str, $ip) if $verbose;

if ($ip ne $pip) {
    # new address
    printf("%s new address = %s\t\t(previous was %s from %s to %s = %d days)\n",
	   $runtime_str, $ip, $pip,
	   pt($db{'first'}), pt($db{'last'}), ($db{'last'} - $db{'first'})/24/3600);
    unless ($dry_run) {
	$db{'ip'} = $ip;
	$db{'first'} = $t;
	$db{'last'} = $t;
	$db{'last-update'} = 0;
    }
} else {
    printf("%s no change since %s.\n", $runtime_str, pt($db{'first'})) if $verbose;
}

if ($force || $ip ne $pip || $t > $db{'last-update'}+24*3600) {
    # time to update DDNS
    my $url = make_ddns_request_url();
    if ($dry_run) {
	printf("%s would update DDNS to %s (DRY-RUN) with\n%s\n", $runtime_str, $ip, $url);
    } else {
	printf("%s update DDNS to %s\n", $runtime_str, $ip);
	my $st = submit_url($url);
	if ($st =~ /OK/) {
	    printf("%s received from DDNS: '%s'\n", $runtime_str, $st) if ($verbose);
	    $db{'last-update'} = $t;
	} else {
	    printf(STDERR "%s ERROR; received from DDNS: '%s'\n", $runtime_str, $st);
	}
    }
} else {
    printf("%s skip DDNS refresh.\n", $runtime_str) if $verbose;
}

untie(%db);

sub pt {
    my $t = shift;
    return strftime("%Y-%m-%d %H:%M:%S", localtime($t)) if $t;
    return "undef";
}

sub make_ddns_request_url {
    my $url = $s{ddns_url};
    $s{ip} = $ip;
    while ($url =~ s/\[(\w+)\]/\001/) {
	my $k = $1;
	my $v = $s{$k};
	die "Param '$k' undefined in $config_file\n" unless defined $v;
	$url =~ s/\001/$v/;
    }
    return $url;
}

sub submit_url {
    my $url = shift;
    my $cmd = "echo url=\"$url\" | curl -k -s -K -";
    open(D, "$cmd|") || die "couldn't run $cmd: $!\n";
    my @ans = ();
    while (<D>) {
	push(@ans, $_);
    }
    close D;
    return wantarray ? @ans : join("\n", @ans);
}


sub get_ip_from_html_body {
    my $body = join('\n', @_);
    my $te = HTML::TableExtract->new()->parse($body);
    for my $ts ($te->tables) {
	for my $row ($ts->rows) {
	    my @col = map { trim($_) } @$row;
	    return $col[1] if $col[0] =~ /^IP Address$/i and $col[1] =~ /^\d+\.\d+\.\d+\.\d+$/;
	}
    }
    return undef;
}

sub trim { s/^\s+|\s+$//gm; $_ }


__END__

=head1 NAME

ddns-update - Update DuckDNS if needed

=head1 SYNOPSIS

ddns_update [options]

 Options:
   -h|-help         brief help message
   -dbfile file     indicate a different file for the cache
   -f|-force        update DDNS even if the IP address hasn't changed
   -n|-dry-run      don't actually update the DDNS nor the local cache
   -v|-verbose      more output while doing its thing

=head1 DESCRIPTION

B<This program> reaches to the router to find out the current WAN IP address.  If it has changed, or if enough
time has lapsed since the last update, it will update the DDNS service.

=cut
