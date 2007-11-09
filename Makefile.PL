use inc::Module::Install;

name 'CHI';
all_from 'lib/CHI.pm';

build_requires 'Test::More';

requires 'File::Spec'            => 0;
requires 'List::MoreUtils'       => '0.21';
requires 'Storable'              => 0;
requires 'Sys::HostIP'           => '1.3.1';
requires 'Time::Duration::Parse' => '0.03';
requires 'URI::Escape'           => '3.28';

license 'perl';

auto_install;

WriteAll;

