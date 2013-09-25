#-*-perl-*-
#---------------------------------------------------------------------------
# Copyright (C) 2004-2012 Joerg Tiedemann
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#---------------------------------------------------------------------------

=head1 NAME

Text::SRT::Align - sentence alignment for movie subtitles based on time overlaps

=head1 SYNOPSIS

 use Text::SRT::Align qw/:all/;

 # source and target language files in XML format
 # (use srt2xml to convert srt to XML)

 my $srcfile    = "source-language-file.xml";
 my $trgfile    = "target-language-file.xml";
 my @alignments = ();

 # find alignments between sentences in source and target
 # print the result in XCES Align format

 my $score = &align( $srcfile,$trgfile,\@alignments)
 print_ces($srcfile,$trgfile,\@alignment);

 # run a new alignment
 # - use a cognate filter to find synchronization points
 # - cognate filter uses string similarity threshold 0.8
 # - use 'best-align' mode: find the best synchonization points

 my $score = &align( $srcfile,$trgfile,\@alignments,
                     USE_COGNATES => 0.8,
                     BEST_ALIGN => 1 );

=head1 DESCRIPTION

Text::SRT:Align aligns sentences with the largest time overlap. Time information has to be available in the XML files to be aligned. Use C<srt2xml> to convert movie subtitle files from *.srt format to XML!

=cut


package Text::SRT::Align;


use strict;

use XML::Parser;
use IO::File;
use File::ShareDir qw/dist_dir/;
use Locale::Codes::Language 3.26;


use Exporter 'import';
our @EXPORT_OK   = qw(align print_ces);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );


our $VERSION = '0.1.0';
our $AUTHOR  = 'Joerg Tiedemann';

our $VERBOSE  = 0;
our $FALLBACK = 'align/hun';
our $UPLUG    = 'uplug';


our $WINDOW        = 25;
our $BEST_ALIGN    = 0;
our $MAX_MATCHES   = undef;

our $TOK_LEN       = undef;
our $CHAR_SET      = undef;
our $USE_WORDFREQ  = undef;
our $UPPER_CASE    = undef;
our $COGNATE_RANGE = undef;
our $MINLENGTH     = 5;

our $USE_DICTIONARY = undef;
our $USE_COGNATES   = undef;
our $USE_IDENTICAL  = undef;


my %DIC     = ();
my $srcfreq = undef;
my $trgfreq = undef;


################################################################################

=head1 Exported Functions

=head2 C<$score = align( $srcfile, $trgfile, \@alignments [,%options] )>

Alignments will be returned within the C<@alignment> array. Possible options are

  # verbose output
  VERBOSE => 1

  # specify hard boundaries
  HARD_BOUNDARES => $boundaries

  # use 'best-align' mode:
  # - find lexical matches in the beginning and at the end of each movie
  # - test synchronization with all possible pairs of matched lexical items
  # - use the one that gives the highest score 
  #   (proportion between non-emtpy and empty links)
  BEST_ALIGN => 1

  # lexical matching for synchronization
  # - window size for finding matches (beginning and end in number of sentences)
  # - number of matches to be used in best-align mode
  WINDOW => $window_size
  MAX_MATCHES => $nr_matches

  # us a bilingual dictionary for finding possible translation equivalents
  USE_DICTIONARY => $dictionary_file

  # match strings (possible cognates)
  # - identical tokens
  # - minimum length of tokens to be matched
  # - words starting with upper-case letters only (named entities?)
  # - word frequency heuristics (prefer rare identical words)
  # - character set restrictions (for example, only alphabetic letters: \p{L})
  USE_IDENTICAL => 1
  TOK_LEN => $minimum_token_length
  UPPER_CASE => 1
  USE_WORDFREQ => 1
  CHAR_SET => $character_set

  # string-similarity-based matching using LCSR scores
  # - define matching threshold
  # - minimum token length
  # - use cognates with macthing scores 1..$sim_score in combination with best_align
  USE_COGNATES => $cognate_threshold
  MINLENGTH => $minimum_token_length
  COGNATE_RANGE => $sim_score



=cut

