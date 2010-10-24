package Cafe::Application;
use strict;
use utf8;
use base qw(Cafe::Base);

use constant MAX_CONTENT_LENGTH => 1024 * 1024 * 5; # 5M
use constant RAW => 0;
our $VERSION = '0.81';

use Carp;
use Apache2::Const -compile => qw(OK FORBIDDEN NOT_FOUND SERVER_ERROR REDIRECT);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil ();
use Apache2::Request;
use Apache2::Log;
use Apache2::Cookie;
use Apache::Session::Postgres;
use POSIX qw(strftime setlocale LC_ALL);
use DBI;
use JSON::XS;
use RPC::XML;
use RPC::XML::Parser;
use Text::Iconv;
use Cache::Memcached;
use Cafe::Class;
use Data::Dumper;
use Encode;

#{{{ pod
=head1 NAME

Cafe::Application - Method for handle client requests bussines logic classes

=head1 SYNOPSIS

package Complaints::Application;
use utf8;
use strict;
use base qw(Cafe::Application);
use Complaints::Complaints;

sub new {
        my ($self, $r) = @_;
        my ($instance) = $self->SUPER::new( $r, __PACKAGE__ );
        bless($instance);

        # For each option, call appropriate subroutine.
        $instance->{methods} = {
                index                           => sub { $instance->listing_view('Complaints::Complaints', 'complaint_search.tt2', 60); },
                complaint_search		=> sub { $instance->listing_view('Complaints::Complaints', undef, 60); },
		complaint_view			=>  sub { $instance->class_view('Complaints::Complaint', undef, 60); },
		complaint_get			=>  sub { $instance->rpc_get('Complaints::Complaint', 60, @_); },
		complaint_set			=>  sub { $instance->rpc_set('Complaints::Complaint', 60, @_); },
		complaint_del			=>  sub { $instance->rpc_del('Complaints::Complaint', 60, @_); },
		receivedtypes_get		=>  sub { $instance->rpc_get('Complaints::ReceivedTypes', 60, @_); },
		places_get			=>  sub { $instance->rpc_get('Complaints::Places', 60, @_); },
		results_get			=>  sub { $instance->rpc_get('Complaints::Results', 60, @_); },
		requirements_get		=>  sub { $instance->rpc_get('Complaints::Requirements', 60, @_); },
		store_search_get		=>  sub { $instance->rpc_get('Schema::Store::Search', 60, @_); },
		article_search_get		=>  sub { $instance->rpc_get('Iris::Catalog::Article::Search', 60, @_); },
		note_get			=>  sub { $instance->rpc_get('Complaints::Complaint::Note', 60, @_); },
		note_set			=>  sub { $instance->rpc_set('Complaints::Complaint::Note', 60, @_); },
		note_del			=>  sub { $instance->rpc_del('Complaints::Complaint::Note', 60, @_); },
		attachement_get			=>  sub { $instance->rpc_get('Complaints::Complaint::Attachement', 60, @_); },
		attachement_set			=>  sub { $instance->rpc_set('Complaints::Complaint::Attachement', 60, @_); },
		attachement_del			=>  sub { $instance->rpc_del('Complaints::Complaint::Attachement', 60, @_); },
		attachement_upload		=>  sub { $instance->class_null('attachement_upload.tt2', 60); },
        };

        return $instance;
}

sub DESTROY {
        my ($self) = @_;
}

1;

=head1 DESCRIPTION

Cafe::Application is a new module based on the Apache::Application module
on AFv1. Users now don't need define handler. All configuration is in apache
configuration files.

=head1 Cafe::Application

Cafe::Application - Method for handle client requests bussines logic classes

=head2 handler()

Join application as Apache module to web server

