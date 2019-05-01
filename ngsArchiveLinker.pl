#!/usr/bin/env perl

use FindBin;
use lib $FindBin::Bin."/lib/lib/perl5/";
use LWP::UserAgent;
use LWP::Simple;
use MIME::Base64;
use JSON;
use Getopt::Long;
use Pod::Usage;
use File::Path qw(make_path);
use File::Basename qw(basename);
use Term::ReadKey;
use HTTP::Status qw(:constants :is status_message);
use Config::Simple;
use Cwd;
use HTTP::Tiny;
use strict;
use warnings;

if(!@ARGV){ #if no args, print usage message
	pod2usage(0);
}

my $version = '1.0.2';
my $print_version = 0;

my $client_id="defaultLinker";
my $client_secret="defaultLinkerSecret";

use constant {FAIL_ON_DUPLICATE => 0, IGNORE_DUPLICATES => 1, RENAME_DUPLICATES => 2};
my @DEFAULT_CONFIG_LOCATIONS = ($FindBin::Bin."/ngs-archive-linker.conf",$ENV{HOME}."/.irida/ngs-archive-linker.conf","/etc/irida/ngs-archive-linker.conf");

my ($baseURL,$projectId, @sampleIds,$directory,$help,$verbose,$vverbose,$username,$password,$ignoreDuplicates,$renameDuplicates,$flatDirectory,$download,$configFile);

$directory = cwd();

GetOptions(
	"b|baseURL=s"=>\$baseURL,
	"p|project=s"=>\$projectId,
	"s|sample=s"=>\@sampleIds,
	"o|output=s"=>\$directory,
	"c|config=s"=>\$configFile,
	"username=s"=>\$username,
	"password=s"=>\$password,
	"i|ignore"=>\$ignoreDuplicates,
	"r|rename"=>\$renameDuplicates,
	"flat"=>\$flatDirectory,
	"d|download"=>\$download,
	"v|verbose"=>\$verbose,
	"vv|vverbose"=>\$vverbose,
	"version"=>\$print_version,
	"h|help"=>\$help
) or pod2usage(1);
##Error checking
pod2usage(1) if $help;
print "$version\n" and exit(0) if ($print_version);

if(!defined $projectId){
	print "Error: Project ID must be defined.  Use --help option for argument details.\n";
	exit(1);
}

print "Writing files to $directory\n";

if($vverbose){ #if we're very verbose, we're also verbose...
	$verbose = 1;
}

#get the level of what to do when we're working with duplicates
my $duplicateLevel = FAIL_ON_DUPLICATE;
if($ignoreDuplicates){
	$duplicateLevel = IGNORE_DUPLICATES;
}
if($renameDuplicates){
	$duplicateLevel = RENAME_DUPLICATES;
}

#get the config file from the set locations if it's not set by the user
if(!$configFile){
	#Check which config file to use
	foreach my $loc(@DEFAULT_CONFIG_LOCATIONS){
		if(-e $loc){
			$configFile = $loc;
			print "Using configuration $loc\n" if $verbose;
			last;
		}
	}
}

#set up the config file if it's set
my $config;
if($configFile && -e $configFile){
	$config = new Config::Simple($configFile);
	
	#get the oauth2 id and secret if they're set
	my $configClientId = $config->param("credentials.CLIENTID");
	my $configClientSecret = $config->param("credentials.CLIENTSECRET");
	
	#update the config values if they're in the config file
	$client_id = $configClientId if($configClientId);
	$client_secret = $configClientSecret if($configClientId);

}
elsif(!-e $configFile){
	print "Error: Config file $configFile cannot be found\n";
	exit(1);
}

if(!$baseURL){
	$baseURL = $config->param("apiurls.BASEURL") or die "Base URL not set and cannot be read from config file";
}

if(! -d $directory){
	print "Error: Directory $directory doesn't exist\n";
	exit(1);
}


if(!$username){
	print "Enter username: ";
	$username = <>;
	chomp $username;
}
if(!$password){
	print "Enter password: ";
	ReadMode('noecho');
	$password = <>;
	ReadMode('restore');
	print "\n";
	chomp $password;
}


my $agent = new LWP::UserAgent;
my $head = new HTTP::Headers;
my $url = $baseURL;

my $tokenstr = getToken($baseURL,$username,$password,$client_id,$client_secret);

$head->authorization("Bearer $tokenstr");

checkServerStatus($url,$agent,$head);

$url = buildProjectURL($url,$projectId,$agent,$head);