sub align{
    my $srcfile = shift;
    my $trgfile = shift;
    my $alignment = shift || [];

    my %options = @_;

    # make sure we print error messages in UTF8 ....
    # TODO: should we change it back after running the alignment procedure?
    binmode(STDERR,":utf8");

    # set some global variables
    # TODO: can we skip all these global settings?

    $VERBOSE        = $options{VERBOSE} if (defined $options{VERBOSE});

    # variables enabling lexical matching for time synchronization
    # - match entries from bilingual dictionaries
    # - match idenical tokens
    # - match "cognates" (using string similarity measures)
    $USE_DICTIONARY = $options{USE_DICTIONARY} if (defined $options{USE_DICTIONARY});
    $USE_IDENTICAL  = $options{USE_IDENTICAL} if (defined $options{USE_IDENTICAL});
    $USE_COGNATES   = $options{USE_COGNATES} if (defined $options{USE_COGNATES});

    # parameters for lexical matching
    $COGNATE_RANGE  = $options{COGNATE_RANGE} if (defined $options{COGNATE_RANGE});
    $UPPER_CASE     = $options{UPPER_CASE} if (defined $options{UPPER_CASE});
    $TOK_LEN        = $options{TOK_LEN} if (defined $options{TOK_LEN});
    $MINLENGTH      = $options{MINLENGTH} if (defined $options{MINLENGTH});
    $USE_WORDFREQ   = $options{USE_WORDFREQ} if (defined $options{USE_WORDFREQ});
    $CHAR_SET       = $options{CHAR_SET} if (defined $options{CHAR_SET});

    # window size for finding lexical matches (beginning and end of file)
    $WINDOW         = $options{WINDOW} if (defined $options{WINDOW});
    $MAX_MATCHES    = $options{MAX_MATCHES} if (defined $options{MAX_MATCHES});

    # TODO: is it OK if we never reset the dictionary?
    # (will be used again if align is called multiple times)
    if ($USE_DICTIONARY){
	&ReadDictionary(\%DIC,$USE_DICTIONARY);
    }
    elsif ($options{SOURCE_LANG} && $options{TARGET_LANG}){

	# make a three-letter language code
	if (length($options{SOURCE_LANG}) == 2){
	    $options{SOURCE_LANG} = language_code2code($options{SOURCE_LANG}, 'alpha-2', 'alpha-3');
	}
	if (length($options{TARGET_LANG}) == 2){
	    $options{TARGET_LANG} = language_code2code($options{TARGET_LANG}, 'alpha-2', 'alpha-3');
	}

	my $SharedHome = &dist_dir('Text-SRT-Align');
	if (-e "$SharedHome/dic/$options{SOURCE_LANG}-$options{TARGET_LANG}"){
	    $USE_DICTIONARY = "$SharedHome/dic/$options{SOURCE_LANG}-$options{TARGET_LANG}";
	    &ReadDictionary(\%DIC,$USE_DICTIONARY);
	    $options{BEST_ALIGN} = 1;
	}
	# inverse dictionary
	if (-e "$SharedHome/dic/$options{TARGET_LANG}-$options{SOURCE_LANG}"){
	    $USE_DICTIONARY = "$SharedHome/dic/$options{TARGET_LANG}-$options{SOURCE_LANG}";
	    &ReadDictionary(\%DIC,$USE_DICTIONARY,1);
	    $options{BEST_ALIGN} = 1;
	}
    }

    if (! -e $srcfile){$srcfile.='.gz';}
    if (! -e $trgfile){$trgfile.='.gz';}

    if (! -e $srcfile){die "$srcfile doesn't exist!\n";}
    if (! -e $trgfile){die "$trgfile doesn't exist!\n";}

    my @srcdata=();
    my @trgdata=();

    $srcfreq=undef;
    $trgfreq=undef;

    my %first=();   # word matches in initial part of the move
    my %last=();    # matches in final part of the movie

    print STDERR "parse '$srcfile' & '$trgfile' ... " if ($VERBOSE);
    &parse_bitext($srcfile,$trgfile,\@srcdata,\@trgdata,\%first,\%last);
    print STDERR "ok!\n" if ($VERBOSE);

    ## fix start and end times (without scaling and offsets)
    &set_sent_times(\@srcdata);
    &set_sent_times(\@trgdata);

    if (defined $options{HARD_BOUNDARIES}){
	&fit_hard_boundaries($options{HARD_BOUNDARIES},\@srcdata,\@trgdata);
    }

    my $score=undef;
    my $baseScore=undef;

    print STDERR "align sentences ... " if ($VERBOSE);
    if ($COGNATE_RANGE){
	$score = &cognate_align($srcfile,$trgfile,
				\@srcdata,\@trgdata,
				\%first,\%last,$alignment);
    }
    if ($options{BEST_ALIGN}){
	($score,$baseScore) = 
	    &best_align($srcfile,$trgfile,
			\@srcdata,\@trgdata,
			\%first,\%last,$alignment);
    }
    else{
	$score = &standard_align(\@srcdata,\@trgdata,\%first,\%last,$alignment);
    }

    print STDERR "done!\n" if ($VERBOSE);
    if ($baseScore){
	print STDERR "ratio = $score ($baseScore)\n";
    }
    else {
	print STDERR "ratio = $score\n";
    }

    return $score;
}


=head2 C<print_ces( $srcfile, $trgfile, \@alignments )>

Print the sentence alignments in XCES Align format.

=cut


sub print_ces{
    my ($src,$trg,$alg)=@_;

    print '<?xml version="1.0" encoding="utf-8"?>'."\n";
    print '<!DOCTYPE cesAlign PUBLIC "-//CES//DTD XML cesAlign//EN" "">'."\n";
    print '<cesAlign version="1.0">'."\n";
    print "<linkGrp targType=\"s\" fromDoc=\"$src\" toDoc=\"$trg\">\n";

    foreach my $i (0..$#{$alg}){
	print "<link id=\"SL$i\" xtargets=\"";
	if (ref($alg->[$i]->{src}) eq 'ARRAY'){
	    print join(' ',@{$alg->[$i]->{src}});
	}
	print ';';
	if (ref($alg->[$i]->{trg}) eq 'ARRAY'){
	    print join(' ',@{$alg->[$i]->{trg}});
	}
	print "\" />\n";
    }
    print "</linkGrp>\n</cesAlign>\n";
}




################################################################################





