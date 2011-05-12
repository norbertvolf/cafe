package Cafe::Base;

use utf8;
use strict;
use warnings;
use base qw(Cafe::Object);

use constant TEMPLATE => 1;
use constant TRANSLATIONS_FILE => "translations.csv";

use POSIX qw(strftime locale_h setlocale LC_ALL);
use Cafe::Class;
use Data::Dumper;
use HTTP::Request;
use LWP::UserAgent;
use Encode qw(encode);
use Template;
use Carp;
use Time::Piece;
use Cafe::Filters;

$Data::Dumper::Maxdepth = 4;

#{{{ new
sub new {
	my $self = shift;
	my $instance = $self->SUPER::new(); 
	bless($instance);

	#Property initialization
	$instance->{methods} = {}; #Define hash of method
	$instance->{method} = undef; #Initialization of method
	$instance->{template} = undef; #Initialization of name of template
	$instance->{filename} = undef; #Initialization of filename for Content-Disposition header

	return($instance);
}
#}}}
#{{{ tmpl
=head2 tmpl

Return instance of templates system

=cut
sub tmpl {
	my ($self) = @_;

	if ( ! $self->{_tmpl} ) {
		my @paths = $self->template_paths();

		$self->{_tmpl} = new Template( 
			INCLUDE_PATH => join(":", @paths),
			ENCODING => 'utf8' ,
			RECURSION => 1 ,
			FILTERS => {
				'cslatex' => [ \&Cafe::Filters::cslatex_filter_factory, 1 ],
				'a2ps' => [ \&Cafe::Filters::a2ps, 1 ],
				'iso2utf' => [ \&Cafe::Filters::iso2utf, 1 ],
				'utf2iso' => [ \&Cafe::Filters::utf2iso, 1 ],
				'texclean' => [ \&Cafe::Filters::texclean, 1 ],
				'tex_zipcode' => [ \&Cafe::Filters::tex_zipcode, 1 ],
				'article' => [ \&Cafe::Filters::article, 1 ],
				'phonenumber' => [ \&Cafe::Filters::phonenumber, 1 ],
				'shoesize' => [ \&Cafe::Filters::shoesize, 1 ],
				'location' => [ \&Cafe::Filters::location, 1 ],
				'sprintf' => [ \&Cafe::Filters::sprintf, 1 ],
				'hostaddress' => [ \&Cafe::Filters::hostaddress, 1 ],
				'utf8_email_header' => [ \&Cafe::Filters::utf8_email_header, 1 ],
				'csvclean' => [ \&Cafe::Filters::csvclean, 1 ],
				'viewlet' => [ \&Cafe::Filters::viewlet, 1 ],
				'default' => [ \&Cafe::Filters::default, 1 ],
				'decode' => [ \&Cafe::Filters::perl_decode, 1 ],
				'remove_diacritic' => [ \&Cafe::Filters::remove_diacritic, 1 ],
			},
			CONSTANTS => {
				class => {
					DB_VARCHAR  => Cafe::Class::DB_VARCHAR,
					DB_INT   => Cafe::Class::DB_INT,
					DB_DATE  => Cafe::Class::DB_DATE,
					DB_NUMERIC  => Cafe::Class::DB_NUMERIC,
					DB_FMTCHAR   => Cafe::Class::DB_FMTCHAR,
				}
			},
		);
	}

	return($self->{_tmpl});
}
#}}}
#{{{ translations
=head2 translations

Load and returns translations from CSV files in templates directories

Method don't accept parameters.

CSV file - comma separated file contains in first column 
"C" locale message  (english message) used also as key
in getstring method.

You can also use first column as key and define en_US column
for english language.

=cut
sub translations {
	my ($self) = @_;
	if ( ! defined( $self->{_translations} ) && $self->dir_config('path_template') ) {
		$self->{_translations} = {};
		foreach my $path ( split(/:/, $self->dir_config('path_template')) ) {
			my @locales;
			if ( -e "$path/" . TRANSLATIONS_FILE ) {
				open(TRANSLATIONS, "<:utf8", "$path/" . TRANSLATIONS_FILE) or die "AF error " . __FILE__ . " line " . __LINE__ . ": Cannot load translation file."; 
				while( <TRANSLATIONS>  ) {
					chomp();
					if ( $_ =~ /^C\|/ && ! scalar(@locales) ) {
						@locales = split(/\|/, $_);
						foreach my $locale ( @locales ) {
							if ( ! exists($self->{_translations}->{$locale}) ) {
								$self->{_translations}->{$locale} = {};
							}
						}
					} elsif ( scalar(@locales) ) {
						my @messages = split(/\|/, $_);
						for(my $i = 0; $i <  scalar(@locales); $i++ ) {
							if ( ! $messages[$i] ) {
								$self->{_translations}->{$locales[$i]}->{$messages[0]} = $messages[0];
							} else {
								$self->{_translations}->{$locales[$i]}->{$messages[0]} = $messages[$i];
							}
						}
					}
				}
				close(TRANSLATIONS);
			}
		}
	} elsif ( ! $self->dir_config('path_template') ) {
		die "AF error " . __FILE__ . " line " . __LINE__ . ": Not defined path_template variable by PerlSetVar in Apache configuration files.\n";
	}

	return($self->{_translations});
}
#}}}
#{{{ getstring
=head3 C<getstring>