my $project = getProject($url,$agent,$head);
my $projectName = $project->{resource}->{name};

my %samples;

#get the sample URLs from either the requested samples or all for the selected project
if(@sampleIds){
	print "Reading samples ". join(",",@sampleIds) . " from project $projectId\n";
	%samples = getSampleUrlsFromList($project, \@sampleIds,$agent,$head);
}
else{
	print "Listing all samples from project $projectId\n";
	%samples = getSamplesForProject($project,$agent,$head);
}

my %sampleFiles;
foreach my $id(keys %samples){
	my $sample = $samples{$id};
	print "Getting sequence files for sample $id\n" if $verbose;
	my @files = getSequenceFilesForSample($sample,$agent,$head);
	
	foreach my $file (@files)
	{
		push(@{$sampleFiles{$id}},$file);
	}
}

#globals counting the number of files ignored and linked
my $fileCount = 0;
my $ignoreCount = 0; 

createLinks(\%sampleFiles,$projectName,$directory,$duplicateLevel,$flatDirectory,$download,$agent,$head);

#Get an OAuth2 token for the 
sub getToken{
	my $url = shift;
	my $username = shift;
	my $password = shift;
	my $client_id = shift;
	my $client_secret = shift;


        my $response = HTTP::Tiny->new->post_form($url."/oauth/token", {
            client_id => $client_id,
            client_secret => $client_secret,
            grant_type => "password",
            username => $username,
            password => $password });
        
        
        my $oauth_info = decode_json($response->{'content'});

        my $tokenstr = $oauth_info->{'access_token'};

	if(!defined $tokenstr){
            print "Couldn't get OAuth token: " . $response->{'status'} . "\n";
            print $oauth_info->{'error'} . ': ' . $oauth_info->{'error_description'} ."\n";
            exit(1);
        }
	
	return $tokenstr;
}

#Create a collection of links to the list of samples and files
sub createLinks{
	my $samples = shift;
	my $projectId = shift;
	my $directory = shift;
	my $duplicateLevel = shift;
	my $flatDirectory = shift;
	my $download = shift;
	my $client = shift;
	my $headers = shift;

	my $sampleCount = 0;

	if (keys %$samples > 0){
		my $projectDir = "$directory/$projectId";
		if(!-d $projectDir){
			make_path($projectDir) or die "Couldn't make project directory $projectDir: $!";
			print "Created project directory $projectDir\n" if $verbose;
		}

		foreach my $sampleId(keys %$samples){
			my $sampleDir;
			if(!$flatDirectory){ #if we don't want flat directorys, create a directory for the sequence file's sample
				$sampleDir = "$projectDir/$sampleId";
				if(!-d $sampleDir){
					make_path($sampleDir) or die "Couldn't make sample directory $sampleDir: $!";
					print "Created sample directory $sampleDir\n" if $verbose;
				}
			}
			else{
				$sampleDir = $projectDir;
			}

			$sampleCount++;

			foreach my $fileref(@{$samples->{$sampleId}}){
				my $filename = $fileref->{file};
				my $basename = basename($filename);

				my $newfile = "$sampleDir/$basename";

				if($download){
					downloadFile($fileref->{href},$newfile,$client,$headers,$duplicateLevel);
				}
				else{
					if(! -e $filename){
						die "Error: Script cannot see a file to be linked: $filename.  Ensure you have access to the sequence files directory.";
					}

					linkFile($newfile,$filename,$duplicateLevel);
				}
			}
		}
	
		if($fileCount > 0){
			print "Created $fileCount files for $sampleCount samples in $projectDir\n";
		}

		if($ignoreCount > 0){
			print "Skipped $ignoreCount files as they already exist\n";
		}
	}
	else{
		print "No sequence files to link for project $projectId\n";
	}

}

#check if a file or link exists
sub checkFileExistence{
	my $newfile = shift;
	my $duplicateLevel = shift;

	my $writeFile = 0;
	
	if((-l $newfile or -e $newfile) && $duplicateLevel == FAIL_ON_DUPLICATE){
		print "Error: File $newfile already exists\n";
		print "To skip already existing files, use --ignore option.  To create new files with a unique name, use --rename option.\n";
		exit(1);
	}
	elsif((-l $newfile or -e $newfile) && $duplicateLevel == IGNORE_DUPLICATES){
		print "Skipping $newfile as it already exists.\n" if $verbose;
		$ignoreCount++;
	}
	elsif((-l $newfile or -e $newfile) && $duplicateLevel == RENAME_DUPLICATES){
		print "File $newfile exists.  Trying to create a unique filename.\n" if $verbose;
		$writeFile = checkAvailableFilename($newfile);
	}
	else{
		$writeFile = $newfile;
	}

	return $writeFile;
}

