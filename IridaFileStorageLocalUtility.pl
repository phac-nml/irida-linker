package IridaFileStorageLocalUtility;
use strict;
use warnings;
use Exporter;

our @ISA= qw( Exporter );

# these are exported by default.
our @EXPORT= qw( downloadLocalFile );


#download an individual sequence file from local storage
sub downloadLocalFile {
    my $href             = shift;
    my $client           = shift;
    my $accept            = shift;
    my $writeFile = shift;
    my $agent = shift;
    my $head = shift;

    if ($writeFile) {
        $client->show_progress(1);
        $head->header( Accept => $accept );

        my $req = HTTP::Request->new( "GET", $href, $head );
        my $ret = $agent->request( $req, $writeFile );

        $client->show_progress(0);
        $::fileCount++;
    }
}

1;