Return locale string from translations.csv

Method accept message key ("C" locale message} as first parameter. 

If not defined message key parameter method return hash contains 
all translations for actual language

If not defined message for actual locale function returns "C" locale message

Method can convert encoding of output text to $encoding. This conversion
must be supported byt iconv utility and only if $key parameter is used.

=cut 
sub getstring {
	my ($self, $key, $encoding, $quote) = @_;
	my $locale = $self->{user}->locale();

	if ( ! exists($self->translations()->{$locale}) ) {
		if ( exists($self->translations()->{"C"}) ) {
			$locale = "C";
		} else {
			die "Error Cafe::Base::getstring : Not defined " . $self->{user}->locale() . " locale. (line " . __LINE__ . ")\n";
		}
	}

	my $retval;

	if ( $key ) {
		if ( exists($self->translations()->{$locale}->{$key}) ) {
			$retval =  $self->translations()->{$locale}->{$key};
		} elsif ( exists($self->translations()->{"C"}->{$key}) ) {
			$retval =  $self->translations()->{"C"}->{$key};
		} else {
			$self->log("Warning Cafe::Base::getstring: Key \"$key\" not found in translations (line " . __LINE__ . ")");
			$retval = "$key";
		}
	} else {
		$self->die("Cafe::Base::getstring", "Not defined parameter key in getstring function", __LINE__);
	}

	if ( $encoding ) {
		my $converter = Text::Iconv->new("UTF-8", $encoding);
		$retval = $converter->convert($retval);
	}


	if ( $quote && $quote eq 'quote' ) {
		$retval =~ s/'/\\'/;
	}

	if ( $quote && $quote eq 'quotedbl' ) {
		$retval =~ s/"/\\"/;
	}

	return($retval);
}
#}}}
#{{{ restore_local_locale
=head2 restore_local_locale

Reset locale from LIFO

=cut
sub restore_local_locale {
	my ( $self ) = @_;

	if ( ! $self->{local_locale} ) { $self->{local_locale} = []; }   
	if ( scalar(@{$self->{local_locale}}) ) {
		pop(@{$self->{local_locale}});
		if ( scalar(@{$self->{local_locale}}) ) {
			setlocale( LC_ALL, $self->{local_locale}->[scalar(@{$self->{local_locale}}) - 1]);
		}
	} else {
		die "AF error " . __FILE__ . " line " . __LINE__ . ": Locale array is empty, when I want restore locale.";
	}   
}
#}}}
#{{{set_local_locale
=head2 set_local_locale

Set locale and save original locale to LIFO. If $locale
is not defined try get locale from class_user. Be carefull
$locale must se same se generated locale in system (with or 
without charset it depends).

=over

=item $locale - requested locale

=back

=cut
sub set_local_locale {
	my ($self, $locale) = @_;

	if ( ! $locale ) { 
		$locale = "C"; 
		if ( $self->{user} ) {
			$locale = $self->{user}->locale() . "." . $self->{user}->charset();
		}
	}   
	if ( ! $self->{local_locale} ) { $self->{local_locale} = []; }   
	setlocale( POSIX::LC_ALL, $locale );
	push ( @{$self->{local_locale}}, $locale );
}
#}}}
#{{{ post_request
=item post_request
#Return post request
=cut
sub post_request {
	my ($self, $url, $args) = @_;
	
	# Create a user agent object
	my $ua = new LWP::UserAgent;
	$ua->agent("AgentName/0.1 " . $ua->agent);
	
	# Create a request
	my $req = new HTTP::Request POST => $url;
	$req->content_type('application/x-www-form-urlencoded');
	$req->content(encode("UTF-8", $args));
	
	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);
	
	# Check the outcome of the response
	if ($res->is_success) {
		return $res->content;
	} else {
		return "failed";
	}
}
#}}}
#{{{ generate_params
=item generate_params
post parameters string generation
=cut
sub generate_params {
	my ($self, $params) = @_;
	my $string = "";
	foreach my $param (keys %{$params}) {
		if ($string) {
			$string = $string."&";	
		}
		$string = $string.$param."=".$params->{$param};
	}
	return $string;
}
#}}}
#{{{ parse
=item parse
Parsing of http request arguments
=cut
sub parse {
	my ($self, $content) = @_;
	my ($key, $name, $index, $item);

	foreach $key (keys(%$content)) {
		if ( $key =~ /(^(\w+)\[\d+\])|(^(\w+)\{\w+\})/ ) {
			#Najdeme si nazev pole/hashe
			$key =~ /^(\w+)/;$name = '$content->{' . $1 . '}';
			#Prochazim polozku pole hashe a hledame jeji a vkladame typ do pole
			while ($key =~ /\[(\d+)\]|\{(\w+)\}/g) {
				if ( defined($1) ) { # je to obycejne indexovane pole dame do reference na pole
					$name .= "->[$1]";
				} elsif ( defined($2) ) { # je to hash dame to do referenece na hash
					$name .= "->{$2}";
				}
			}
			eval($name . ' = $content->{$key}');
		} 
	}
}
#}}}
#{{{ dump
=head2 Method dump