sub checkAvailableFilename{
	my $filename = shift;

	my $baseId = 0;

	while(-e $filename or -l $filename){
		$baseId++;
		if($filename =~ /_\d+$/){
			$filename =~ s/_\d+$/_$baseId/;
		}
		else{
			$filename .= "_$baseId";
		}
	}

	return $filename;
}

#link an individual sequence file
sub linkFile{
	my $newfile = shift;
	my $filename = shift;
	my $ignoreDuplicates = shift;

	my $writeFile = checkFileExistence($newfile,$ignoreDuplicates);

	if($writeFile){
		symlink($filename,$writeFile) or die "Couldn't create link to file $filename: $!";
		print "Created link to file $filename at $writeFile\n" if $verbose;
		$fileCount++;
	}
}

#download an individual sequence file
sub downloadFile{
	my $href = shift;
	my $output = shift;
	my $client = shift;
	my $headers = shift;
	my $ignoreDuplicates = shift;
	
	my $writeFile = checkFileExistence($output,$ignoreDuplicates);
	
	if($writeFile){
	$client->show_progress(1);
		$head->header(Accept => 'application/fastq');
	
		my $req = HTTP::Request->new("GET",$href,$head);
		my $ret = $agent->request($req,$writeFile);
	
		$client->show_progress(0);
		$fileCount++;
	}
}

#get all the URLS for samples that are passed by the user
sub getSampleUrlsFromList{
	my $project = shift;
	my $sampleIds = shift;
	my $agent = shift;
	my $headers = shift;
	
	my %samples;

	foreach my $id(@$sampleIds){
		my($sequencerId,$sampleUrl) = getSampleDetails($project,$id,$agent,$headers);

		$samples{$sequencerId} = $sampleUrl;
	}
	
	return %samples;
}

#build the URL for a project and check that it exists
sub buildProjectURL{
	my $url = shift;
	my $projectId = shift;
	my $client = shift;
	my $headers = shift;
	
	my $respdat = makeJsonRequest($url,$agent,$headers);
	my $json = from_json($respdat->content);

	$url = getRelFromLinks($json->{resource}->{links},'projects');
	$url = "$url/$projectId";

	$respdat = makeJsonRequest($url,$agent,$headers);
	checkResponseCode($respdat,$url);	

	return $url;
}

#build the URL for a sample by its numerical ID and check that it exists
sub getSampleDetails{
	my $project = shift;
	my $sampleId = shift;
	my $agent = shift;
	my $headers = shift;

	#get the URL of project samples
	my $url = getRelFromLinks($project->{resource}->{links},'project/samples');
	$url = "$url/$sampleId";

	my $respdat = makeJsonRequest($url,$agent,$headers);

	checkResponseCode($respdat,$url);
	my $json = from_json($respdat->content);
	my $id = $json->{resource}->{sampleName};

	$url = getRelFromLinks($json->{resource}->{links}, 'self');
	
	return ($id,$json->{resource});
}

#get the given rel from the given collection of links
sub getRelFromLinks{
	my $links = shift;
	my $rel = shift;
	
	my $url;

	foreach my $link(@{$links}){
		if($link->{rel} eq $rel){
			$url = $link->{href};
		}
	}
	
	return $url;
}

#Get all the sample URLs for a particular project
sub getSamplesForProject{
	my $project = shift;
	my $agent = shift;
	my $head = shift;

	my $url = getRelFromLinks($project->{resource}->{links},'project/samples');
	
	my $ret = makeJsonRequest($url,$agent,$head);

	checkResponseCode($ret,$url);	
	my $resp = from_json($ret->content);

	my $resources = $resp->{resource}->{resources};

	my %samples;

	foreach my $sample(@$resources){
		my $sampleURL = $sample->{links}->[0]->{href};
		my $sequencerId = $sample->{sampleName};
		
		$samples{$sequencerId} = $sample;
	}

	return %samples;
}

