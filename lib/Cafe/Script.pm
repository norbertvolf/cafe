package Cafe::Script;
use utf8;
use strict;
use warnings;
use base qw(Cafe::Base);

use POSIX qw(locale_h strftime setlocale);
use DBI;
use Proc::PID::File;
use Sys::Syslog;
use Apache::ConfigFile;
use Time::Piece;


#{{{ pod
=head1 NAME

Cafe::Script - Method for emulate Cafe::Application for AFv2 classes in 
scripts

=head1 SYNOPSIS

use utf8;
use strict;
use Cafe::Script;

=head1 DESCRIPTION

Cafe::Script is module used by scripts which need AFv2 classes
in normal scripts like replicators etc. Module reads configuration
from /etc/apache/sites-enabled/caramel or any redefined 

=head1 Cafe::Script

Cafe::Script - Class for emulation Cafe::Application for  bussines logic 
classes from scripts

=cut
#}}}

#{{{ new
sub new {
	my $self = shift;
	my $conf = shift;
	my $location = shift;
	my $conf_file = $conf;
	my $pid = 1;

#Convert new hash input parameter to variables
	if ( ref($conf_file) eq "HASH" ) {
		$conf_file = $conf->{conf_file};
		$location = $conf->{location};
		$pid = $conf->{pid};
	}

#Open config file
	openlog("$0", 'cons,pid', 'user');

#Open log
	my $scriptname = $0;
	if ( $0 =~ /([^\/]*)$/ ) {
		$scriptname = $1;
	}
	openlog("$scriptname", 'cons,pid', 'user');

	my $instance = $self->SUPER::new();
	bless($instance);
	
	
#Check running script
	if ( $pid ) {
		if ( defined($scriptname) ) {
			if ( Proc::PID::File->running(
				"dir" => "/var/run/robot/",
				"name" => "$scriptname"
			) ) {
				$instance->error("Already running!");
				die "Already running!";
			}
		} else { 
			if ( Proc::PID::File->running("dir" => "/var/run/robot/") ) {
				$instance->error("Already running!");
				die "Already running!";
			}
		}
	}

	$instance->{_conf_file}  = $conf_file ? $conf_file : "/etc/apache2/sites-enabled/caramel";
	$instance->{_conf_location}  = $location;

	#Creating user class instance
	my $class_user = $instance->dir_config('class_user');
	eval("require $class_user") or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
	eval('$instance->{user} = new ' . $class_user . '($instance, $instance);') or die "AF error " . __FILE__ . " line " . __LINE__ . ": $@";
	$instance->{user}->load_by_user(getpwuid($<) || getlogin || "robot");

	return $instance;
}
# }}}

#{{{ log
=head2 log

	Send log message to syslog 

=cut
sub log {
	my ($self, $message) = @_;
	syslog("info", "$message");
}
#}}}

#{{{ error 
=head2 error

	Senderror message to syslog 

=cut
sub error {
	my ($self, $message) = @_;
	syslog("err", "$message");
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
# }}}

#{{{ set_local_locale
=head2 set_local_locale

Set locale and save original locale to LIFO.

=cut
sub set_local_locale {
	my ($self, $locale) = @_;

	if ( ! $locale ) { $locale = "C"; }   
	if ( ! $self->{local_locale} ) { $self->{local_locale} = []; }   
	setlocale( POSIX::LC_ALL, $locale );
	push ( @{$self->{local_locale}}, $locale );
}
# }}}

#{{{ location
=head2 location 

Return location with application configuration

Parameters:

=over 4

=item * $data - Hash from Apache::ConfigFile method

=back

=cut 
sub config_location {
	my ($self) = @_;
	my $ac;
	
	if ( ! exists($self->{_config_hash} ) ) {
		if ( -e $self->{_conf_file} ) {
			$ac = Apache::ConfigFile->read($self->{_conf_file});
		} else {
			die "AF error " . __FILE__ . " line " . __LINE__ . ": Cannot found configure file $self->{_conf_file}.";
		}
		
		if ( $ac->cmd_config("VirtualHost") ) {
			my $vh = $ac->cmd_context(VirtualHost => $ac->cmd_config("VirtualHost"));
			if ( $vh->cmd_config("IfModule") ) {
				my $md = $vh->cmd_context(IfModule => 'mod_perl.c');
				my $loc = $md->cmd_context(Location => $self->{_conf_location});
				if ( ref($loc) eq 'Apache::ConfigFile' ) { 
					my %hash = $loc->cmd_config_hash('PerlSetVar');
					$self->{_config_hash} = \%hash; 
				} else {
					die "AF error " . __FILE__ . " line " . __LINE__ . ": Cannot found location $self->{_conf_location}.";
				}
			} else {
				die "AF error " . __FILE__ . " line " . __LINE__ . ": Cannot found IfModule directive with mod_perl.c value.";
			}
		} else {
			die "AF error " . __FILE__ . " line " . __LINE__ . ": Cannot found VirtualHost directive.";
		}
	}
	return($self->{_config_hash});
}
# }}}

#{{{ dir_config
=head2 dir_config

Return value of PerlSetVar directive on Apache config file used by AFv2

=head3 Parameters

=over 4

=item * $varname - Hash from Apache::ConfigFile method

=back

=cut 
sub dir_config {
	my ($self, $varname) = @_;

	foreach my $key ( keys(%{$self->config_location()}) )  {
		if ( $key eq $varname ) {
			return($self->config_location()->{$key}->[0]);
		}
	}
	return(undef);
}
#}}}

#{{{ to_time_piece
=head2 to_time_piece

Convert string with date in %Y-%m-%d %H:%M:%S
format to instance of Time::Piece class

=over Parameters

=item $value - input string with date and time

=item return instance of Time::Piece

=back 

=cut 
sub to_time_piece {
	my ( $self, $value ) = @_;
	if ( $value && $value =~ /(\d{4})-(\d{2})-(\d{2}).(\d{2}):(\d{2}):(\d{2})/  ) {
		$value = Time::Piece->strptime("$1-$2-$3 $4:$5:$6", "%Y-%m-%d %H:%M:%S");
	} elsif ( $value && $value =~ /(\d{4})-(\d{2})-(\d{2})/  ) {
		$value = Time::Piece->strptime("$1-$2-$3", "%Y-%m-%d");
	} elsif ( $value && $value =~ /(\d{4})(\d{2})(\d{2})/  ) {
		$value = Time::Piece->strptime("$1-$2-$3", "%Y-%m-%d");
	}
	return($value);
}
# }}}

#{{{ memd
=head2 memd

Simulate memd from Cafe::Application

=cut 
sub memd {
	my ( $self ) = @_;
	return(undef);
}
#}}}

1;
