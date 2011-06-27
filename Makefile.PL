use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME                => 'Cafe::Application',
	AUTHOR              => 'Norbert Volf <norbert@volf.eu>',
	VERSION_FROM        => 'lib/Cafe/Application.pm',
	ABSTRACT_FROM       => 'lib/Cafe/Application.pm',
	PL_FILES            => {},
	EXE_FILES    => [ qw(bin/pgbuilder.pl) ],
	PREREQ_PM => {
		'Test::More' => 0,
		'Apache2::Const' => 0,
		'Apache2::Cookie' => 0,
		'Apache2::Log' => 0,
		'Apache2::Request' => 0,
		'Apache2::RequestIO' => 0,
		'Apache2::RequestRec' => 0,
		'Apache2::RequestUtil' => 0,
		'Apache::ConfigFile' => 0,
		'Apache::Session::Postgres' => 0,
		'Cache::Memcached' => 0,
		'Carp' => 0,
		'Cwd' => 0,
		'Data::Dumper' => 0,
		'DBD::Pg' => 0,
		'DBI' => 0,
		'Encode' => 0,
		'File::Path' => 0,
		'File::Spec' => 0,
		'File::Temp' => 0,
		'HTTP::Request' => 0,
		'JSON::XS' => 0,
		'LWP::UserAgent' => 0,
		'MIME::Base64' => 0,
		'POSIX' => 0,
		'Proc::PID::File' => 0,
		'RPC::XML' => 0,
		'RPC::XML::Parser' => 0,
		'Scalar::Util' => 0,
		'Sys::Syslog' => 0,
		'Template' => 0,
		'Text::Iconv' => 0,
	},
	dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean               => { FILES => 'Cafe-*' },
        postamble => { files => [
                "usr/share/cafe/templates/edit.tt2",
                "usr/share/cafe/templates/filter.tt2",
                "usr/share/cafe/templates/footer.tt2",
                "usr/share/cafe/templates/header.tt2",
                "usr/share/cafe/templates/list.tt2",
                "usr/share/cafe/templates/pages.tt2",
                "usr/share/cafe/templates/title.tt2",
                "usr/share/cafe/templates/toolbar.tt2",
        ] },
);

sub MY::postamble {
    my ($mm, %args) = @_;
    my $postamble = "";

    # add testcover target if available
    $postamble .= eval {
        require ExtUtils::MakeMaker::Coverage;
        ExtUtils::MakeMaker::Coverage::testcover();
    } || "";

    # install data files (in /etc, /usr/share, ...)
    # first, we must add a target in install::
    for my $makeline (@{ $mm->{RESULT} }) {
        $makeline =~ s/(install *::.+)\n/$1 priv_data_files\n/;
    }

    # then, declare the target with the files
    $postamble .= "\nINSTALL = install -D -p\n\npriv_data_files:\n";

    for my $file (@{ $args{files} }) {
        $postamble .= "\t\$(INSTALL) $file /$file\n";
    }

    return $postamble
}