sub best_align{
    my ($srcfile,$trgfile,$srcdata,$trgdata,$first,$last,$alg)=@_;

    my %types;
    align_srt($srcdata,$trgdata,$alg,\%types);
    my $bestratio = ($types{nonempty}+1)/($types{empty}+1);

    print STDERR "\nratio = " if $VERBOSE;
    print STDERR ($types{nonempty}+1)/($types{empty}+1) if $VERBOSE;
    print STDERR "\n" if $VERBOSE;

    my @sortfirst = sort {$$first{$b} <=> $$first{$a} } keys %{$first};
    my @sortlast  = sort {$$last{$b} <=> $$last{$a} } keys %{$last};

    if ($MAX_MATCHES){
	@sortfirst = splice(@sortfirst,0,$MAX_MATCHES) if (@sortfirst > $MAX_MATCHES);
	@sortlast = splice(@sortlast,0,$MAX_MATCHES) if (@sortlast > $MAX_MATCHES);
    }

    my $standard = $bestratio;

    foreach my $sf (@sortfirst){
	foreach my $lf (@sortlast){

	    my @anchor = ($sf,$lf);

	    ## use only the first and the last one
	    if ($VERBOSE){
		print STDERR "use $anchor[0] and $anchor[1] as reference\n";
	    }

	    ## compute slope and offset for this movie
	    my ($slope,$offset) = ComputeOffset(\@anchor,$srcdata,$trgdata);
	    print STDERR "time factor: $slope - offset: $offset\n" if $VERBOSE;
	    if ($slope<=0){
		print STDERR "strange scaling factor -> ignore\n";
		next;
	    }
	    ## re-scale source language subtitles
#	    set_sent_times($srcdata,$slope,$offset);
	    synchronize($srcdata,$slope,$offset);

	    my %types=();
	    my @newalg=();
	    align_srt($srcdata,$trgdata,\@newalg,\%types);
	    print STDERR "ratio = " if $VERBOSE;
	    print STDERR ($types{nonempty}+1)/($types{empty}+1) if $VERBOSE;
	    if (($types{nonempty}+1)/($types{empty}+1) > $bestratio){
		@{$alg} = @newalg;
		$bestratio = ($types{nonempty}+1)/($types{empty}+1);
		print STDERR " ---> best!" if $VERBOSE;
	    }
	    print STDERR "\n" if $VERBOSE;
	}
    }
    print STDERR "\n" if $VERBOSE;
    if ($bestratio < 2){
	if ($FALLBACK && (-e $UPLUG)){
	    print STDERR "best ratio < 2 --> fall back to $FALLBACK!\n";
	    print `$UPLUG $FALLBACK -src $srcfile -trg $trgfile`;
	    exit;
	}
    }
    return ($bestratio,$standard);
}



sub standard_align{
    my ($srcdata,$trgdata,$first,$last,$alg)=@_;

    my %types;
    align_srt($srcdata,$trgdata,$alg,\%types);

    if ($types{empty}*2 > $types{nonempty}){

	if (keys %{$first} && keys %{$last}){
	    &use_anchor_points($srcdata,$trgdata,$first,$last);
	}
	@{$alg} = ();
	&align_srt($srcdata,$trgdata,$alg);
    }
    return ($types{nonempty}+1)/($types{empty}+1);
}



sub cognate_align{
    my ($srcfile,$trgfile,$srcdata,$trgdata,$first,$last,$alg)=@_;
    my $best;
    for (my $c=1;$c>$COGNATE_RANGE;$c-=0.05){
	$BEST_ALIGN=1;
	$USE_COGNATES=$c;
	print STDERR "use c=$USE_COGNATES";
	&parse_bitext($srcfile,$trgfile,$srcdata,$trgdata,$first,$last);
	my @newalg=();
	my $new=best_align($srcfile,$trgfile,
			   $srcdata,$trgdata,
			   $first,$last,\@newalg);
	if ($new>$best){
	    print STDERR "--> best ($new)";
	    $best=$new;
	    @{$alg}=@newalg;
	}
	print STDERR "\n";
    }
    return $best;
}





sub align_srt{
    my ($src,$trg,$alg,$types)=@_;

    my %srcalign = ();
    my %trgalign = ();

    my %DIST;
    $DIST{0}{0} = 1;
    $DIST{0}{1} = 1;
    $DIST{1}{0} = 1;
#    $DIST{1}{1} = 1;
    $DIST{0}{2} = 1;
    $DIST{2}{0} = 1;
#    $DIST{1}{2} = 1;
#    $DIST{2}{1} = 1;
#    $DIST{0}{3} = 1;
#    $DIST{3}{0} = 1;
#    $DIST{1}{3} = 1;
#    $DIST{3}{1} = 1;
#    $DIST{2}{3} = 1;
#    $DIST{3}{2} = 1;


    my $s = 0;
    my $t = 0;

    while($s<=$#{$src} && $t<=$#{$trg}) {

	my ($srcbefore,$trgbefore,
	    $srcafter,$trgafter,
	    $common,$not_common) = &overlap($src->[$s]->{start},
					    $src->[$s]->{end},
					    $trg->[$t]->{start},
					    $trg->[$t]->{end});

	my $idx=$#{$alg}+1;

	if ($common<=0 && $srcbefore){
#	if ($srcbefore > $common+$srcafter){
	    $alg->[$idx]->{trg}=[];
	    $alg->[$idx]->{src}->[0]=$src->[$s]->{id};
	    $s++;
	    $$types{'1:0'}++;
	    $$types{empty}++;
	    next;
	}

	if ($common<=0 && $trgbefore){
#	if ($trgbefore > $common+$trgafter){
	    $alg->[$idx]->{src}=[];
	    $alg->[$idx]->{trg}->[0]=$trg->[$t]->{id};
	    $t++;
	    $$types{'0:1'}++;
	    $$types{empty}++;
	    next;
	}

	
	my %cost=();

	foreach my $ds (keys %DIST){
	    next if $s+$ds>$#{$src};
	    foreach my $dt (keys %{$DIST{$ds}}){
		next if $t+$dt>$#{$trg};
		next if ($src->[$s]->{start} >= $trg->[$t+$dt]->{end});
		next if ($trg->[$t]->{start} >= $src->[$s+$ds]->{end});
		my ($srcbefore,$trgbefore,
		    $srcafter,$trgafter,
		    $common,$not_common) = &overlap($src->[$s]->{start},
						    $src->[$s+$ds]->{end},
						    $trg->[$t]->{start},
						    $trg->[$t+$dt]->{end});
		$cost{"$ds-$dt"}=$not_common;
	    }
	}
	    
	if (keys %cost){
	    my ($best) = sort {$cost{$a} <=> $cost{$b}} keys %cost;
	    my ($ds,$dt)=split(/\-/,$best);
	    my $idx=$#{$alg}+1;
	    foreach (0..$ds){
		push(@{$alg->[$idx]->{src}},$src->[$s+$_]->{id});
	    }
	    foreach (0..$dt){
		push(@{$alg->[$idx]->{trg}},$trg->[$t+$_]->{id});
	    }
	    my $key = join(':',$ds+1,$dt+1);
	    $$types{$key}++;
	    $$types{nonempty}++;
	    $s+=$ds+1;
	    $t+=$dt+1;
	}
#	else{
#	    if ($VERBOSE){
#		print STDERR "s[0]: $src->[$s]->{start}->$src->[$s]->{end}\n";
#		print STDERR "s[1]: $src->[$s+1]->{start}->$src->[$s+1]->{end}\n";
#		print STDERR "s[2]: $src->[$s+2]->{start}->$src->[$s+2]->{end}\n";
#		print STDERR "t[0]: $trg->[$t]->{start}->$trg->[$t]->{end}\n";
#		print STDERR "t[1]: $trg->[$t+1]->{start}->$trg->[$t+1]->{end}\n";
#		print STDERR "t[2]: $trg->[$t+2]->{start}->$trg->[$t+2]->{end}\n";
#		print STDERR "strange ...\n";
#	    }
#	}
    }


    while($s<=$#{$src}) {
	my $idx=$#{$alg}+1;
	$alg->[$idx]->{trg}=[];
	$alg->[$idx]->{src}->[0]=$src->[$s]->{id};
	$s++;
	$$types{'1:0'}++;
	$$types{empty}++;
    }
    while($t<=$#{$trg}) {
	my $idx=$#{$alg}+1;
	$alg->[$idx]->{src}=[];
	$alg->[$idx]->{trg}->[0]=$trg->[$t]->{id};
	$t++;
	$$types{'1:0'}++;
	$$types{empty}++;
    }
}


