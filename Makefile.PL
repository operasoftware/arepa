use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'                => 'Arepa',
    'VERSION_FROM'        => 'lib/Arepa.pm',
    'PREREQ_PM'           => {'Test::Deep'                 => 0,
                              'DBD::SQLite'                => 0,
                              'File::chmod'                => 0,
                              'Parse::Debian::PackageDesc' => 0,
                              'Config::Tiny'               => 0},
    'ABSTRACT_FROM'       => 'lib/Arepa.pm',
    'AUTHOR'              => 'Esteban Manchado Velázquez <estebanm@opera.com>',
);
