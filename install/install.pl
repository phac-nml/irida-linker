#!/usr/bin/env perl

use FindBin;
use strict;
use warnings;

use constant DEFAULT_REST_URL=>"http://localhost:8080/api";


#Install PERL packages
my @requiredPackages = ("LWP::UserAgent","LWP::Simple","MIME::Base64","JSON",
			"Getopt::Long","Pod::Usage","File::Path","File::Basename",
			"Term::ReadKey","HTTP::Status","Config::Simple");

my $binLoc = $FindBin::Bin;
my $defaultLib = "$binLoc/../lib/";
my $libDir = textOption("Perl library location?",$defaultLib);
if(!-d $libDir){
	die "Library path $libDir is not a valid directory!";
}

print "Using $libDir as library\n";
foreach my $pack(@requiredPackages){
	##INSTALL Config::Simple
	eval("use $pack");

	if($@){
		my $ret = option("Package $pack is not installed. Would you like to try to install it using cpanm?","y");

		if($ret eq "y"){
			my $cmd = "cpanm -L $libDir $pack";
			print "Running command: $cmd\n";
			system($cmd);
		}
	}
}


##Install config file
my $iridaDir = $ENV{HOME}."/.irida/";
my $confFile = "$iridaDir/ngs-archive-linker.conf";

my $ret = option("Install config file to $confFile?","y");
if($ret eq "y"){
	if(!-d $iridaDir){
		print "Creating directory $iridaDir\n";
		mkdir($iridaDir);
	}

	open(OUT, ">" , $confFile) or die "Couldn't open file $confFile";
        
	my $ngsloc = textOption("REST API location?",DEFAULT_REST_URL);
	print "Setting base URL as $ngsloc in $confFile\n";
        print OUT "[apiurls]\n";
	print OUT "BASEURL=$ngsloc\n";

	print OUT "\n";

	my $iridaClientId = textOption("IRIDA Client ID?","");
	my $iridaClientSecret = textOption("IRIDA Client Secret?", "");
	print "Setting IRIDA client ID as $iridaClientId and client secret as $iridaClientSecret in $confFile\n";
        print OUT "[credentials]\n";
	print OUT "CLIENTID=$iridaClientId\n";
	print OUT "CLIENTSECRET=$iridaClientSecret\n";
        
	close OUT;
}

sub textOption{
	my $message = shift;
	my $default = shift;
	print "$message [$default] ";

	my $input = <>;
	chomp $input;
	my $return = $default;
	if($input ne ""){
		$return = $input;
	}

	return $return;
}

sub option{
	my $msg = shift;
	my $default = shift;
	
	if(lc($default) eq "y"){
		$msg .= " [Y,n] ";
	}
	else{
		$msg .= " [y,N] ";
	}

	print $msg;
	my $input;
	my $valid = 0;
	do{
		$input = <>;
		chomp $input;
		$input = lc($input);
		if($input eq ""){
			$input = $default;
		}

		if($input eq "y" or $input eq "n"){
			$valid = 1;
		}
		else{
			print "Invalid entry: $input\n";
		}
	}
	while(!$valid);

	return $input;
}
