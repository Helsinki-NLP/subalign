#!/usr/bin/env perl
#-*-perl-*-

use utf8;

use Test::More;
use File::Compare;
use File::Temp qw/ tempfile /;

use FindBin qw/$Bin/;
use lib "$Bin/../lib";
use Cwd;

my $SUBALIGN = $Bin.'/../subalign';

my $srcdir = 'en/2001/209475';
my $trgdir = 'et/2001/209475';

my $HomeDir = getcwd;
chdir($Bin);

my ($fh, $filename) = tempfile();
close $fh;


system("$SUBALIGN $srcdir $trgdir > $filename.out 2>$filename.err");
is( file_exists("en-et/2001/209475/54828-3123721.xml.gz"), 1, "output file exists");

print STDERR `pwd`;

system("gunzip -f en-et/2001/209475/54828-3123721.xml.gz");
is( compare( "en-et/2001/209475/54828-3123721.xml", "xml/en-et/2001/209475/54828-3123721.xml" ),0, "subalign result" );


chdir($HomeDir);
done_testing;

## cleanup
unlink("$filename.out");
unlink("$filename.err");
unlink("en-et/2001/209475/54828-3123721.xml");
rmdir("en-et/2001/209475");
rmdir("en-et/2001");
rmdir("en-et");


sub file_exists{
    my $file = shift;
    return 1 if ( -f $file );
    return 0;
}