sub overlap{
    my ($srcstart,$srcend,$trgstart,$trgend) = @_;

#    if ($srcstart>$trgend){return -1;}
#    if ($trgstart>$srcend){return -1;}

#    print "$srcstart --> $srcend\n";
#    print "$trgstart --> $trgend\n";

    my $not_common=0;
    my $common_start=$srcstart;
    my $srcbefore=0;
    my $trgbefore=0;
    my $srcafter=0;
    my $trgafter=0;


    if ($srcstart<$trgstart){
	$srcbefore=$trgstart-$srcstart;
	$not_common+=$srcbefore;
	$common_start=$trgstart;	
    }
    else{
	$trgbefore=$srcstart-$trgstart;
	$not_common+=$trgbefore;
    }

    my $common_end=$srcend;
    if ($srcend<$trgend){
	$trgafter=$trgend-$srcend;
	$not_common+=$trgafter;
    }
    else{
	$srcafter=$srcend-$trgend;
	$not_common+=$srcafter;
	$common_end=$trgend;
    }

    my $common = $common_end - $common_start;

#    print STDERR "    common: $common\n";
#    print STDERR "not common: $not_common\n";

    return ($srcbefore,$trgbefore,
	    $srcafter,$trgafter,
	    $common,$not_common);

}





sub ReadDictionary{
    my ($dic,$file,$inverse)=@_;
    if (-e $file){
	if ($file=~/\.gz$/){
	    open DIC,"gzip -cd < $file |" || 
		die "cannot open dictionary file $file!\n";
	}
	else{
	    open DIC,"< $file " || die "cannot open dictionary file $file!\n";
	}
	binmode(DIC,":utf8");
	while (<DIC>){
	    chomp;
	    my ($src,$trg) = split(/\s/);
	    $inverse ? $$dic{$trg}{$src}++ : $$dic{$src}{$trg}++;
	}
    }
}




sub parse_bitext{
    my ($srcfile,$trgfile,$srcdata,$trgdata,$first,$last)=@_;


    ## first and last sentences (size = WINDOW)
    my $srcfirst=[];
    my $srclast=[];
    my $trgfirst=[];
    my $trglast=[];

    my ($src_fh,$src_ph) = init_parser($srcfile,$srcdata);
    my ($trg_fh,$trg_ph) = init_parser($trgfile,$trgdata);

    $srcfreq = $src_ph->{WORDFREQ};
    $trgfreq = $trg_ph->{WORDFREQ};

    my $src_count=0;
    my $trg_count=0;

    print STDERR "\n" if $VERBOSE;

    ## parse through source language text
    while (&ReadNextSentence($src_fh,$src_ph)){
#	next unless (@{$src_ph->{WORDS}});
	if (@{$srcfirst} < $WINDOW ){
	    my $idx = scalar @{$srcfirst};
	    if (@{$src_ph->{WORDS}}){
		@{$srcfirst->[$idx]} = @{$src_ph->{WORDS}->[-1]};
	    }
	    else{@{$srcfirst->[$idx]}=();}
	}
	my $idx = scalar @{$srclast};
	if (@{$src_ph->{WORDS}}){
	    @{$srclast->[$idx]} = @{$src_ph->{WORDS}->[-1]};
	    @{$src_ph->{WORDS}->[-1]} = undef;
	}
	else{@{$srclast->[$idx]}=();}
	if (@{$srclast} > $WINDOW ){
	    shift (@{$srclast});
	}
	$src_count++;
    }

    ## parse through target language text
    while (ReadNextSentence($trg_fh,$trg_ph)){
#	next unless (@{$trg_ph->{WORDS}});
	if (@{$trgfirst} < $WINDOW ){
	    my $idx = scalar @{$trgfirst};
	    if (@{$trg_ph->{WORDS}}){
		@{$trgfirst->[$idx]} = @{$trg_ph->{WORDS}->[-1]};
	    }
	    else{@{$trgfirst->[$idx]}=();}
	}
	my $idx = scalar @{$trglast};
	if (@{$trg_ph->{WORDS}}){
	    @{$trglast->[$idx]} = @{$trg_ph->{WORDS}->[-1]};
	    @{$trg_ph->{WORDS}->[-1]} = undef;
	}
	else{@{$trglast->[$idx]}=();}
	if (@{$trglast} > $WINDOW ){
	    shift (@{$trglast});
	}
	$trg_count++;
    }


    # find matches in initial windows
#    my %first=();
    foreach my $s (0..$WINDOW-1){
	foreach my $t (0..$WINDOW-1){
	    if (my $score = find_match($srcfirst->[$s],$trgfirst->[$t])){
#		$score/=($s+$t)+2;
		print STDERR "in $s:$t ($score)\n" if $VERBOSE;
#		$$first{"$s:$t"}=$score;
		$$first{"$s:$t"}=1/($s+$t+2);
	    }
	}
    }

    # find matches in final windows
#    my %last=();
    foreach my $s (0..$WINDOW-1){
	foreach my $t (0..$WINDOW-1){
	    if (my $score = find_match($srclast->[$s],$trglast->[$t])){
		my $src = $src_count-$WINDOW+$s;
		my $trg = $trg_count-$WINDOW+$t;
#		$score/=(2*$WINDOW-$s-$t);
		print STDERR "in $src:$trg ($score)\n" if $VERBOSE;
#		$$last{"$src:$trg"}=$score;
		$$last{"$src:$trg"}=1/(2*$WINDOW-$s-$t);
	    }
	}
    }
}