print variables to error.log

=head3 Parameters

=over

=item $params - any parameter used to Dumper function from Data::Dumper class.

=back

=cut

sub dump {
	my ($self, @params) = @_;
	print(STDERR Dumper(@params));	
}
#}}}
#{{{ user
=head2 Method user

Returns instance of user class. 

=cut 

sub user {
	my ($self) = @_;
	return($self->{user});
}
#}}}
#{{{ dir_config
=head2 Method dir_config

Virtual method to get configuration

=cut 
sub dir_config {
	my ($self, $varname) = @_;
	
	die "Call virtual method dir_config from Cafe::Base for variable $varname.";
}
#}}}
#{{{ dbh
=head2 Method dbh

Return main database handler

=cut 
sub dbh {
	my ($self, $varname) = @_;
	
	if ( ! $self->{_dbh} ) {
		$self->{_dbh} = DBI->connect(
			$self->dir_config('db_dsn'), 
			$self->dir_config('db_user'), 
			$self->dir_config('db_password'), 
			{
				RaiseError => 1, 
				pg_enable_utf8 => 1
			}
		);#Set up connection to database
	
		#Set database encoding
		if ( $self->dir_config('encoding') ) {
			if ( $self->dir_config('db_dsn') =~ /dbi:Pg/i ) {
				$self->{_dbh}->do("SET client_encoding = " . $self->dir_config('encoding'));
				if ( $self->dir_config('default_text_search_config') ) {
					$self->{_dbh}->do("SET default_text_search_config = " . $self->dir_config('default_text_search_config'));
				}
			}
		}
	}
	return($self->{_dbh});
}
#}}}
#{{{ headers
=head2 Method headers

Return headers for 

=cut 
sub headers {
	my ($self) = @_;

	if ( ! $self->{_headers} ) {
		#HTML headers from config file
		$self->{_headers} = {};
		$self->{_headers}->{author} = $self->dir_config('app_headers_author');
		$self->{_headers}->{copyright} = $self->dir_config('app_headers_copyright');
		$self->{_headers}->{description} = $self->dir_config('app_headers_description');
		$self->{_headers}->{keywords} = $self->dir_config('app_headers_keywords');
		$self->{_headers}->{icon} = $self->dir_config('app_headers_icon');
		$self->{_headers}->{logo} = $self->dir_config('app_headers_logo');

		$self->{_headers}->{stylesheets} = [];
		my @indexes = ('', 0, 1, 2, 3, 4, 5, 6, 7, 8, 9);
		foreach my $index ( @indexes ) {
			if ( $self->dir_config('app_headers_stylesheet' . $index) ) {
				push(@{$self->{_headers}->{stylesheets}}, $self->dir_config('app_headers_stylesheet' . $index));
			}
		}

		$self->{_headers}->{application_name} = $self->dir_config('app_headers_application_name');
		$self->{_headers}->{topleft} = $self->dir_config('app_headers_topleft');
	}
	return($self->{_headers});
}
#}}}
#{{{ to_time_piece
=head2 Method to_time_piece

Convert string with date in %Y-%m-%d %H:%M:%S
format to instance of Time::Piece class

=head3 Parameters

=over 

=item $value - input string with date and time

=item return instance of Time::Piece

=back 

=cut 

