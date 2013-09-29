#!/usr/bin/env perl
#-*-perl-*-

use Test::More;

use FindBin qw/$Bin/;
use lib "$Bin/../lib";

BEGIN { use_ok('Text::Srt::Align', ':all') };

done_testing;
