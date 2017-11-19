#!/usr/bin/env perl
#-*-perl-*-

use utf8;

use Test::More;
use File::Compare;
use File::Temp qw/ tempfile /;

use FindBin qw/$Bin/;
use lib "$Bin/../lib";
use Cwd;

my $SRTALIGN = $Bin.'/../srtalign';

my $srcfile = 'xml/de/shrek3.xml';
my $trgfile = 'xml/en/shrek3.xml';

my $HomeDir = getcwd;
chdir($Bin);

my ($fh, $filename) = tempfile();
close $fh;
system("$SRTALIGN $srcfile $trgfile > $filename 2>/dev/null");
is( compare( "$filename", "$Bin/xml/de-en/shrek3.basic.xml" ),0, "align (basic)" );

($fh, $filename) = tempfile();
close $fh;
system("$SRTALIGN -d $Bin/../share/dic/eng-ger -b $trgfile $srcfile > $filename 2>/dev/null");
is( compare( "$filename", "$Bin/xml/en-de/shrek3.dic.best.xml" ),0, "align (dic,best)" );


($fh, $filename) = tempfile();
close $fh;
system("$SRTALIGN -c 0.65 -b $srcfile $trgfile > $filename 2>/dev/null");
is( compare( "$filename", "$Bin/xml/de-en/shrek3.cog.best.xml" ),0, "align (dic,best)" );


chdir($HomeDir);
done_testing;
