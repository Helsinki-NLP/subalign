
# The subalign package

A collection of scripts and tools for procesing movie subtitles. The
main focus is on converting and aligning subtitles in several
languages to make them useful for machine translation development.


## Installation

```
perl Makefile.PL
make all
make install
```


## srt2xml

The script can be used to convert subtitles in srt-format to XML
with sentence boundaries and basic markup.
It also performs a conversion between character encoding
and performs simple tokenisation as well.

Remember to remove DOS-style return characters before applying the script
(use `dos2unix` or similar tools).

```
srt2xml [OPTIONS] < input.srt > output.xml
```

OPTIONS

```
 -e encoding ......... specify the character encoding of the SRT file
 -l lang-id .......... use non-breaking prefixes for the given language
 -r filename ......... save an untokenized version in <filename>
 -s .................. always start a new sentence at each time frame
```


## srtalign

Aligns XML files with time stamps coming from subtitle files.
Use the `srt2xml` above to create such XML files from SRT files.

```
 srtalign [OPTIONS] source-file.xml target-file.xml > aligned.xml
```

OPTIONS

```
 -S source-lang . source language ID
 -T target-lang . target language ID
 -c score ....... use cognates with LCSR>=score
 -r score-range . use cognates in a certain range 1..score and take best
 -l length ...... set minimal length of cognates (if used)
 -i len ......... use identical strings with length>=len
 -w size ........ set size for sliding window
 -d dic ......... use dictionary in file 'dic'
 -u ............. cognates/identicals that start with upper case only
 -r char_set .... define a set of characters to be used for matching
 -q ............. normalize length scores with (current) word frequencies
 -b ............. use "best" alignment (least empty alignments)
 -p nr .......... stop after <nr> candidates (when using -b)
 -m MAX ......... in "best" alignment: use only MAX first & MAX last
                  (default = 10; 0 = all)
 -f uplug-conf .. use fallback aligner if necessary
 -P ............. use proportion of non-empty alignments as scoring function
 -v ............. verbose output
```


The aligner uses the installed dictionaries if source language (-S)
AND target language (-T) are given AND a dictionary for the given
language pair is installed on the system (in the shared dir of the
Text::SRT::Align package). If a dictionary is found it also assumes
the best-align-mode (usually set by -b)

Cognates/identicals are used to set time ratio + time offset!
They define reference points that will be used to compute
* time scaling factor
* time offset
between source and target subtitles.

The script looks for these anchor points in the beginning and at the end
of each subtitle file (size of the windows defines how far from the start
and the end it'll look).

The similarity score is normalized by the distances from start/end
only two points will be used (one from the begiining and one from the end
with the best scores)


* `share/dic`:

This directory contains word alignment dictionaries obtained by
aligning the OpenSubtitles corpus from OPUS These
dictionaries can be used to improve sentence alignment
by synchronizing time stamps with the help of anchor
points found by matching dictionary entries with word
pairs in the subtitle pair


## mt2srt

A script for aligning time stamps to a translation of subtitles.
This tool can be used to fit sentence-level translations back to the original
time frames of a given subtitle file.


```
 mt2srt [OPTIONS] template.srt < input > output.srt
```

OPTIONS

```
 -i srt|xml .......... template format (default = srt)
 -o srt .............. output format (only srt is supported so far)
 -l length-penalty ... penalty for exceeding hard length limit (1 = no penalty = default)
 -L .................. relative length limit violation penalty (only in combination with -l)
 -s non-eos-penalty .. penalty for alignments that end within a sentence (1 = no penalty, default = 0.1)
 -x length ........... soft length limit (default = 30)
 -X length ........... hard length limit (default = 50)
 -n .................. add newlines using some heuristics
```


Subtitle blocks do not have to match the blocks in which individual
subtitle lines are shown. This script aligns the translated text to a
given template (typically the original source language SRT file) to
project the blocks to the translations. Sentences will be split and
merged in the best possible way to match the original
segmentation. The algorithm uses a length-based alignment algorithm
with some additional constraints.