#Get all the sequence file URLs associated with a sample
sub getSequenceFilesForSample{
	my $sample = shift;
	my $agent = shift;
	my $headers = shift;
	
	my $url = getRelFromLinks($sample->{links},"sample/sequenceFiles");
	my $respdat = makeJsonRequest($url,$agent,$headers);
	checkResponseCode($respdat,$url);	
	my $resp = from_json($respdat->content);
	my $resources = $resp->{resource}->{resources};

	my @files;
	foreach my $filedat(@$resources){
		my $file = $filedat->{file};
		my $href = $filedat->{links}->[0]->{href};
		my %ref = ("file"=>$file,"href"=>$href);
		push(@files,\%ref);
	}

	return @files;
}

#get the project from the API
sub getProject{
	my $projectURL = shift;
	my $agent = shift;
	my $headers = shift;

	my $respdat = makeJsonRequest($projectURL,$agent,$headers);
	checkResponseCode($respdat,$projectURL);
	my $resp = from_json($respdat->content);
	
	return $resp;
}

#check that the server is available
sub checkServerStatus{
	my $baseURL = shift;
	my $agent = shift;
	my $headers = shift;
	
	my $ret = makeJsonRequest($baseURL,$agent,$headers);

	checkResponseCode($ret,$baseURL);
}

#make a request for JSON data
sub makeJsonRequest{
	my $url = shift;
	my $agent = shift;
	my $headers = shift;
	
	$headers->header(Accept => 'application/json');

	my $req = HTTP::Request->new("GET",$url,$headers);
	my $ret = $agent->request($req);

	return $ret;
}

#check the given response to ensure that the response code is OK
sub checkResponseCode{
	my $response = shift;
	my $url = shift;
	
	my $code = $response->code;
	if($vverbose){
		print "HTTP response from $url: $code " . status_message($code) . "\n";
	}

	if($code == HTTP_UNAUTHORIZED){
		print "Error: Username or password are incorrect.\n";
		exit(1);
	}
	elsif($code == HTTP_INTERNAL_SERVER_ERROR){
		print "Error: Server returned internal server error.  You may have used an incorrect URL for the API.\n";
		exit(1);
	}
	elsif($code == HTTP_FORBIDDEN){
		print "Error: This user does not have access to the resource at $url.\n";
		exit(1);
	}
	elsif($code == HTTP_NOT_FOUND){
		print "Error: Requested resource wasn't found at $url.\n";
		exit(1);
	}
	elsif($code != HTTP_OK){
		print "Error: Server returned status code $code when requesting resource $url.\n";
		exit(1);
	}
}

__END__
=head1 NAME

ngsArchiveLinker.pl - Get links for files stored in the NGS archive

=head1 SYNOPSIS

ngsArchiveLinker.pl -b <API URL> -p <projectId> -o <outputDirectory> [-s <sampleId> ...]

=head1 DESCRIPTION

B<ngsArchiveLiner.pl> allows users to work with their files from the NGS Archive without having to copy the large sequencing files to their machines.  It is a Perl script used to generate a structure of links for files stored in the NGS archive. You are able to get links to the files in an entire project, or to specific samples within a project.

=head1 OPTIONS

=over 8

=item B<-p, --projectId [ARG]>

The ID of the project to get data from. (required)

=item B<-o, --output [ARG]>

A directory to output the collection of links. (Default: Current working directory)

=item B<-c, --config [ARG]>

The location of the config file.  Not required if --baseURL option is used.  (Default: $HOME/.irida/ngs-archive-linker.conf, /etc/irida/ngs-archive-linker.conf)

=item B<-b, --baseURL [ARG]>
    
The base URL for the NGS Archive REST API.  Overrides config file setting.

=item B<-s, --sample [ARG]>

A sample id to get sequence files for.  Not required.  Multiple samples may be listed as -s 1 -s 2 -s 3...

=item B<-i, --ignore>

Ignore creating links for files that already exist.

=item B<-r, --rename>

Rename existing files with _# suffix.  Useful for topup runs with similar filenames.  NOTE: This option overrides the --ignore option.

=item B<--flat>

Create links or files in a flat directory under the project name rather than in sample directories.

=item B<--username>

The username to use for API requests.  
Note: if this option is not entered it will be requested during running of the script.

=item B<--password>

The password to use for API requests.  
Note: if this option is not entered it will be requested during running of the script.

=item B<--download>

Option to download files from the REST API instead of softlinking.  Note: Files may be quite large.  This option is not recommended if you have access to the sequencing filesystem.

=item B<-v, --verbose>

Print verbose messages.

=item B<-h, --help>

Display a help message.

=item B<--version>

Print version.

=back

=cut