=cut
sub handler : method {
#{{{
	my ($class, $r) = @_;
	my $app;
	my $req = Apache2::Request->new($r);
	$req->parse();	
	eval ('$app = new ' . $class . '($req);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
	if (  $app->controller() == Apache2::Const::OK ) {
		$app->view();
	}

	$app->clean();
	return($app->{status});
#}}}
}
#}}}

#{{{ new
=head2 new()

Contructor of Cafe::Application class. Prepare default values of properties.

=head3 Parameters

=over

=item $r - instance of Apache2::Request, used for reading data from client

=back

=cut
sub new {
	my ($self, $r) = @_;
	
	my $instance = $self->SUPER::new();
	bless($instance);
	
	#Property initialization
	$instance->{request} = $r; #Save request
	$instance->{request_type} = $r->param('type') ? $r->param('type') : undef;#Save type of request type for logic classes
	$instance->{status} = Apache2::Const::OK; #Default method

	#Creating user class instance
	my $class_user = $instance->dir_config('class_user');
	eval("require $class_user") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
	eval('$instance->{user} = new ' . $class_user . '($instance, $instance);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
	if ( $r->user() ) {
		$instance->{user}->load_by_user($r->user());
	} elsif ( $instance->dir_config('auto_login_user') ) {
		$instance->{user}->load_by_user($instance->dir_config('auto_login_user'));
	}

	# read in the cookie if self is an old session
	my $cookies = Apache2::Cookie::Jar->new($r);

	# create a session object based on the cookie we got from the
	# browser, or a new session if we got no cookie
	my %session;
	eval {
		tie %session, 'Apache::Session::Postgres', $cookies->cookies("SESSION_ID") ? $cookies->cookies("SESSION_ID")->value() : undef , {
			Handle      => $instance->dbh,
			TableName   => 'schema.sessions',
			Commit      => 0
		};
	};

	if ($@) {
		# could be a database problem
		print(STDERR "AF error " . __FILE__ . " line " . __LINE__ . ": Couldn't tie session: $@");
		eval {
			tie %session, 'Apache::Session::Postgres', undef , {
				Handle      => $instance->dbh,
				TableName   => 'schema.sessions',
				Commit      => 0
			};
		};
	}
	$instance->{session} = \%session;

	# might be a new session, so let's give them their cookie back
	my $cookie = Apache2::Cookie->new($r,
				  -name  => "SESSION_ID",
				  -value => $session{_session_id} );

	$cookie->bake($r);                       # send cookie in response headers

	return $instance;
}
#}}}

#{{{ controller
=head2 controller()

Call method specified in query string

=cut
sub controller {
	my ($self) = @_;
	my $r = $self->{request};

	if ( $r->param('type') && $r->param('type') eq 'json' ) {
		#Check input data
		if($r->method ne 'POST') { die "AF error " . __FILE__ . " line " . __LINE__ . ": You must send data thru POST in json rpc." }
		my $len  = $r->headers_in()->get('Content-length');
		if(MAX_CONTENT_LENGTH < $len) { die "AF error " . __FILE__ . " line " . __LINE__ . ": Data is out of limit." }

		my ($buf, $js);
		while( $r->read($buf,$len) ){ $js .= $buf; }
		#Convert json to hash
		my $json = JSON::XS->new->utf8(0)->pretty->allow_nonref;
		my $hash = $json->decode($js);

		my $uri = "/" . $self->clean_uri( $hash->{method} );
		$self->{method} = $uri if ( exists( $self->{methods}->{"$uri"} ) );
		$self->{method} = $hash->{method} if ( ! $self->{method} && exists( $self->{methods}->{$hash->{method}} ) );

		if ($self->{method}) {
			my $method = $self->{methods}->{$self->{method}};
			my $retval = &$method(@{$hash->{params}});
			$retval = {
				id     => $hash->{id},
				result => $retval,
				error  => undef,
			};
			#Remove object from $retval
			$retval = $self->clean_struct($retval);
			#Encode hash to json
			$self->{data} = $json->encode($retval);
			$self->{contenttype} = "text/plain;charset=UTF-8"; #Inititalization o contenttype from ContentType header
			$self->{data_type} = RAW; #Initialization of raw data
		} else {
		    $self->{status} = Apache2::Const::NOT_FOUND;
		}
	} elsif ( $r->param('type') && $r->param('type') eq 'xmlrpc' ) {
		#Check input data
		if($r->method ne 'POST') { die "AF error " . __FILE__ . " line " . __LINE__ . ": You must send data thru POST in xml rpc." }
		my $len  = $r->headers_in()->get('Content-length');
		if(MAX_CONTENT_LENGTH < $len) { die "AF error " . __FILE__ . " line " . __LINE__ . ": Data is out of limit." }

		my ($buf, $xml);
		while( $r->read($buf,$len) ){ $xml .= $buf; }
		$xml = Encode::encode("utf8", $xml);

		$RPC::XML::ENCODING = "utf-8";
			
		#By default, C<smart_encode> uses heuristics to determine what encoding
		#is required for a data type. For example, C<123> would be encoded as C<int>,
		#where C<3.14> would be encoded as C<double>. In some situations it may be
		#handy to turn off all these heuristics, and force encoding of C<string> on
		#all data types encountered during encoding. Setting this flag to C<true>
		#will do just that.
		$RPC::XML::FORCE_STRING_ENCODING = 1;
		
		my $resp = RPC::XML::Parser->new()->parse($xml);
		if (ref($resp)) { 
			#Call method from xmlrpc
			if (exists $self->{methods}->{$resp->name}) {
				my @params;
				foreach my $arg (@{$resp->args}) {
				    push(@params, $arg->value);
				}
				my $method = $self->{methods}->{$resp->name}; 
				my $retval = &$method(@params);
				#$retval = RPC::XML::smart_encode($retval);
				my $response = RPC::XML::response->new($retval);
				$self->{data} = $response->as_string();
				$self->{data_type} = RAW; #Initialization of raw data
			} else {
				$self->{status} = Apache2::Const::NOT_FOUND;
			}
		}
	} else {
		my $method = undef;
		#Find called method from client
		if ( $r->param('method') && exists( $self->{methods}->{$r->param('method')} ) ) {
			$method = $self->{methods}->{$r->param('method')};
			$self->{method} = $r->param('method');
		} elsif ( $self->dir_config('uri_base') ) { 
			my $uri = "/" . $self->clean_uri( $r->uri() );
			$method = $self->{methods}->{"$uri"} if ( exists( $self->{methods}->{"$uri"} ) );
		}

		#Call method
		if ( $method ) {
			&$method();
		} else {
			$self->log("Method on uri " . $r->uri() . " not found.");
			$self->{status}	= Apache2::Const::NOT_FOUND;
		}
	}
	#Save session data
	$self->{session}->{time} = time();
	untie(%{$self->{session}});
	return( $self->{status} );
}
#}}}

#{{{ view
=head2 view()

Create document from template and data or 
send raw data to client

=cut
sub view {
	my ($self) = @_;
	my $r = $self->{request};

	#set header for file definition
	if ( $self->{filename} ) { 
		$r->headers_out->set("Content-Disposition" => "attachment;filename=$self->{filename}"); 
	}
	if ( $self->{data_type} eq Cafe::Base::TEMPLATE ) {

		$self->{data}->{getstring} = sub { $self->getstring(@_); };
		$r->content_type($self->{contenttype});

		if ( $self->{contenttype} eq "application/pdf" || $self->{contenttype} eq "application/postscript") {

			$r->no_cache( -1 );
			#Send document to client
			$self->set_local_locale();
			my $output = "";
			if ( $self->tmpl()->process($self->template(), $self->{data}, \$output) )  {
				$r->headers_out->set("Accept-Ranges" => "bytes");
				$r->headers_out->set("Content-Length" => length($output));
				$self->set_local_locale("C");
				$r->headers_out->set("Expires" => strftime("%a, %e %b %Y %H:%M:%S GMT", gmtime));
				$self->restore_local_locale(); 
				$r->rflush();
				$r->print($output);
			} else {
				$self->{status} = Apache2::Const::SERVER_ERROR;
				$r->log_reason($self->tmpl()->error());
			}
			$self->restore_local_locale();
		} elsif ( $self->{contenttype} eq "application/vnd.oasis.opendocument.text") {
		} else {
			$r->no_cache( -1 );
			$r->rflush();
			#Send document to client
			$self->set_local_locale();
			my $output = "";
			if ( $self->tmpl()->process($self->template(), $self->{data}, \$output) )  {
				$r->print($output);
			} else {
				$self->{status} = Apache2::Const::SERVER_ERROR;
				$r->log_reason($self->tmpl()->error());
			}
			$self->restore_local_locale();
		}
	} elsif ( $self->{data_type} eq RAW ) {
		$r->content_type($self->{contenttype});
		$r->headers_out->set("Expires" => strftime("%a, %e %b %Y %H:%M:%S GMT", gmtime(time - 86400)));
		$r->no_cache( -1 );
		$r->rflush();
		$r->print($self->{data});
	}

	return($self->{status});
}
#}}}

#{{{ clean
=head2 clean()

Clean references after HTTP request

=cut
sub clean {
	my ($self) = @_;
	$self->dbh->disconnect();
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

#{{{rpc_del
=head2 rpc_del()

template of delete method by json
=head3 Parameters
=over

=item $class - class name

=item $right - idright, if not defined method is allowed for all

=back

=cut
sub rpc_del {
    my ($self, $class, $right, @id) = @_;

    if ( ! defined($right) ||  $self->{user}->isright($right) ) {
        my $obj;
        eval("require $class")  or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
	if ( scalar(@id) > 0 ) {
		if ( ref($id[0]) eq "HASH" ) {
			eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
			$obj->rules($id[0]);
		} else {
			eval('$obj = new ' . $class . '($self, $self, @id);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		}
	} else {
		die "AF error " . __FILE__ . " line " . __LINE__ . ": Cannot delete instance without primary key";
	}
        $obj->delete();
        return($obj->gethash());
    } else {
        $self->{status} = Apache2::Const::FORBIDDEN;
    }   
    return(undef);
}
#}}}

#{{{rpc_set
=head2 Method rpc_set

template of save object by json

=head3 Parameters

=over

=item $class - class name

=item $right - idright, if not defined method is allowed for all

=back

=cut
sub rpc_set {
	my ($self, $class, $right, $hash) = @_;
    
	if ( ! defined($right) ||  $self->{user}->isright($right) ) {
		my $obj;
		eval("require $class") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@"; 
		eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		$obj->rules($hash);
		if ( $obj->{root}->{data}->{msgid} == 0 ) { $obj->save(); }
		return($obj->gethash());
	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}
	return(undef);
}
#}}}

#{{{rpc_get
=head2 Method rpc_get

template of get object by json  method

=head3 Parameters

=over

=item $class - class name

=item $right - idright, if not defined method is allowed for all

=back

=cut
sub rpc_get {
	my ($self, $class, $right, @id) = @_;
	if ( ! defined($right) || $self->{user}->isright($right) ) {
		my $obj;
		eval("require $class") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		if ( scalar(@id) > 0 ) {
			if ( ref($id[0]) eq "HASH" ) {
				eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
				$obj->rules($id[0]);
			} else {
				eval('$obj = new ' . $class . '($self, $self, @id);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
			}
		} else {
			eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		}
		$obj->load();
		return($obj->gethash());
	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}
	return(undef); 
}
#}}}

#{{{rpc_class_view
=head2 Method rpc_class_view

template of view object by json  method.
The method returns html code rendered the same way as Apache2::Class.
The differences are:
It returns HTML code

Template parts are parametrized by any way. A context contains request->param dictionary.
So you can insert into template IF sections that filtered out parts to be displayed.


=head3 Parameters

=over

=item $class - class name

=item $right - idright, if not defined method is allowed for all

=back

How to use it
-------------

Javascript client ::

	var rpc = new JSONRpcClient("/iris2.html?type=json");
	var req = rpc.makeRequest("storearticleinformation_view",[{'htmlparts':['articleinfo',]},]);
	var retval = rpc.sendRequest(req);
	var somenode = document.getElementById('to-be-filled');
	somenode.innerHTML = retval
	
Html template ::

	[% IF not param.defined or param.htmlparts.grep('articleheader').size() > 0 %]
	some code
	[% END %]

	[% IF not param.defined or param.htmlparts.grep('articleinfo').size() > 0 %]
	some another code
	[% END %]

	...

Steps:
1. write template
2. divide template code into smaller parts (by [% IF param.defined ... %])
3. write javascript code
4. in the javascript code call method with arguments you like (in this case the arguments are {'htmlparts':['articleinfo',]})
5. replace given node with htmlcode you gave from method call

That is all.

=cut
sub rpc_class_view {
	my ($self, $class, $template, $right, @params) = @_;
	my $retval;
	if ( ! defined($right) || $self->{user}->isright($right) ) {
		my $instance = "instance";
		my $output = "";
		my $obj = undef;

		if ( $class =~ /([0-9A-Za-z]+)$/) {
			$instance = lc($1); 
		}
		eval("require $class") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";

		if( scalar(@params) ){
			my $content = $params[0];
			$obj->rulekey($content);
		};
		$obj->load();

		$self->{data}->{"$instance"} = $obj;
		$self->{data}->{getstring} = sub { $self->getstring(@_); };
		$self->{data}->{param} = \@params;
		$self->set_local_locale();
		if ( $self->tmpl()->process($self->template($template), $self->{data}, \$output) )  {
			$retval = $output;
		}
		$self->restore_local_locale(); 
	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}

	return($retval); 
}
#}}}

#{{{class_null
=head2 class_null 

method check right and set template (if defined)
Useful for create static pages for info, help or ajax
applications
	
=cut
sub class_null {
	my ($self, $template, $right) = @_;
	my $obj = undef;
	my $instance = "instance";


	if ( ! defined($right) || $self->{user}->isright($right) ) {
		$self->template($template)
	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}
	return($self->{status});
}
#}}}

#{{{listing_view
=head2 Method listing_view

template of print method

=head3 Parameters

$class - class name
$template - force template name
$right - idright, if not defined method is allowed for all

=cut
sub listing_view {
	my ($self, $class, $template, $right) = @_;
	if ( ! defined($right) || $self->{user}->isright($right) ) {
		$self->template($template);
		my $obj = undef;
		#Create name of instance variable
		my $instance = ($class =~ /([0-9A-Za-z]+)$/) ? lc($1) : "instance";
		eval("require $class") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		$obj->rules();
		$obj->load();
		$self->{data}->{"$instance"} = $obj;
		$self->{data}->{listing} = $obj;
	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}

	return($self->{status});
}
#}}}

#{{{class_view
=head2 Method class_view

template of view method

=head3 Parameters

$class - class name
$template - force template name
$right - idright, if not defined method is allowed for all

=cut
sub class_view {
	my ($self, $class, $template, $right) = @_;

	if ( ! defined($right) || $self->{user}->isright($right) ) {
		$self->template($template);
		my $instance = "instance";
		my $obj = undef;
		if ( $class =~ /([0-9A-Za-z]+)$/) {
			$instance = lc($1); 
		}
		eval("require $class") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		$obj->rulekey();
		$obj->load();
		$self->{data}->{"$instance"} = $obj;
		$self->{data}->{record} = $obj;
	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}
	return($self->{status});
}
#}}}

#{{{ class_print
=head2 Method class_print

template of print method for Cafe::Class class

=head3 Parameters

$class - class name
$template - force template name
$right - idright, if not defined method is allowed for all
$contenttype - contenttype of print  
$format - sprintf format for filename
@columns - sprintf values for filename

=cut
sub class_print {
	my ($self, $class, $template, $right, $contenttype, $format, @columns) = @_;


	if ( ! defined($right) || $self->{user}->isright($right) ) {
		$self->template($template);
		my $obj = undef;
		my $instance = "instance";

		if ( $class =~ /([0-9A-Za-z]+)$/) {
			$instance = lc($1);
		}

		eval("require $class") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		$obj->rulekey();
		$obj->load();
		$self->{data}->{"$instance"} = $obj;
		$self->{data}->{record} = $obj;
		$self->{contenttype} = $contenttype;

		if ( $format ) {
			my @values;
			foreach my $column (@columns) {
				push(@values, $obj->{$column});
			}
			$self->{filename} = sprintf($format, @values);
		}
	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}

	return($self->{status});
}
#}}}

#{{{listing_print
=head2 Method listing_print

template of print method for Cafe::Listing class

=head3 Parameters

$class - class name
$template - force template name
$right - idright, if not defined method is allowed for all
$contenttype - contenttype of print  
$format - sprintf format for filename
@columns - sprintf values for filename

=cut
sub listing_print {
	my ($self, $class, $template, $right, $contenttype, $format, @columns) = @_;

	if ( ! defined($right) || $self->{user}->isright($right) ) {
		$self->template($template);
		my $obj = undef;
		my $instance = "instance";

		if ( $class =~ /([0-9A-Za-z]+)$/) {
			$instance = lc($1);
		}

		eval("require $class") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		$obj->rules();
		$obj->load();
		$self->{data}->{"$instance"} = $obj;
		$self->{data}->{listing} = $obj;
		$self->{contenttype} = $contenttype;

		if ( $format ) {
			my @values;
			foreach my $column (@columns) {
				push(@values, $obj->{$column});
			}
			$self->{filename} = sprintf($format, @values);
		}
	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}

	return($self->{status});
}
#}}}

#{{{class_save
=head2 Method class_save

template of saved method


=head2 Parameters

=over

=item $class - class name

=item $template_prefix - use template prefix 

=item $right - idright, if not defined method is allowed for all

=back

=cut

sub class_save {
	my ($self, $class, $template, $right) = @_;
	my $obj = undef;
	my $instance = "instance";

	if ( ! defined($right) ||  $self->{user}->isright($right) ) {
		$self->template($template);
		if ( $class =~ /([0-9A-Za-z]+)$/) {
			$instance = lc($1);
		}
		eval("require $class") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		eval('$obj = new ' . $class . '($self, $self);') or die "$@";
		if ( $obj->rules() ) {
			$obj->save();
		}
		$self->{data}->{"$instance"} = $obj;
	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}
	return($self->{status});
}
#}}}

#{{{ dir_config
=head2 

Return value of PerlSetVar directive on Apache config file used by AFv2

=head3 Parameters

=over 4

=item * $varname - Hash from Apache::ConfigFile method

=back

=cut 
sub dir_config {
	my ($self, $varname) = @_;
	return($self->{request}->dir_config($varname));
}
#}}}

#{{{ manual
=head2 Method manual

Returns html manual

=head3 Parameters

=over 

=item $name - input manual file name

=item return html manual

=back 

=cut 

sub manual {
	my ( $self, $name ) = @_;
	my $dir = '/var/www/caramel/www/manual/';
	my $locale = $self->{user}->locale();
	my $file = $dir.$locale.'/'.$name;
	if (! -e $file.'.xml') {
		$locale = 'en_US';
		$file = $dir.$locale.'/'.$name;
		if (! -e $file.'.xml') {
			$self->{status} = 'NOT_FOUND';
		}
	}
	if (! $self->{status}) {
		my $return = `xmlto html-nochunks $file.xml -o /tmp/`;
		open(FILE, '/tmp/'.$name.'.html');
		$self->{data_type} = RAW;
		$self->{data} = join('', <FILE>);
		$self->{data} =~ s/img\//\/manual\/$locale\/img\//g; 
		$self->{contenttype} = "text/html;charset=ISO-8859-1";
		close(FILE);
	}
	return($self->{'status'}); 
}
#}}}

#{{{ memd
=head2 Method memd

Returns instance of Cache::Memecached class. 

=cut 

sub memd {
	my ( $self ) = @_;
	if ( $self->{request}->dir_config('memcached_servers') && ! defined($self->{_memd}) ) {
		my @servers = split(',', $self->{request}->dir_config('memcached_servers'));
		$self->{_memd} = new Cache::Memcached {
			'servers' => \@servers,
			'debug' => 0,
			'compress_threshold' => 10_000,
		} or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
	} elsif ( defined($self->{_memd}) ) {
		return($self->{_memd});
	}
}
#}}}

#{{{ rpc_listing_view
=head2 Method 

template of view object by json  method.
The method returns html code rendered the same way as Cafe::Class.
The differences are:
It returns HTML string

Template parts are parametrized by any way. A context contains request->param dictionary.
So you can insert into template IF sections that filtered out parts to be displayed.


=head3 Parameters

=over

=item $class - class name

=item $right - idright, if not defined method is allowed for all

=back

How to use it
-------------

Javascript client ::

	var rpc = new JSONRpcClient("/iris2.html?type=json");
	var req = rpc.makeRequest("storearticleinformation_view",[param1, param2, param3, ... ]);
	var retval = rpc.sendRequest(req);
	var somenode = document.getElementById('to-be-filled');
	somenode.innerHTML = retval;
	
Steps:
1. write template
2. write javascript code
3. in the javascript code call method with arguments you like (in this case the arguments are {'htmlparts':['articleinfo',]})
4. replace given node with htmlcode you gave from method call

That is all.

=cut
sub rpc_listing_view {
	my ($self, $class, $template, $right, @params) = @_;
	my $retval;

	if ( ! defined($right) || $self->{user}->isright($right) ) {
		my $instance = "instance";
		my $output = "";
		my $obj = undef;
		
		
		#Create instance of required class
		eval("require $class") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		eval('$obj = new ' . $class . '($self, $self);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
		#We use first param as hash of parameters
		my $content = {};
		if ( scalar(@params) ) { $content = $params[0]; }
		$obj->rules($content);
		$obj->load();

		#Copy reference instance of class to template
		if ( $class =~ /([0-9A-Za-z]+)$/) {
			$instance = lc($1); 
		}
		$self->{data}->{"$instance"} = $obj;

		#Add getstring function
		$self->{data}->{getstring} = sub { $self->getstring(@_); };

		#Generate output by template and data
		$self->set_local_locale();
		if ( $self->tmpl()->process($self->template($template), $self->{data}, \$output) )  {
			$retval = $output;
		} else {
			$self->{status} = Apache2::Const::SERVER_ERROR;
			$self->{request}->log_reason($self->tmpl()->error());
		}
		$self->restore_local_locale(); 

	} else {
		$self->{status} = Apache2::Const::FORBIDDEN;
	}

	return($retval); 
}
#}}}

#{{{ log
=head2 log

	Send log message to log (Apache version - only send message to STDERR by dump function)

=cut
sub log {
	my ($self, $message) = @_;
	$self->dump("$message");
}
#}}}

#{{{ clean_struct
=head2 clean_struct

	Remove class instances from anonymous structure recursively

	This function is used before converting structure to json

=cut
sub clean_struct {
	my ($self, $value) = @_;

	if ( ! ref($value) || ref($value) eq 'SCALAR') {
		return($value);
	} elsif ( ref($value) eq 'ARRAY' ) {
		foreach my $item (@{$value}) {
			$item = $self->clean_struct($item);
		}
		return($value);
	} elsif ( ref($value) eq 'HASH' ) {
		foreach my $key (keys(%{$value})) {
			$value->{$key} = $self->clean_struct($value->{$key});
		}
		return($value);
	} elsif ( ref($value) eq 'Time::Piece' ) {
		$self->set_local_locale();
		my $strftime = $value->strftime('%x');
		$self->restore_local_locale();
		return($strftime);
	} else {
		return(ref($value));
	}

}
#}}}

#{{{ template
=head2 template

Try found template from template path

=cut
sub template {
	my ($self, $template) = @_;

	#Save manually set template 
	$self->{template} = $template if ( $template );

	#Try found classic method template
	if ( ! $self->{template} ) {
		foreach my $path ( $self->template_paths() ) {
			if ( -f "$path/$self->{method}.tt2" ) {
				$self->{template} = "$self->{method}.tt2";
				last;	
			}
		}
	}

	#Try found route template
	if ( ! $self->{template} && $self->dir_config('uri_base') ) {
			foreach my $path ( $self->template_paths() ) {
				if ( -f "$path/" . $self->clean_uri( $self->{request}->uri() ) . ".tt2" ) {
					$self->{template} = $self->clean_uri( $self->{request}->uri() ) . ".tt2";
					last;	
				}
			}
	}

	die "Cafe framework: Template not found for " . $self->clean_uri( $self->{request}->uri() ) . "." if ( ! $self->{template} );

	return($self->{template});
}
#}}}
1;