sub use_anchor_points{

    my ($srcdata,$trgdata,$first,$last)=@_;

    my @sortfirst = sort {$$first{$b} <=> $$first{$a} } keys %{$first};
    my @sortlast  = sort {$$last{$b} <=> $$last{$a} } keys %{$last};

    ## I need at least 2 reference points!

    if (@sortfirst && @sortlast){
	my @fixpoints = ($sortfirst[0],$sortlast[0]);

	## use only the first and the last one
	if ($VERBOSE){
	    print STDERR "use $fixpoints[0] and $fixpoints[1] as reference\n";
	}

	## compute slope and offset for this movie
	my ($slope,$offset) = ComputeOffset(\@fixpoints,$srcdata,$trgdata);
	print STDERR "time factor: $slope - offset: $offset\n" if $VERBOSE;
	if ($slope<=0){
	    print STDERR "strange scaling factor -> ignore\n";
	    delete $last->{$sortlast[0]};
	    return use_anchor_points($srcdata,$trgdata,$first,$last);
	}
	## re-scale source language subtitles
#	set_sent_times($srcdata,$slope,$offset);
	synchronize($srcdata,$slope,$offset);
    }
}


sub fit_hard_boundaries{
    my ($hardstr,$src,$trg)=@_;
    my @pairs = split(/\+/,$hardstr);

    my %SrcIdx=();
    foreach my $i (0..$#{$src}){
	$SrcIdx{$src->[$i]->{id}}=$i;
    }
    my %TrgIdx=();
    foreach my $i (0..$#{$trg}){
	$TrgIdx{$trg->[$i]->{id}}=$i;
    }

    my @matches=();
    foreach (@pairs){
	my ($src,$trg) = split(/\:/);
	push (@matches,$SrcIdx{$src}.':'.$TrgIdx{$trg});
    }

    if (@matches > 1){

	## use only the first and the last one
	@matches=($matches[0],$matches[-1]);
	if ($VERBOSE){
	    print STDERR "use $matches[0] and $matches[-1] as reference\n";
	}

	## compute slope and offset for this movie
	my ($slope,$offset) = ComputeOffset(\@matches,$src,$trg);
	print STDERR "time factor: $slope - offset: $offset\n" if $VERBOSE;
	while (($slope<=0) && (@matches > 1)){
	    print STDERR "strange scaling factor -> ignore\n";
	    pop(@matches);
	    return 0 if (@matches==0);
	    ($slope,$offset) = ComputeOffset(\@matches,$src,$trg);
	    print STDERR "time factor: $slope - offset: $offset\n" if $VERBOSE;
	}
	## re-scale source language subtitles
#	set_sent_times($src,$slope,$offset);
	synchronize($src,$slope,$offset);
    }
}


sub ComputeOffset{
    my ($matches,$srcdata,$trgdata) = @_;

    my @params=();
    return AverageOffset(\@params) unless (ref($srcdata) eq 'ARRAY');
    return AverageOffset(\@params) unless (ref($trgdata) eq 'ARRAY');

    foreach my $i (0..$#{$matches}){
	foreach my $j ($i+1..$#{$matches}){
	    my ($s1,$t1) = split(/:/,$$matches[$i]);
	    my ($s2,$t2) = split(/:/,$$matches[$j]);

	    next unless (exists $srcdata->[$s1]);
	    next unless (exists $srcdata->[$s2]);
	    next unless (exists $trgdata->[$t1]);
	    next unless (exists $trgdata->[$t2]);

#	    my $x1=$srcdata->[$s1]->{start};
#	    my $y1=$trgdata->[$t1]->{start};
#	    my $x2=$srcdata->[$s2]->{start};
#	    my $y2=$trgdata->[$t2]->{start};

	    my $x1=$srcdata->[$s1]->{end};
	    my $y1=$trgdata->[$t1]->{end};
	    my $x2=$srcdata->[$s2]->{end};
	    my $y2=$trgdata->[$t2]->{end};

#	    print STDERR "fit line from $x1:$y1 to $x2:$y2\n" if $VERBOSE;
	    my ($slope,$offset)=FitLine($x1,$y1,$x2,$y2);
#	    print STDERR "time factor=$slope, offset=$offset\n" if $VERBOSE;
	    push (@params,($slope,$offset));
	}
    }
    return AverageOffset(\@params);
}

sub FitLine{
    my ($x1,$y1,$x2,$y2)=@_;

    if ($x1-$x2 != 0){
	my $a = ($y1-$y2)/($x1-$x2);
	my $b = $y2-$x2*$a;
	return ($a,$b);
    }
    return (1,0);
}


