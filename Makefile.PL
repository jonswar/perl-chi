use inc::Module::Install;

name 'CHI';
abstract 'Unified cache interface';
all_from 'lib/CHI.pm';
author 'Jonathan Swartz <swartz@pobox.com>';

perl_version '5.006';

build_requires 'Date::Parse' => 0;
build_requires 'Test::Class' => 0;
build_requires 'Test::Deep'  => 0;
build_requires 'Test::More'  => 0;

requires 'Any::Moose'                => '0.07';
requires 'Carp::Assert'              => '0.20';
requires 'Data::UUID'                => 0;
requires 'Digest::JHash'             => 0;
requires 'File::Spec'                => '0.80';
requires 'Hash::MoreUtils'           => 0;
requires 'List::MoreUtils'           => '0.13';
requires 'Module::Load::Conditional' => 0;
requires 'Storable'                  => 0;
requires 'Time::Duration'            => '1.06';
requires 'Time::Duration::Parse'     => '0.03';

license 'perl';

auto_install;

WriteAll;