sub to_time_piece {
	my ( $self, $value ) = @_;
	if ( $value && ! ref($value) && $value =~ /(\d{4})-(\d{2})-(\d{2}).(\d{2}):(\d{2}):(\d{2})/  ) {
		$value = Time::Piece->strptime("$1-$2-$3 $4:$5:$6", "%Y-%m-%d %H:%M:%S");
	} elsif ( $value && $value =~ /(\d{4})-(\d{2})-(\d{2})/  ) {
		$value = Time::Piece->strptime("$1-$2-$3", "%Y-%m-%d");
	}
	return($value);
}
#}}}
#{{{ now
=head2 Method now

Return Time::Piece actual time

=cut 
sub now {
	my ($self) = @_;
	my $now = localtime();
	return($now);
}
#}}}
#{{{ template_paths
=head2 Method template_paths

Return array of template directories

=cut 
sub template_paths {
	my ($self) = @_;
	my @paths;
	if ( $self->dir_config('path_template') ) {
		foreach my $path (split(/:/, $self->dir_config('path_template'))) {
			if ( $path && $self->{user}->locale() && -d ( $path . "/" . $self->{user}->locale() ) ) { push(@paths, $path . "/" . $self->{user}->locale()); }
			if ( -d $path ) { push(@paths, $path); }
		}
	}
	return(@paths);
}
#}}}
#{{{ clean_uri
=head2 clean_uri

Remove uri_base from uri

=cut
sub clean_uri {
	my ($self, $uri) = @_;
	
	return if ( ! $uri );
	
	if ( $self->dir_config('uri_base')) {
		my $uri_base = $self->dir_config('uri_base');
		$uri_base = $uri_base . "/" if ( ! $uri_base =~ /\/$/ );
		$uri_base = "/" . $uri_base if ( ! $uri_base =~ /^\// );
		$uri =~ s/^$uri_base//;
		$uri =~ s/\/$//;
		return($uri);
	} else {
		die "Parameter uri_base not defined."
	}
}
#}}}
#{{{ rich_uri
=head2 rich_uri

Return uri from HTTP request and cleaned by uri_base from configuration

=cut
sub rich_uri {
	my ($self, $uri) = @_;

	return if ( ! $uri );
	if ( $self->dir_config('uri_base')) {
		my $uri_base = $self->dir_config('uri_base');
		my $uri = $self->clean_uri($uri);
		$uri =~ s/^\///;
		return($uri_base . $uri);
	} else {
		die "Parameter uri_base not defined."
	}
}
#}}}
#{{{message
=head2 message
	return global message of instance
=cut
sub message {
	my ($self, $message, $notranslate) = @_;
	if ( defined($message) ) {
		if ( $notranslate ) {
			$self->{_message} = $message;
		} else {
			$self->set_local_locale();
			$self->{_message} = $self->getstring($message);
			$self->restore_local_locale();
		}
	}
	return($self->{_message});
}
#}}}
#{{{ output_type
=head2 output_type

get/set output_type (TEMPLATE or RAW)

=cut
sub output_type {
	my $self = shift;
	my $output_type = shift;

	$self->{_output_type} = $output_type if ( defined($output_type) ); #Set output_type from parameter
	$self->{_output_type} = TEMPLATE if ( ! exists($self->{_output_type}) ); #Initialization output_type
	return( $self->{_output_type} );
}
#}}}
#{{{ content_type
=head2 content_type

get/set content_type (used for HTTP during serve response)

=cut
sub content_type {
	my $self = shift;
	my $content_type = shift;

	$self->{_content_type} = $content_type if ( $content_type ); #Set content_type from parameter
	$self->{_content_type} = "text/html;charset=UTF-8" if ( ! $self->{_content_type} ); #Initialization content_type
	return( $self->{_content_type} );
}
#}}}
#{{{ output
=head3 C<output>
	B<Hash context>
	$self->output( { key => 'value' } ); #Add to output hash 
	$self->output( { key2 => 'value2' } ); #Add to output hash 

	Output property:
	{
		app => ..., #Instance of application
		key => 'value', 
		key2 => 'value2', 
	}

	B<Scalar context>
	$self->output( "Hello world !!!" );

	Output property:
	'Hello world !!!"

	Merge hash parameter output hash (in hash context for templating)
	or overwrite output by input parameter (in scalar context)
=cut
sub output {
	my $self = shift;
	my $output = shift;

	if ( ! $self->{_output} ) {
		#Initialization output
		$self->{_output} = {
			app => $self, #Copy reference to application
			getstring => sub { $self->getstring(@_); }, #getstring reference for translations in templates
		}; 
	}
	if ( $output && ref($output) eq "HASH" ) {
		%{$self->{_output}} = (%{$self->{_output}}, %{$output});
	} elsif ( $output )  {
		$self->{_output} = $output;
	}
	return($self->{_output});
}
#}}}

1;