sub AverageOffset{
    my $data=shift;

    my $sum1=0;
    my $sum2=0;

    my $total=($#{$data}+1)/2;

    while (@{$data}){
	$sum1+=shift(@{$data});
	$sum2+=shift(@{$data});
    }
    if ($total>0){
	return ($sum1/$total,$sum2/$total);
    }
    return (1,0);
}




sub FindWordMatches{
    my ($src,$srcstart,$srcend,$trg,$trgstart,$trgend)=@_;

    foreach my $d (0..$WINDOW){
	foreach my $i (0..$WINDOW){
	    my $s = $srcstart+$i;
	    my $t = $trgstart+$i+$d;
	    if ($s <= $srcend && $t <= $trgend){
		if (find_match($src->[$s],$trg->[$t])){
		    foreach ($srcstart..$s){$src->[$_]=undef;}
		    foreach ($trgstart..$t){$trg->[$_]=undef;}
		    return ($s,$t);
		}
	    }
	    $s = $srcstart+$i+$d;
	    $t = $trgstart+$i;
	    if ($s <= $srcend && $t <= $trgend){
		if (find_match($src->[$s],$trg->[$t])){
		    foreach ($srcstart..$s){$src->[$_]=undef;}
		    foreach ($trgstart..$t){$trg->[$_]=undef;}
		    return ($s,$t);
		}
	    }
	}
    }

    return ($srcend,$trgend);
}




sub init_parser{
    my $file=shift;
    my $data=shift;

    my $fh = new IO::File;
    if ($file=~/\.gz$/){
	$fh->open("gzip -cd < $file |") || die "cannot open $file!\n";
    }
    else{
	$fh->open("<$file") || die "cannot open $file!\n";
    }
#    binmode($fh,":utf8");

    my $p = new XML::Parser(Handlers => {Start => \&xml_start_tag,
					 End   => \&xml_end_tag,
					 Char  => \&xml_char_data});
    my $ph = $p->parse_start;
    $ph->{SENTENCES} = $data;
    $ph->{WORDS} = [];
    $ph->{WORDFREQ} = {};
    return ($fh,$ph);
}




sub ReadNextSentence{
    my ($FH,$parser) = @_;

    $parser->{SENTENCE_END} = 0;

    while (not $parser->{SENTENCE_END}){
	my $line = <$FH>;                    # read next line
	if (not $line){                      # end of file?
	    $parser->{SENTENCE_END}=1;       # --> stop
	    return 0;
	}
	else{
	    $parser->parse_more($line);      # else: parse line
	}
    }
    return 1;
}




sub xml_start_tag{
    my $p=shift;
    my $e=shift;
    my %a=@_;

    if ($e eq 's'){
	if (ref($p->{SENTENCES}) ne 'ARRAY'){
	    $p->{SENTENCES}=[];
	}
	my $idx = $#{$p->{SENTENCES}}+1;
	$p->{SENTENCES}->[$idx]={};
	$p->{SENTENCES}->[$idx]->{id}=$a{id};
	$p->{SENTENCES}->[$idx]->{start_pos} = $p->{POSITION};
#	print "current sentence: $a{id}\n";
    }
    elsif ($e eq 'w'){
	$p->{WORD} = 1;
    }
    elsif ($e eq 'time'){
	my $time=time2sec($a{value});
	if ((not $a{value}) && (not $time)){
	    print STDERR "No time value found ($a{value} = $time)\n";
	    return 0;
	}
	## first time tag seen in the sentence
	if (not defined $p->{SENTENCES}->[-1]->{first}){
	    $p->{SENTENCES}->[-1]->{first}=$time;
	    $p->{SENTENCES}->[-1]->{first_pos}=$p->{POSITION};
	}
	## last time tag seen in the sentence
	## (only when position is higher than first!)
	else{
	    if ($p->{POSITION} > $p->{SENTENCES}->[-1]->{first_pos}){
		$p->{SENTENCES}->[-1]->{last}=$time;
		$p->{SENTENCES}->[-1]->{last_pos}=$p->{POSITION};
	    }
	}
    }
}


sub xml_end_tag{
    my $p=shift;
    my $e=shift;

    if ($e eq 's'){
	$p->{SENTENCES}->[-1]->{end_pos} = $p->{POSITION};
	$p->{SENTENCE_END}=1;
    }
    elsif ($e eq 'w'){
	$p->{WORD} = 0;
    }
}

sub xml_char_data{
    my $p=shift;
    my $c=shift;
    if ($p->{WORD}){
	$p->{POSITION}+=length($c);

	if (ref($p->{WORDS}) eq 'ARRAY'){
	    my $idx = $#{$p->{SENTENCES}};
	    push (@{$p->{WORDS}->[$idx]},$c);
	    $p->{WORDFREQ}->{$c}++;
	}
    }
}


sub time2sec{
    my $time=shift;
    my ($h,$m,$s,$ms)=split(/[^0-9\-]/,$time);
    my $sec = 3600*$h+60*$m+$s+$ms/1000;
    return $sec;
}












sub find_match{
    if ($USE_DICTIONARY){
	if (my $ret=dictionary(@_)){
	    return $ret;
	}
    }
    if ($USE_IDENTICAL){
	if (my $ret=identical(@_,$USE_IDENTICAL,$CHAR_SET,$TOK_LEN)){
	    return $ret;
	}
    }
    if ($USE_COGNATES){
	if (my $ret=cognates(@_,$MINLENGTH,$USE_COGNATES)){
	    return $ret;
	}
    }
    return 0;
}




sub identical_old{
    my ($src,$trg,$minlength)=@_;

    ## make lower case version of first word
    ## to avoid problems with the 'only upper case words'
    ## (quite ad-hoc)
    if ($UPPER_CASE){
	$$src[0] = lc($$src[0]);
	$$trg[0] = lc($$trg[0]);
    }

    my %src_words=();
    my %trg_words=();
    foreach (@{$src}){
	$src_words{$_}++;
    }
    foreach (@{$trg}){
	$trg_words{$_}++;
    }

    foreach (keys %src_words){
	if (length($_)<=$minlength){next;}
	if ($UPPER_CASE){if ($_!~/^\p{Lu}/){next;}}
	if (defined $trg_words{$_}){
	    print STDERR "found identical string '$_' " if $VERBOSE;
	    return 1;
	}
    }
    return 0;
}



sub identical{
    my ($src,$trg,$minlength,$CHAR_SET,$TOK_LEN)=@_;

    ## make lower case version of first word
    ## to avoid problems with the 'only upper case words'
    ## (quite ad-hoc)
    if ($UPPER_CASE){
	$$src[0] = lc($$src[0]);
	$$trg[0] = lc($$trg[0]);
    }

    my %src_words=();
    my %trg_words=();
    foreach (0..$#{$src}){
	push(@{$src_words{$$src[$_]}},$_);
    }
    foreach (0..$#{$trg}){
	push(@{$trg_words{$$trg[$_]}},$_);
    }

    my $bestmatch = '';
    my $minsrcfreq = 1;
    my $mintrgfreq = 1;

    foreach my $w (keys %src_words){
	if ($CHAR_SET){if ($w!~/^$CHAR_SET+$/){next;}}
	if ($UPPER_CASE){if ($w!~/^\p{Lu}/){next;}}
	if ($TOK_LEN){if (length($w)<$TOK_LEN){next;}}
	if (defined $trg_words{$w}){

	    my $match = $w;
	    $minsrcfreq = $srcfreq->{$w};
	    $mintrgfreq = $trgfreq->{$w};

	    # 2 identical words found! now check even their neighbors!

	    foreach my $i (@{$src_words{$w}}){
		foreach my $j (@{$trg_words{$w}}){
		    my $spos = $i;
		    my $tpos = $j;
		    while ($spos < $#{$src} && $tpos < $#{$trg}){
			$spos++;
			$tpos++;
			last if ($$src[$spos] ne $$trg[$tpos]);
			last if ($UPPER_CASE && $$src[$spos]!~/^\p{Lu}/);
			last if ($CHAR_SET && $$src[$spos]!~/^$CHAR_SET+$/);
			last if ($TOK_LEN && length($$src[$spos])<$TOK_LEN);
			$match .= ' '.$$src[$spos];
			if ($srcfreq->{$$src[$spos]} > $minsrcfreq){
			    $minsrcfreq = $srcfreq->{$$src[$spos]};
			}
			if ($trgfreq->{$$trg[$spos]} > $mintrgfreq){
			    $mintrgfreq = $trgfreq->{$$trg[$spos]};
			}
		    }
		}
	    }
	    if (length($match)>length($bestmatch)){
		$bestmatch = $match;
	    }
	}
    }
    my $length = length($bestmatch);
    if ($length > $minlength){
	print STDERR "found identical string '$bestmatch' " if $VERBOSE;
	if ($USE_WORDFREQ){
	    if ($minsrcfreq+$mintrgfreq){
		$length/=($minsrcfreq+$mintrgfreq);
	    }
	}
	return $length;
    }
    return 0;
}





sub cognates{

    my ($src,$trg,$minlength,$minscore)=@_;

    ## make lower case version of first word
    ## to avoid problems with the 'only upper case words'
    ## (quite ad-hoc)
    if ($UPPER_CASE){
	$$src[0] = lc($$src[0]);
	$$trg[0] = lc($$trg[0]);
    }

    my %src_words=();
    my %trg_words=();
    foreach (@{$src}){
	$src_words{$_}++;
    }
    foreach (@{$trg}){
	$trg_words{$_}++;
    }

    foreach my $s (keys %src_words){
	my $s_len = length($s);
	if ($s_len < $minlength){next;}
	if ($UPPER_CASE){if ($s!~/^\p{Lu}/){next;}}
	foreach my $t (keys %trg_words){
	    my $t_len = length($t);
	    if ($t_len < $minlength){next;}
	    if ($UPPER_CASE){if ($t!~/^\p{Lu}/){next;}}
	    if ($s eq $t){
		print STDERR "found cognate '$s' - '$t' " if $VERBOSE;
		return 1;
	    }
	    if ($s_len > $t_len){
		if ($t_len/$s_len < $minscore){next;}
		if (LCS($s,$t)/$s_len > $minscore){
		    print STDERR "found cognate '$s' - '$t' " if $VERBOSE;
		    return LCS($s,$t)/$s_len;
		}
	    }
	    else{
		if ($s_len/$t_len < $minscore){next;}
		if (LCS($s,$t)/$t_len > $minscore){
		    print STDERR "found cognate '$s' - '$t' " if $VERBOSE;
		    return LCS($s,$t)/$t_len;
		}
	    }
	}
    }
    return 0;
}



sub LCS {
    my ($src,$trg)=@_;
    my (@l,$i,$j);
    my @src_let=split(//,$src);		# split string into char
    my @trg_let=split(//,$trg);
    unshift (@src_let,'');
    unshift (@trg_let,'');
  for ($i=0;$i<=$#src_let;$i++){                # initialize the matrix
      $l[$i][0]=0;
  }
  for ($i=0;$i<=$#trg_let;$i++){
      $l[0][$i]=0;
  }                                                       # weight function is

    for $i (1..$#src_let){
	for $j (1..$#trg_let){
	    if ($src_let[$i] eq $trg_let[$j]){
		$l[$i][$j]=$l[$i-1][$j-1]+1;
	    }
	    else{
		if ($l[$i][$j-1]>$l[$i-1][$j]){
		    $l[$i][$j]=$l[$i][$j-1];
		}
		else{
		    $l[$i][$j]=$l[$i-1][$j];
		}
	  }
	}
    }
    return $l[$#src_let][$#trg_let];
}





sub dictionary{
    my ($src,$trg)=@_;

    my %src_words=();
    my %trg_words=();
    foreach my $w (@{$src}){
	$src_words{$w}++;
    }
    foreach my $w (@{$trg}){
	$trg_words{$w}++;
    }

    foreach my $s (keys %src_words){
	if (exists $DIC{$s}){
	    foreach my $t (keys %trg_words){
		if (exists $DIC{$s}{$t}){
		    print STDERR "found in dic '$s' - '$t' " if $VERBOSE;
		    return 1;
		}
	    }
	}
    }

    return 0;
}






sub synchronize{
    my $sent=shift;
    my $scale=shift;
    my $offset=shift;
    foreach my $s (0..$#{$sent}){
	$sent->[$s]->{start} = $scale * $sent->[$s]->{start}+$offset;
	$sent->[$s]->{end} = $scale * $sent->[$s]->{end}+$offset;
    }
}

sub set_sent_times{
    my $sent=shift;
    my $scale=shift;
    my $offset=shift;

    if (not $scale){$scale=1;}

    ## if the first time tag is at the end of the sentence
    ## ---> move it to be the last!

    foreach my $s (0..$#{$sent}){
	if (defined $sent->[$s]->{first}){
	    if ($sent->[$s]->{first_pos} == $sent->[$s]->{end_pos}){
		if (not defined $sent->[$s]->{last}){
		    $sent->[$s]->{last} = $sent->[$s]->{first};
		    $sent->[$s]->{last_pos} = $sent->[$s]->{first_pos};
		}
		delete $sent->[$s]->{first};
		delete $sent->[$s]->{first_pos};
	    }
	}
    }



    foreach my $s (0..$#{$sent}){

	## no first time tag found in this sentence
	## --> copy end time from previous sentence
	if (not defined $sent->[$s]->{first}){
	    $sent->[$s]->{first_pos}=$sent->[$s]->{start_pos};
	    if ($s>0){
		$sent->[$s]->{first}=$sent->[$s-1]->{end};
	    }
	    else{
		$sent->[$s]->{first}=0;
	    }
	}

	## no last time tag found?
	## copy first from following sentences
	if (not defined $sent->[$s]->{last}){
	    my $x=$s+1;
	    while ($x<$#{$sent}){
		if (defined $sent->[$x]->{first}){
		    $sent->[$s]->{last}=$sent->[$x]->{first};
		    $sent->[$s]->{last_pos}=$sent->[$x]->{first_pos};
		    last;
		}
		if (defined $sent->[$x]->{last}){
		    $sent->[$s]->{last}=$sent->[$x]->{last};
		    $sent->[$s]->{last_pos}=$sent->[$x]->{last_pos};
		    last;
		}
		$x++;
	    }
	}

	## first time tag is not at sentence start!
	## --> interpolate
	if ($sent->[$s]->{first_pos} != $sent->[$s]->{start_pos}){
	    my $char=$sent->[$s]->{last_pos}-$sent->[$s]->{first_pos};
	    my $time=$sent->[$s]->{last}-$sent->[$s]->{first};

	    if (not $char){
		print STDERR "strange?!?\n";
	    }

	    my $diff=$sent->[$s]->{first_pos}-$sent->[$s]->{start_pos};

	    if ($char*$diff){
		$sent->[$s]->{first} = $sent->[$s]->{first}-$time/$char*$diff;
	    }
	    else{
		$sent->[$s]->{first} = $sent->[$s]->{first}-0.0000000001;
	    }
	}

	## last time tag is not at sentence end!
	## --> interpolate
	if ($sent->[$s]->{last_pos} != $sent->[$s]->{end_pos}){
	    my $char=$sent->[$s]->{last_pos}-$sent->[$s]->{first_pos};
	    my $time=$sent->[$s]->{last}-$sent->[$s]->{first};

	    if (not $char){
		print STDERR "strange?!?\n";
	    }

	    my $diff=$sent->[$s]->{end_pos}-$sent->[$s]->{last_pos};
	    if ($char*$diff){
		$sent->[$s]->{last} = $sent->[$s]->{last} + $time/$char*$diff;
	    }
	    else{
		$sent->[$s]->{last} = $sent->[$s]->{last} + 0.0000000001;
	    }
	}

	$sent->[$s]->{start} = $scale * $sent->[$s]->{first}+$offset;
	$sent->[$s]->{end} = $scale * $sent->[$s]->{last}+$offset;
    }

    ## take care of some special cases where the time slot is 0
    ## (or even negative)
    ## --> just change the start time to be a milisecond before end time

    foreach my $s (0..$#{$sent}){
	if ($sent->[$s]->{start} >= $sent->[$s]->{end}){
	    $sent->[$s]->{start} = $sent->[$s]->{end} - 0.00000001;
	}
    }

}





## old parse sub-routine ...

sub parse_srt{
    my $file=shift;
    my $data=shift;

    my $fh = new IO::File;
    if ($file=~/\.gz$/){
	$fh->open("gzip -cd < $file |") || die "cannot open $file!\n";
    }
    else{
	$fh->open("<$file") || die "cannot open $file!\n";
    }

    my $p = new XML::Parser(Handlers => {Start => \&xml_start_tag,
				      End   => \&xml_end_tag,
				      Char  => \&xml_char_data});

    $p->{SENTENCES} = $data;

    $p->parse($fh);
    $fh->close;

    if (ref($p->{SENTENCES}) ne 'ARRAY'){return 0;}
}


1;

__END__

=head1 AUTHOR

Jörg Tiedemann, L<https://bitbucket.org/tiedemann>

=head1 TODO

Add length-based option (using time slot length correlations) also in combination with character length.

=head1 BUGS AND SUPPORT

Please report any bugs or feature requests to
L<https://bitbucket.org/tiedemann/subalign>.

=head1 SEE ALSO

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Jörg Tiedemann.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.


THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
