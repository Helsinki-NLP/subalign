#!/usr/bin/env perl
#-*-perl-*-

use utf8;

use Test::More;
use File::Compare;
use File::Temp qw/ tempfile /;

use FindBin qw/$Bin/;
use lib "$Bin/../lib";

my $SRT2XML = $Bin.'/../srt2xml';

# evaluation files
my %movies = ( de => "shrek3",
	       en => "shrek3",
	       nl => "shrek3",
	       sv => "shrek3");

my %encoding = ( de => "iso-8859-1",
		 en => "iso-8859-1",
		 nl => "iso-8859-1",
		 sv => "iso-8859-1");

foreach my $l (keys %movies){
    my ($fh, $filename) = tempfile();
    close $fh;
    system("$SRT2XML -l $l -e $encoding{$l} < $Bin/srt/$l/$movies{$l}.srt > $filename");
    is( compare( "$filename", "$Bin/xml/$l/$movies{$l}.xml" ),0, "convert $movies{$l}" );
}

done_testing;
