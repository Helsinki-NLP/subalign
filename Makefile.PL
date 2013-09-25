use inc::Module::Install;

name        'Text-SRT-Align';
abstract    'Convert and align translated movie subtitles';
author      'Joerg Tiedemann';
license     'gpl';
version     '0.2';

include     'Module::AutoInstall';

requires 'FindBin'     => 0;
requires 'Encode'      => 0;
requires 'File::BOM'   => 0;
requires 'Getopt::Std' => 0;
requires 'IO::File'    => 0;
requires 'IPC::Open3'  => 0;
requires 'XML::Parser' => 0;

# recommends 'File::ShareDir' => 0;
requires 'File::ShareDir' => 0;
requires 'Locale::Codes::Language' => 3.26;

auto_install;

install_script 'srt2xml';
install_script 'srtalign';
install_share;

WriteAll;
