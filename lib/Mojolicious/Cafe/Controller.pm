package Mojolicious::Cafe::Controller;

use utf8;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::Exception;
use DBI;
use POSIX qw(strftime locale_h setlocale LC_ALL);

sub dbh {    #Return instance of DBI class. The class is used as interface between database and Caramel application
	return ( shift->app->dbh(@_) );
}

sub restore_locale {    #Restore_locale locale from LIFO Ex
	my ($self) = shift;

	$self->{_local_locale} = [] if ( !defined( $self->{_local_locale} ) );
	if ( scalar( @{ $self->{_local_locale} } ) ) {
		my $locale = pop( @{ $self->{_local_locale} } );
		if ($locale) {
			$ENV{LANG}     = $locale;    #For TextDomain we mu set LANG also
			$ENV{LANGUAGE} = $locale;    #For TextDomain we mu set LANG also
			setlocale( LC_ALL, $locale );
			my $foo = setlocale(LC_ALL);
		}
	} else {
		Mojo::Exception->throw("Locale array is empty, when I want restore locale.");
	}
}

sub set_locale {                         #Set locale and save original locale to LIFO. If $locale is not defined use "C".
	my $self   = shift;
	my $locale = shift;
	my $orig;

	#As first local we must use "C" instead of locally defined
	if ( !exists( $self->{_begin} ) ) {
		$self->{_begin} = 1;
		$orig = "C";
	} else {
		$orig = setlocale(LC_ALL);
	}

	#Set new locale
	$locale = "C" unless ($locale);
	$ENV{LANG}     = $locale;    #For TextDomain we mu set LANG also
	$ENV{LANGUAGE} = $locale;    #For TextDomain we mu set LANG also
	setlocale( LC_ALL, $locale );

	#Keep previous locale for reset
	$self->{_local_locale} = [] if ( !$self->{_local_locale} );
	push( @{ $self->{_local_locale} }, $orig );
}

1;

__END__
#{{{ pod
=head1 NAME

Mojolicious::Cafe::Controller - controller

=head1 DESCRIPTION

Caramel provides a runtime environment for Caramel application
framework. It provides all the basic tools and helpers needed to write
Caramel web applications. Caramel is based on Mojolicious.

=head1 METHODS

L<Caramel> inherits all methods from L<Mojolicious::Controllers> and 
implements the following new ones.



=head2 C<dbh>

  my $sth = $app->dbh->prepare(q(SELECT * FROM table));

Return DBI object for communicat with database. Database handlers
is depend on virtual host.


=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>. L<https://caramel.bata.eu/foswiki/bin/view/>.

=cut
#}}}
