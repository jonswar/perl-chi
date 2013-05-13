use ExtUtils::MakeMaker::Dist::Zilla::Develop;
WriteMakefile(
    NAME => 'CHI',
    test => { TESTS => 't/*.t xt/*/*.t' },
);
