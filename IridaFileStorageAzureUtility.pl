package IridaFileStorageAzureUtility;
use strict;
use warnings;
use Exporter;
use Net::Azure::StorageClient::Blob;

our @ISA= qw( Exporter );

# these are exported by default.
our @EXPORT = qw( downloadAzureFile );

my $account_name = $::config->param("cloud.AZUREACCOUNTNAME");
my $access_key = $::config->param("cloud.AZUREACCOUNTKEY");
my $container_name = $::config->param("cloud.AZURECONTAINERNAME");

my $blobService = Net::Azure::StorageClient::Blob->new(
                                  account_name => $account_name,
                                  primary_access_key => $access_key,
                                  container_name => $container_name,
                                  protocol => 'https');

my $RESPONSE_OK = '200';

# Downloads an individual sequence file from an Azure container
sub downloadAzureFile {
    my $href = shift;
    my $path = shift;
    my $output_file = shift;
    my $writeFile = shift;
    my $accept = shift;

    # the path has a leading slash which needs to be removed
    # before accessing the container otherwise the blob is not
    # found in the container
    $path = substr($path, 1);

    if ($writeFile) {
        $output_file = { filename => $output_file, headers => { 'ACCEPT' => $accept } };
        my $res = $blobService->get_blob( $path, $output_file );

        my $rc = $res->{_rc};
        my $msg = $res->{_msg};
        if($rc eq $RESPONSE_OK) {
            print "** GET $href ==> $rc $msg\n";
            $::fileCount++;
        } else {
            print "Unable to get file $href => $rc $msg\n";
        }
    }
}


1;