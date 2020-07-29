package IridaFileStorageAwsUtility;
use strict;
use warnings;
use Exporter;
use Net::Amazon::S3;
use Net::Amazon::S3::Client;
use Net::Amazon::S3::Client::Object;

our @ISA= qw( Exporter );

our @EXPORT = qw( downloadAwsFile );

my $bucket_name = $::config->param("cloud.AWSBUCKETNAME");
my $aws_access_key_id = $::config->param("cloud.AWSACCESSKEY");
my $aws_secret_access_key = $::config->param("cloud.AWSSECRETKEY");

my $s3 = Net::Amazon::S3->new(
  aws_access_key_id     => $aws_access_key_id,
  aws_secret_access_key => $aws_secret_access_key,
  retry                 => 1
);

my $s3Client = Net::Amazon::S3::Client->new( s3 => $s3 );
my $bucket = $s3Client->bucket( name => $bucket_name );

# Download an individual sequence file from an AWS S3 bucket
sub downloadAwsFile {
    my $href = shift;
    my $path = shift;
    my $output_file = shift;
    my $writeFile = shift;
    my $type = shift;

    # the path has a leading slash which needs to be removed
    # before accessing the bucket otherwise the object is not
    # found in the bucket
    $path = substr($path, 1);

    my $object = $bucket->object( key => $path );
    if(getFileExtension($object->{key}) eq $type)
    {
        $object->get_filename($output_file);
        $::fileCount++;
    } else {
        print "Incorrect content-type. $href was not downloaded";
    }
}

# Since the S3 perl module doesn't have a way to download a file with a header 
# we use this subroutine to return the file extension which is checked against
# the type (fasta, fastq) and will only download the file if it matches the type.
sub getFileExtension {
    my $path = shift;
    my @pathTokens = split('/', $path);
    my @filenameTokens = split('\\.', $pathTokens[-1]);
    my $file_extension = $filenameTokens[-1];
    return $file_extension;
}

1;