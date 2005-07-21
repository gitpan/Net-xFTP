package Net::xFTP;

require 5.001;

use warnings;

use strict;
use vars qw(@ISA $VERSION %CONSTANTS);
use Carp;
use Cwd 'cwd';
use File::Copy;
#use Net::SFTP::Constants qw(SSH2_FXF_WRITE SSH2_FXF_CREAT SSH2_FXF_TRUNC);

#use Net::FTP;
#use Net::SFTP;
our $haveFTP = 0;
our $haveSFTP = 0;
our $haveSFTPConstants = 0;

eval 'use Net::FTP; $haveFTP = 1; 1';
eval 'use Net::SFTP; $haveSFTP = 1; 1';
eval 'use Net::SFTP::Constants qw(SSH2_FXF_WRITE SSH2_FXF_CREAT SSH2_FXF_TRUNC); $haveSFTPConstants = 1; 1';

#die "..Must have either Net::FTP and or Net::SFTP!"
#		unless ($haveFTP || $haveSFTP);

our $VERSION = '0.11';

{
	no warnings 'redefine';
	sub cwd  #SET THE "CURRENT" DIRECTORY.
	{
		my $self = shift;
		my $cwd = shift || '/';

		my $ok;
		if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
		{
			$ok = $self->{xftp}->cwd($cwd);
			$self->{cwd} = $cwd  if ($ok);
		}
		elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
		{
			my $fullwd;
			eval { $fullwd = $self->{xftp}->do_realpath($cwd) };
			if ($fullwd)
			{
				$self->{cwd} = $fullwd;
				$ok = 1;
			}
		}
		elsif (!$self->{pkg})
		{
			$self->{cwd} = $cwd;
			$ok = 1;
		}
		return $ok ? 1 : undef;
	}

	sub copy
	{
		my $self = shift;

		return undef  unless (@_ >= 2);
		my @args = @_;
		if (!$self->{pkg} || $self->{pkg} =~ /Net::SFTP/)
		{
			$args[0] = $self->{cwd} . '/' . $args[0]  unless ($args[0] =~ m#^\/#);
			$args[1] = $self->{cwd} . '/' . $args[1]  unless ($args[1] =~ m#^\/#);
		}
		if ($self->isadir($args[1]))
		{
			my $filename = $1  if ($args[0] =~ m#([^\/]+)$#);
			$args[1] .= '/'  unless ($args[1] =~ m#\/$#);
			$args[1] .= $filename;
		}

		my $ok;
		if (!$self->{pkg})
		{
			$ok = File::Copy::copy($args[0], $args[1]);
			unless ($ok)
			{
				$self->{xftp_lastmsg} = $! || 'Local copy failed for unknown reasons';
			}
		}
		elsif ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
		{
			my ($tmp, $t);
			my $fromHandle;
			eval { $fromHandle = $self->{xftp}->retr($args[0]) };
			unless ($fromHandle)
			{
				$self->{xftp_lastmsg} = "Copy failed (". ($@||'retr failed - Unknown reason')
						. ')!';
				return undef;
			}
			while ($fromHandle->read($tmp, $self->{BlockSize}))
			{
				$t .= $tmp;
			}
			$fromHandle->close();
			my $toHandle;
			eval { $toHandle = $self->{xftp}->stor($args[1]) };
			unless ($toHandle)
			{
				$self->{xftp_lastmsg} = "Copy failed (". ($@||'stor failed - Unknown reason')
						. ')!';
				return undef;
			}
			eval { $toHandle->write($t, length($t)) };
			if ($@)
			{
				$self->{xftp_lastmsg} = "Copy failed (". ($@||'write failed - Unknown reason')
						. ')!';
				return undef;
			}
			$toHandle->close();
			$ok = 1;
		}
		elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
		{
			unless ($haveSFTPConstants)
			{
				$self->{xftp_lastmsg} = 
					"Copy failed (You must install the Net::SFTP::Constants Perl module!)";
				return undef;
			}
			my ($tmp, $t);
			my $fromHandle;
			eval { $fromHandle = $self->{xftp}->do_open($args[0], 0) };
			unless ($fromHandle)
			{
				$self->{xftp_lastmsg} = "Copy failed (". ($@||'do_open1 failed - Unknown reason')
						. ')!';
				return undef;
			}
			my $offset = 0;
			my $err;
			while (1)
			{
				($tmp, $err) = $self->{xftp}->do_read($fromHandle, $offset, $self->{BlockSize});
				last  if (defined $err);
				$t .= $tmp;
				$offset += $self->{BlockSize};
			}
			$self->{xftp}->do_close($fromHandle);
			my $toHandle;
			eval { no strict 'subs'; $toHandle = $self->{xftp}->do_open($args[1], 
					SSH2_FXF_WRITE | SSH2_FXF_CREAT | SSH2_FXF_TRUNC) };
			unless ($toHandle)
			{
				$self->{xftp_lastmsg} = "Copy failed (". ($@||'do_open2 failed - Unknown reason')
						. ')!';
				return undef;
			}
			eval { $self->{xftp}->do_write($toHandle, 0, $t) };
			if ($@)
			{
				$self->{xftp_lastmsg} = "Copy failed (". ($@||'write failed - Unknown reason')
						. ')!';
				return undef;
			}
			$self->{xftp}->do_close($toHandle);
			$ok = 1;
		}
		return $ok ? 1 : undef;
	}

	sub move
	{
		my $self = shift;

		return undef  unless (@_ >= 2);
		return ($self->copy(@_) && $self->delete($_[0])) ? 1 : undef;
	}
}

sub new
{
	my $class = shift;
	my $xftp = bless { }, $class;
	$@ = '';
	$xftp->{pkg}  = shift || 0;
	$xftp->{pkg} =~ s/\s+//g;
	$xftp->{pkg} = 'Net::' . $xftp->{pkg}  unless (!$xftp->{pkg} || $xftp->{pkg} =~ /^Net/);
	my $host = shift;
	my %args = @_;
	my %xftp_args;
	$xftp->{xftp_lastmsg} = '';
	$xftp->{cwd} = '.';
	$xftp->{BlockSize} = $args{BlockSize} || 10240;
	foreach my $i (keys %args)
	{
		if ($i =~ s/^xftp_//)   #EXTRACT OUT OUR SPECIAL ARGS ("xftp_*")
		{
			$xftp_args{$i} = $args{"xftp_$i"};

			delete $args{"xftp_$i"};
		}
	}
	if ($xftp->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		foreach my $i (keys %args)
		{
			delete $args{$i}  if ($i =~ /^ftp_/)   #EXTRACT OUT OUR SPECIAL ARGS ("xftp_*")
		}
		delete($args{BlockSize})  if (defined $args{BlockSize});
		my $saveEnvHome = $ENV{HOME};
		$ENV{HOME} = $xftp_args{home}  if ($xftp_args{home});
		eval { $xftp->{xftp} = Net::SFTP->new($host, %args, warn => \&sftpWarnings); };
		$xftp->{xftp_lastmsg} = $@  if ($@);
		$ENV{HOME} = $saveEnvHome;
		if ($xftp->{xftp})
		{
			my $cwd;
			eval { $cwd = $xftp->{xftp}->do_realpath('.') };
			$xftp->{cwd} = $cwd  if ($cwd);
			return $xftp;
		}
	}
	elsif ($xftp->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		foreach my $i (keys %args)
		{
			delete $args{$i}  if ($i =~ /^sftp_/)   #EXTRACT OUT OUR SPECIAL ARGS ("xftp_*")
		}
		$xftp->{xftp} = Net::FTP->new($host, %args);
		unless (defined $xftp->{xftp})
		{
			$xftp->{xftp_lastmsg} = $@;
			return;
		}
		if (defined $args{user})
		{
			$args{user} ||= 'anonymous';
			$args{password} ||= 'anonymous@'  if ($args{user} eq 'anonymous');
			my @loginargs = ($args{user});
			push (@loginargs, $args{password})  if (defined $args{password});
			push (@loginargs, $args{account})  if (defined $args{account});
			if ($xftp->{xftp}->login(@loginargs))
			{
				my $cwd = $xftp->{xftp}->pwd();
				$xftp->{cwd} = $cwd  if ($cwd);
				return $xftp;
			}
		}
		else
		{
			return $xftp  if ($xftp->{xftp}->login());
		}
		$@ ||= 'Invalid Password?';
		return;
	}
	elsif (!$xftp->{pkg} || $xftp->{pkg} =~ /local/i)
	{
		$xftp->{cwd} = Cwd::cwd();
		$xftp->{pkg} = '';
		$xftp->{xftp} = 1;
		return $xftp;
	}
	else
	{
		@_ = "Do not have package \"$xftp->{pkg}\"!";
		return;
	}
}

sub haveFTP
{
	return $haveFTP;
}

sub haveSFTP
{
	return $haveSFTP;
}

sub haveModules
{
	return { 'Net::FTP' => $haveFTP, 'Net::SFTP' => $haveSFTP };
}

sub protocol
{
	my $self = shift;

	return $self->{pkg};
}

sub ascii
{
	my $self = shift;

	$self->{xftp}->ascii()  if ($self->{pkg} =~ /Net::FTP/ && $haveFTP);
	return;
}

sub binary
{
	my $self = shift;

	$self->{xftp}->binary()  if ($self->{pkg} =~ /Net::FTP/ && $haveFTP);
	return;
}

sub quit
{
	my $self = shift;
	if ($self->{pkg} =~ /Net::FTP/)
	{
		$self->{xftp}->quit();
	}
	else
	{
		$self->{xftp} = undef;
		delete($self->{xftp});
	}
	return;
}

sub ls
{
	my $self = shift;
	my $path = shift || '';
	my $showall = shift || 0;
	my @dirlist;
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		@dirlist = $self->{xftp}->ls($path||'.');
		shift (@dirlist)  if ($dirlist[0] =~ /^total \d/);  #REMOVE TOTAL LINE!
		my $i = 0;
		while ($i<=$#dirlist)
		{
			#$dirlist[$i] =~ s#\/\/#\/#;
			$dirlist[$i] = $1  if ($dirlist[$i] =~ m#([^\/\\]+)$#);
			$dirlist[$i] = $1  if ($dirlist[$i] =~ /\/(\.\.?)$/);
			if ($dirlist[$i] eq '..' && $path eq '/')
			{
				splice(@dirlist, $i, 1);
			}
			elsif (!$showall && $dirlist[$i] =~ /^\.[^\.]/)
			{
				splice(@dirlist, $i, 1);
			}
			else
			{
				++$i;
			}
		}
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		my $realpath;
		eval { $realpath = $self->{xftp}->do_realpath($path||$self->{cwd}||'.') };
		chomp $realpath;
		$realpath = $self->{cwd} . '/' . $realpath  unless ($realpath =~ m#^\/#);
		my @dirHash;
		eval { @dirHash = $self->{xftp}->ls($realpath) };
		return  if ($@);
		shift (@dirHash)  if ($dirHash[0]->{longname} =~ /^total \d/);  #REMOVE TOTAL LINE!
		my $t;
		@dirlist = ();
		for (my $i=0;$i<=$#dirHash;$i++)
		{
			$t = $dirHash[$i]->{filename};
			next  if ($t eq '..' && $path eq '/');
			next  if (!$showall && $t =~ /^\.[^\.]/);
			push (@dirlist, $t);
		}
	}
	elsif (!$self->{pkg})
	{
		my $realpath = $path || Cwd::cwd();
		if ($realpath eq '..')
		{
			$realpath = Cwd::cwd();
			chop $realpath  if ($realpath =~ m#\/$#);
			$realpath =~ s#\/[^\/]+##;
		}
		$realpath = $self->{cwd} . '/' . $realpath  unless ($realpath =~ m#^\/#);
		my $t;
		@dirlist = ();
		if (opendir D, $realpath)
		{
			while ($t = readdir(D))
			{
				next  if ($t =~ /^total \d/);
				next  if ($t eq '..' && $path eq '/');
				next  if (!$showall && $t =~ /^\.[^\.]/);
				push (@dirlist, $t);
			}
		}
		else
		{
			$self->{xftp_lastmsg} = $! || 'Local ls failed for unknown reasons';
			return;
		}
	}
	else
	{
		return;
	}
	@dirlist = sort @dirlist;

	##ON SOME SERVERS, THESE DON'T GET ADDED ON, SO ADD THEM HERE!
	#unshift (@dirlist, '..')  unless ($path eq '/' || $dirlist[1] eq '..');
	#unshift (@dirlist, '.')  unless ($dirlist[0] eq '.');

	return wantarray ? @dirlist : \@dirlist;
}

sub dir
{
	my $self = shift;
	my $path = shift || '';
	my $showall = shift || 0;
	my @dirlist;
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		@dirlist = $self->{xftp}->dir($path||'.');
		shift (@dirlist)  if ($dirlist[0] =~ /^total \d/);  #REMOVE TOTAL LINE!
		my $i = 0;
		while ($i<=$#dirlist)
		{
			#$dirlist[$i] =~ s#\/\/#\/#;
			$dirlist[$i] = $1  if ($dirlist[$i] =~ m#([^\/\\]+)$#);
			$dirlist[$i] = $1  if ($dirlist[$i] =~ /\/(\.\.?)$/);
			if ($dirlist[$i] =~ /\d \.\.$/ && $path eq '/')
			{
				splice(@dirlist, $i, 1);
			}
			elsif (!$showall && $dirlist[$i] =~ /\d \.[^\.]\S*$/)
			{
				splice(@dirlist, $i, 1);
			}
			else
			{
				++$i;
			}
		}
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		my $realpath;
		eval { $realpath = $self->{xftp}->do_realpath($path||$self->{cwd}||'.') };
		chomp $realpath;
		$realpath = $self->{cwd} . '/' . $realpath  unless ($realpath =~ m#^\/#);
		my @dirHash;
		eval { @dirHash = $self->{xftp}->ls($realpath) };
		return  if ($@);
		shift (@dirHash)  if ($dirHash[0]->{longname} =~ /^total \d/);  #REMOVE TOTAL LINE!
		my $t;
		@dirlist = ();
		for (my $i=0;$i<=$#dirHash;$i++)
		{
			$t = $dirHash[$i]->{longname};
			next  if ($t =~ /\d \.\.$/ && $path eq '/');
			next  if (!$showall && $t =~ /\d \.[^\.]\S*$/);
			push (@dirlist, $t);
		}
	}
	elsif (!$self->{pkg})
	{
		my $realpath = $path || Cwd::cwd();
		if ($realpath eq '..')
		{
			$realpath = Cwd::cwd();
			chop $realpath  if ($realpath =~ m#\/$#);
			$realpath =~ s#\/[^\/]+##;
		}
		$realpath = $self->{cwd} . '/' . $realpath  unless ($realpath =~ m#^\/#);
		my $t;
		my @d = $showall ? `ls -la $realpath` : `ls -la $realpath`;
		if (@d)
		{
			shift @d  if ($d[0] =~ /^total \d/);   #REMOVE "TOTAL" LINE.
			foreach my $t (@d)
			{
				chomp $t;
				next  if ($t =~ /\d \.\.$/ && $path eq '/');
				next  if (!$showall && $t =~ /\d \.[^\.]\S*$/);
				push (@dirlist, $t);
			}
			
		}
		elsif ($@)
		{
			$self->{xftp_lastmsg} = $@;
			return;
		}
	}
	else
	{
		return;
	}

	##ON SOME SERVERS, THESE DON'T GET ADDED ON, SO ADD THEM HERE!
	#unshift (@dirlist, '..')  unless ($path eq '/' || $dirlist[1] =~ /\d \.\.$/);
	#unshift (@dirlist, '.')  unless ($dirlist[0] =~ /\d \.$/);

	return wantarray ? @dirlist : \@dirlist;
}

sub pwd  #GET AND RETURN THE "CURRENT" DIRECTORY.
{
	my $self = shift;
	my $cwd;
	if ($self->{pkg} =~ /Net::FTP/)
	{
		$cwd = $self->{xftp}->pwd();
		$self->{cwd} = $cwd  if ($cwd);
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		$self->{cwd} = $cwd  if ($cwd);
	}
	elsif (!$self->{pkg})
	{
		$self->{cwd} = Cwd::cwd() || $ENV{PWD};
	}
	return $self->{cwd};
}

sub get    #(Remote, => Local)
{
	my $self = shift;

	return undef  unless (@_ >= 1);
	my @args = @_;
	if (!$self->{pkg} or $self->{pkg} =~ /Net::SFTP/)
	{
		$args[0] = $self->{cwd} . '/' . $args[0]  unless ($args[0] =~ m#^\/#);
		unless (@args >= 2)
		{
			if (ref(\$args[1]) eq 'GLOB')
			{
				$self->{xftp_lastmsg} = 'Must specify a remote filename (2nd argument) since 1st arg. is a filehandle!';
				return undef;
			}
		}
	}
	unless (@args >= 2)
	{
		$args[1] = $args[0];
		$args[1] = $1  if ($args[1] =~ m#([^\/\\]+)$#);
	}
	my $ok;
	if (!$self->{pkg})
	{
		if (ref(\$args[1]) eq 'GLOB')
		{
			my $buff;
			my $unsubscriptedFH = $args[1];

			flush $unsubscriptedFH;  #DOESN'T SEEM TO HELP - NEEDED IN CALLING ROUTINE TOO?!?!?!

			local *TF;
			unless (open(TF, $args[0]))
			{
				$self->{xftp_lastmsg} = "Could not open remote file ($args[0]) ("
						. ($! ? $! : 'unknown reasons') .')!';
			}
			while ($buff = <TF>)
			{
				print $unsubscriptedFH $buff;
			}
			close TF;
			flush $unsubscriptedFH;
			return 1;
		}
		else
		{
			$ok = File::Copy::copy($args[0], $args[1]);
		}
		unless ($ok)
		{
			$self->{xftp_lastmsg} = $! || 'Local copy failed for unknown reasons';
		}
	}
	else
	{
		if ($self->{pkg} =~ /Net::SFTP/ && ref(\$args[1]) eq 'GLOB')
		{
			my $remoteHandle;
			my $offset = 0;
			my $buff;
			my $unsubscriptedFH = $args[1];
			eval { $remoteHandle = $self->{xftp}->do_open($args[0], 0) };
			if ($remoteHandle)
			{
				my $err;
				while (1)
				{
					($buff, $err) = $self->{xftp}->do_read($remoteHandle, $offset, $self->{BlockSize});
					last  if (defined $err);
					print $unsubscriptedFH $buff;
					$offset += $self->{BlockSize};
				}
				$self->{xftp}->do_close($remoteHandle);
				return 1;
			}
			else
			{
				$self->{xftp_lastmsg} = $@ || 'Could not open remote handle for unknown reasons!';
				return undef;
			}
		}
		else
		{
			if ($self->{pkg} =~ /Net::SFTP/)
			{
				eval { $self->{xftp}->get(@args) };
				if ($@)
				{
					$self->{xftp_lastmsg} = $@;
					return undef;
				}
				else
				{
					return 1;
				}
			}
			else
			{
				eval { $ok = $self->{xftp}->get(@args) };
			}
			$self->{xftp_lastmsg} = $@  if ($@);
		}
	}
	return $ok ? 1 : undef;
}

sub put    #(LOCAL => REMOTE) SFTP returns OK=1 on SUCCESS.
{
	my $self = shift;

	return undef  unless (@_ >= 1);
	my @args = @_;
	unless (@args >= 2 || ref(\$args[0]) eq 'GLOB')
	{
		$args[1] = $args[0];
		$args[1] = $1  if ($args[1] =~ m#([^\/\\]+)$#);
	}
	if ($self->{pkg} =~ /Net::SFTP/)
	{
		$args[1] = $self->{cwd} . '/' . $args[1]  unless ($args[1] =~ m#^\/#);
	}

	my $ok;
	if (!$self->{pkg})
	{
		$args[1] = $self->{cwd} . '/' . $args[1]  unless ($args[1] =~ m#^\/#);
		if (ref(\$args[0]) eq 'GLOB')
		{
			my $buff;
			my $unsubscriptedFH = $args[0];

			local *TF;
			unless (open(TF, ">$args[1]"))
			{
				$self->{xftp_lastmsg} = "Could not open remote file ($args[1]) ("
						. ($! ? $! : 'unknown reasons') .')!';
			}
			my $t;
			while ($buff = <$unsubscriptedFH>)
			{
				$t .= $buff;
			}
			print TF $t;
			close TF;
			return 1;
		}
		else
		{
			$ok = File::Copy::copy($args[0], $args[1]);
		}
		unless ($ok)
		{
			$self->{xftp_lastmsg} = $! || 'Local copy failed for unknown reasons';
		}
	}
	else
	{
		if ($self->{pkg} =~ /Net::SFTP/ && ref(\$args[0]) eq 'GLOB')
		{
			unless ($haveSFTPConstants)
			{
				$self->{xftp_lastmsg} = 
					"Copy failed (You must install the Net::SFTP::Constants Perl module!)";
				return undef;
			}
			my $remoteHandle;
			my $offset = 0;
			my $buff;
			my $unsubscriptedFH = $args[0];
			eval { no strict 'subs'; $remoteHandle = $self->{xftp}->do_open($args[1], 
					SSH2_FXF_WRITE | SSH2_FXF_CREAT | SSH2_FXF_TRUNC) };
			if ($remoteHandle)
			{
				my $t;
				while ($buff = <$unsubscriptedFH>)
				{
					$t .= $buff;
				}
				eval { $self->{xftp}->do_write($remoteHandle, 0, $t) };
				if ($@)
				{
					$self->{xftp_lastmsg} = "Put failed (". ($@||'write failed - Unknown reason')
							. ')!';
					return undef;
				}
				$self->{xftp}->do_close($remoteHandle);
				return 1;
			}
			else
			{
				$self->{xftp_lastmsg} = $@ || 'Could not open remote handle for unknown reasons!';
				return undef;
			}
		}
		else
		{
			eval { $ok = $self->{xftp}->put(@args) };
			$self->{xftp_lastmsg} = $@  if ($@);
		}
	}
	return $ok ? 1 : undef;
}

sub delete       #RETURNED OK=2 WHEN LAST FAILED.
{
	my $self = shift;
	my $path = shift;

	my $ok;
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		eval { $ok = $self->{xftp}->delete($path) };
		$self->{xftp_lastmsg} = $@  if ($@);
		return $ok ? 1 : undef;
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		eval { $ok = $self->{xftp}->do_remove($path) };
		$self->{xftp_lastmsg} = $@  if ($@);
		return $@ ? undef : 1;
	}
	elsif (!$self->{pkg})
	{
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		return  unless ($path);
		#!!!!return ($_ == 1) ? 1 : undef;
		return unlink($path) ? 1 : undef;
	}
	return;
}

sub rename
{
	my $self = shift;
	return undef  unless (@_ == 2);

	my ($oldfile, $newfile) = @_;

	my $ok;
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		eval { $ok = $self->{xftp}->rename($oldfile, $newfile) };
		$self->{xftp_lastmsg} = $@  if ($@);
		return $ok ? 1 : undef;
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		$oldfile = $self->{cwd} . '/' . $oldfile  unless ($oldfile =~ m#^\/#);
		$newfile = $self->{cwd} . '/' . $newfile  unless ($newfile =~ m#^\/#);
		eval { $ok = $self->{xftp}->do_rename($oldfile, $newfile) };
		$self->{xftp_lastmsg} = $@  if ($@);
		return $@ ? undef : 1;
	}
	elsif (!$self->{pkg})
	{
		$oldfile = $self->{cwd} . '/' . $oldfile  unless ($oldfile =~ m#^\/#);
		$newfile = $self->{cwd} . '/' . $newfile  unless ($newfile =~ m#^\/#);
		$ok = rename($oldfile, $newfile);
		unless ($ok)
		{
			$self->{xftp_lastmsg} = $! || 'Local rename failed for unknown reasons';
		}
		return $ok ? 1 : undef;
	}
	return;
}

sub mkdir
{
	my $self = shift;
	my $path = shift;
	my $tryRecursion = shift||0;
	$path =~ s#[\/\\]$##  unless ($path eq '/');

	my $ok = '';
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		eval { $ok = $self->{xftp}->mkdir($path, $tryRecursion) };
		$self->{xftp_lastmsg} = $@  if ($@);
		return $ok ? 1 : undef;
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		my $orgPath = $path;
		my $didRecursion = 0;
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		while ($path)
		{
			eval { $ok = $self->{xftp}->do_mkdir($path, Net::SFTP::Attributes->new()) };
			$self->{xftp_lastmsg} = $@  if ($@);
			last  unless ($tryRecursion && $ok ne '0');
			$path =~ s#[^\/\\]+$##;
			$path =~ s#[\/\\]$##;
			$didRecursion = 1;
		}
		if (defined($ok) && $ok eq '0')
		{
			return $didRecursion ? $self->mkdir($orgPath, 1) : 1;
		}
	}
	elsif (!$self->{pkg})
	{
		my $orgPath = $path;
		my $didRecursion = 0;
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		while ($path)
		{
			$ok = mkdir $path;
			$self->{xftp_lastmsg} = $! || 'local mkdir failed for unknown reasons'
					unless ($ok);
			last  unless ($tryRecursion && !$ok);
			$path =~ s#[^\/\\]+$##;
			$path =~ s#[\/\\]$##;
			$didRecursion = 1;
		}
		if (defined($ok) && $ok)
		{
			return $didRecursion ? $self->mkdir($orgPath, 1) : 1;
		}
	}
	return;
}

sub rmdir
{
	my $self = shift;
	my $path = shift;
	$path =~ s#[\/\\]$##  unless ($path eq '/');

	my $ok;
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		eval { $ok = $self->{xftp}->rmdir($path) };
		$self->{xftp_lastmsg} = $@  if ($@);
		return $ok ? 1 : undef;
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		eval { $ok = $self->{xftp}->do_rmdir($path) };
		$self->{xftp_lastmsg} = $@  if ($@);
		return $@ ? undef : 1;
	}
	elsif (!$self->{pkg})
	{
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		return undef  unless ($path);
		$ok  = rmdir $path;
		unless ($ok)
		{
			$self->{xftp_lastmsg} = $! || 'Local rename failed for unknown reasons';
		}
		return $ok ? 1 : undef;
	}
	return;
}

sub message
{
	my $self = shift;

	chomp $self->{xftp_lastmsg};
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		return $self->{xftp}->message;
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		my @res = $self->{xftp}->status;
		return ($self->{xftp_lastmsg} =~ /^\s*$res[0]/) ? $self->{xftp_lastmsg} : "$res[0]: $res[1] - $self->{xftp_lastmsg}";
	}
	else
	{
		return $self->{xftp_lastmsg};
	}
	return;
}

sub sftpWarnings  #ONLY WAY TO GET NON-FATAL WARNINGS INTO $@ INSTEAD OF STDERR IS TO USE THIS CALLBACK!
{                 #(WE ALWAYS WRAP SFTP->METHODS W/AN EVAL)!
	my $self = shift;
	my @res = $self->status;
	die "$res[0]: $res[1] - ".join(' ', @_)."\n";
}

sub size
{
	my $self = shift;
	my $path = shift;

	my $ok;
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		return $self->{xftp}->size($path);
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
print STDERR "-???- CWD undefined!\n"  unless (defined $self->{cwd});
print STDERR "-???- path undefined!\n"  unless (defined $path);
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		eval { $ok = $self->{xftp}->do_stat($path) };
		unless (defined($ok) && $ok)
		{
			$self->{xftp_lastmsg} = $@;
			return undef;
		}
		return $ok->size();
	}
	elsif (!$self->{pkg})
	{
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		eval { (undef, undef, undef, undef, undef, undef, undef, $ok) = stat($path) };
		return $@ ? undef : $ok;
	}
	return;
}

sub isadir
{
	my $self = shift;
	my $path = shift;

	my $ok;
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		my $curdir = $self->{xftp}->pwd();
		eval { $ok = $self->{xftp}->cwd($path); };
		if ($ok)
		{
			$self->{xftp}->cwd($curdir);
			return 1;
		}
		return 0;
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		eval { $ok = $self->{xftp}->do_opendir($path) };
		if (defined($ok) && $ok)
		{
			eval { $self->{xftp}->do_close($ok) };
			return 1;
		}
		return 0;
	}
	elsif (!$self->{pkg})
	{
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		return (-d $path) ? 1 : 0;
	}
	return;
}

sub chmod
{
	my $self = shift;
	my $permissions = shift;
	my $path = shift;

	my ($ok, $attrs);
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		unless ($self->{xftp}->supported('SITE CHMOD'))
		{
			$@ = 'Server does not support chmod!';
			$self->{xftp_lastmsg} = $@;
			$self->{xftp}->set_status(1, $@);
		}
		$ok = $self->{xftp}->site('CHMOD', $permissions, $path);
		return ($ok == 2) ? 1 : undef;
	}
	elsif ($self->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		eval { $attrs = $self->{xftp}->do_stat($path) };
		unless (defined($attrs) && $attrs)
		{
			$self->{xftp_lastmsg} = $@;
			return undef;
		}
		eval "\$permissions = 0$permissions";
		if ($@)
		{
			$self->{xftp_lastmsg} = "Invalid permissions (0-777) - $@";
			return undef;
		}
		$attrs->perm($permissions);
		eval { $ok = $self->{xftp}->do_setstat($path, $attrs) };
print STDERR "-setstat: AT=".($@ ? $@ : 'NULL')."= ok=".(defined($ok) ? $ok : 'UNDEF')."=\n";
		if ($@ || !defined($ok))
		{
			$self->{xftp_lastmsg} = $@;
			return;
		}
		return 1;
	}
	elsif (!$self->{pkg})
	{
		$path = $self->{cwd} . '/' . $path  unless ($path =~ m#^\/#);
		eval "\$permissions = 0$permissions";
		if ($@)
		{
			$self->{xftp_lastmsg} = "Invalid permissions (0-777) - $@";
			return undef;
		}
		$ok = chmod $permissions, $path;
		unless ($ok)
		{
			$self->{xftp_lastmsg} = $! || 'Local rename failed for unknown reasons';
		}
		return $ok ? 1 : undef;
	}
	return;
}

1

__END__

=head1 NAME

Net::xFTP - Common wrapper functions for use with either Net::FTP or Net::xFTP.

=head1 AUTHOR

Jim Turner, C<< <http://home.mesh.net/turnerjw/jim> >>

=head1 COPYRIGHT

Copyright (c) 2005 Jim Turner <http://home.mesh.net/turnerjw/jim>.  
All rights reserved.  

This program is free software; you can redistribute 
it and/or modify it under the same terms as Perl itself.

This is a derived work from Net::FTP and Net::SFTP.  Net::FTP is 
copyrighted by Graham Barr and Net::SFTP is copyrighted by Benjamin Trott 
and maintained by Dave Rolsky.  Both are copyrighted under the same terms 
as this module.  

Many thanks go to these gentlemen whose work made this module possible.

=head1 SYNOPSIS

	use Net::xFTP;

	#Test for needed protocol module.
	die "..This server connection needs Net::SFTP!" 
		unless (Net::xFTP->haveSFTP());

	#Establish a new connection to a remote host.
	$ftp = Net::xFTP->new('SFTP', "some.host.name", Debug => 0,
			user => 'userid', password => 'opensesme')
		or die "Cannot connect to some.host.name: $@";

	#Establish a "local" (simulated connection) to self.
	$ftp = Net::xFTP->new();

	#Change the current working directory on the remote host.
	$ftp->cwd('/pub')  or die 
		"Cannot change working directory ", $ftp->message();

	#Get the current working directory on the remote host.
	my $current_remote_path = $ftp->pwd();

	#Get a list of files and subdirectories in "/pub".
	my @filesAndSubfolders = $ftp->ls('/pub');

	#Get a detailed (ls -l) list of files and subdirectories.
	my @ls_l_details = $ftp->dir('/pub');

	#Create a new subdirectory.
	$ftp->mkdir('myownfolder')
		or die "Cannot make subdirectory ", $ftp->message();

	#Remove an empty subdirectory.
	$ftp->rmdir('myownfolder')
		or die "Cannot remove subdirectory ", $ftp->message();

	#Get the contents of a file on the remote server.
	$ftp->get('remote.file', 'local.file')
		or die "get failed ", $ftp->message();

	#Get the contents of a remote file and write to an open filehandle.
	open FHANDLE, ">local.file" or die "Could not open local file ($!)";
	print FHANDLE "A Header Line!\n";
	flush FHANDLE;
	$ftp->get('remote.file', *FHANDLE)
		or die "get failed ", $ftp->message();
	print FHANDLE "A Footer Line!\n";
	close FHANDLE;

	#Put a local file onto the remote server.
	$ftp->put('local.file', 'remote.file')
		or die "put failed ", $ftp->message();

	#Read from a file handle putting the content in a remote file.
	open FHANDLE "<local.file" or die "Could not open local file ($!)";
	$ftp->put(*FHANDLE, 'remote.file')
		or die "put failed ", $ftp->message();
	close FHANDLE;

	#Delete a remote file.
	$ftp->delete('some.file')
		or die "Cannot delete file ", $ftp->message();

	#Rename a remote file.
	$ftp->rename('oldfilename', 'newfilename')
		or die "Cannot delete file ", $ftp->message();

	#Change permissions of a remote file.
	$ftp->chmod(755, 'some.file.or.dir')
		or die "Cannot change permissions ", $ftp->message();

	#Fetch the size of a remote file.
	print "remote.file has ".$ftp->size('remote.file')." bytes.\n";

	#Copy a remote file to a new remote location.
	$ftp->copy('remote.fileA','remote.fileB')
		or die "Cannot copy the file ", $ftp->message();

	#Move a remote file to a new remote location.
	$ftp->move('old/path/old.filename', 'new/path/new.filename')
		or die "Cannot move the file ", $ftp->message();

	#Disconnect an existing connection.
	$ftp->quit();

=head1 PREREQUISITES

Even though Net::xFTP will work in a connection-simulating "I<local>" mode, 
to be truly useful, one needs either C<Net::FTP>, C<Net::SFTP>, or 
preferrably both.  

C<Net::SFTP::Attributes> is also needed, if using Net::SFTP.

C<Net::SFTP::Constants> is also needed for using the I<copy>, 
I<move> functions, or using the I<put> function with a filehandle.

=head1 DESCRIPTION

C<Net::xFTP> is a wrapper class to combine common functions of Net::FTP and 
Net::SFTP into a single set of functions allowing one to switch seemlessly 
between the two without having to make non-trivial code changes.  Only  
functionality common to both protocols has been implemented here with the 
intent and invitation to add more functions and features and mayby other 
*FTP-ish modules in the future.

=head1 PURPOSE

I created this module when I had developed several web application 
programs which FTP'd data to and from a central server via Net::FTP.  
The client changed to a new remote server that required Net::SFTP.  Faced 
with rewriting these programs without changing functionality (since for 
some reason Net::FTP and Net::SFTP use slightly different methods and 
conventions).  I decided instead to simply create a common module that 
would use the same method calls to do the same things and allow me to 
specify the protocol in a single place.  I also am the author of I<ptkftp>, 
a Perl/Tk graphical user-interface to Net::FTP and Net::SFTP.  I now 
intend to rewrite it to use Net::xFTP and greatly reduce and simplify 
the code for that application.

Hopelfully others will find this module useful.  Patches adding needed 
functionality are welcome.  

=head1 CONSTRUCTOR

=over 4

=item new ( PROTOCOL, HOST [, OPTIONS ])

This is the constructor for a new Net::FTP object.  The first two 
arguments are required and are positional.  Sebsequent arguments (OPTIONS) 
are in the form "name => value".  It returns a Net::xFTP handle object, 
or I<undef> on failure.  If it fails, the reason will be in $@.

C<PROTOCOL> is the underling module or protocol name.  Currently valid 
values are:  C<FTP>, C<SFTP>, C<Net::FTP>, and C<Net::SFTP>.  There are only
two real options - one may either include or omit the "Net::" part.  A third 
option is to pass I<"local">, zero, an empty string, or I<undef> in which 
case the functions are mapped over the local machine, accessable as if 
connected via ftp!  For example, the I<get> and I<put> methods simply copy 
files from one directory to another on the user's local machine.  
If C<PROTOCOL> is local, then the other options, ie. C<HOST> are optional.
Default is I<local> (no remote connection).

C<HOST> is the name of the remote host to which an FTP connection is 
required (except with the I<local> protocol.

C<OPTIONS> are passed in a hash like fashion, using key and value pairs.
Possible options are:

B<user> is the user-name or login-id to log in with.  For FTP, if not 
specified, then 'anonymous' is used.

B<password> is the password, if required, for connecting.  For FTP, if 
not specified, then 'anonymous@' is used.

B<BlockSize> specifies the buffer size to use for buffered data transfers.  
Default is 10240.  

B<Debug> specifies the debug level for FTP and toggles it for SFTP.  
Default is zero (I<false>), which turns debug off for both.  Set the 
numeric level (non-zero) for FTP, and SFTP will accept it as I<true> and 
turn on debugging.

B<xftp_home> specifies an alternate directory for SFTP to create the ".ssh" 
subdirectory for keeping track of "known hosts".  The default is 
$ENV{HOME}.  This option is useful for web CGI scripts which run often 
under a user with no "home" directory.  The format is: 
"/some/path/that/the/user/can/write/to".

To specify protocol-specific args Not to be passed if the other protocol 
is used, append "protocol_" to the option, ie. "sftp_ssh_args" to specify 
the SFTP option "ssh_args".  

=back

=head1 METHODS

Unless otherwise stated all methods return either a I<true> or I<false>
value, with I<true> meaning that the operation was a success. When a method
states that it returns a value, failure will be returned as I<undef> or an
empty list.

=over 4

=item ascii

Transfer file in ASCII, if using FTP. CRLF translation will be done if 
required.  This is a do-nothing method for SFTP and I<local>.

Always returns I<undef>.

=item binary

Transfer file in binary mode. No transformation will be done if using 
FTP.  This is a do-nothing method for SFTP and I<local>.

Always returns I<undef>.

=item chmod ( PERMISSIONS, PATH )

Sets the permissions on C<PATH>, which can be either a file or subdirectory.  
C<PERMISSIONS> is an octal number expressed as a decimal.  Common values are 
777 (full access), 755 (rwxr-xr-x) and 644 (rw-r--r--).

Returns 1 if successful, I<undef> if fails.

=item copy ( OLDFILE, NEWFILE )

Copies the file C<OLDFILE> to C<NEWFILE>, creating or overwriting it if 
necessary.  C<OLDFILE> and C<NEWFILE> may be in different directories.

Returns 1 if successful, I<undef> if fails.

=item cwd ( [ DIR ] )

Attempt to change directory to the directory given in C<$dir>.  If
C<$dir> is C<"..">, the FTP C<CDUP> command is used to attempt to
move up one directory.  If no directory is given then an attempt is made
to change the directory to the root directory.  For SFTP, the new directory 
is saved and subsequent relative paths have this value appended to them.

Returns 1 if successful, I<undef> if fails.

=item delete ( FILENAME )

Send a request to the server to delete C<FILENAME>.  Calls either the 
FTP->delete method or SFTP->do_remove method.  For local, calls Perl's 
I<unlink> function.

Returns 1 if successful, I<undef> if fails.

=item dir ( [ DIR [, SHOWALL ]] )

Get a directory listing of C<DIR>, or the current directory in long (ls -l) 
format.  See also the C<ls> method.

C<DIR> specifies the absolute or relative path.  Default is "." (Current 
working directory).  ".." is also valid.

C<SHOWALL> - if I<true>, all files and subdirectory names will be listed.
If I<false>, "hidden" files and subdirectories (those whose names begin 
with a ".") will be omitted.  Default is I<false>.

In an array context, returns a sorted list of lines returned from the 
server. In a scalar context, returns a reference to the list.  Each line 
consists of either a file or subdirectory name or "." or "..".  ".." 
is omitted if C<DIR> is "/".  

Returns I<undef> on failure.

=item get ( REMOTE_FILE [, LOCAL_FILE ] )

Get C<REMOTE_FILE> from the server and store locally.  If C<LOCAL_FILE>
is not specified, then a file with the same name as C<REMOTE_FILE> sans 
the path information will be created on the current working directory of 
the machine the program is running on.  C<LOCAL_FILE> can also be an open 
file-handle (see example in the C<SYNOPSIS> section).  If so, it must be 
passed as a typeglob.  For I<local> protocol, simply copys C<REMOTE_FILE> 
to C<LOCAL_FILE>.

Returns 1 if successful, I<undef> if fails.

=item isadir ( DIR )

Returns 1 (I<true>) if C<DIR> is a subdirectory, 0 (I<false>) otherwise.

=item ls ( [ DIR [, SHOWALL ]] )

Get a directory listing of C<DIR>, or the current directory.  Just the file 
and or subfolder names are returned.  For a full listing (like C<ls -l>), 
see the C<dir> method.

C<DIR> specifies the absolute or relative path.  Default is "." (Current 
working directory).  ".." is also valid.

C<SHOWALL> - if I<true>, all files and subdirectory names will be listed.
If I<false>, "hidden" files and subdirectories (those whose names begin 
with a ".") will be omitted.  Default is I<false>.

In an array context, returns a sorted list of lines returned from the 
server. In a scalar context, returns a reference to the list.  Each line 
consists of either a file or subdirectory name or "." or "..".  ".." 
is omitted if C<DIR> is "/".  

Returns I<undef> on failure.

=item message ()

Returns the last error message from the most recent method call.  For FTP, 
simply calles I<$FTP->message()>.  For SFTP, we must eval / trap the error 
from @_ and or use some method's call-back function option.

=item mkdir ( DIR [, RECURSE ])

Create a new directory with the name C<DIR>. If C<RECURSE> is I<true> then
C<mkdir> will attempt to create all the directories in the given path.

Calls the C<mkdir> method in FTP or C<do_mkdir> method in SFTP.

Returns 1 if successful, I<undef> if fails.

=item move ( OLDFILE, NEWFILE )

Moves the file C<OLDFILE> to C<NEWFILE>, creating or overwriting it if 
necessary.  C<OLDFILE> and C<NEWFILE> may be in different directories, 
unlike I<rename>, which can only change the name (in the same path).  
Essentially does a I<copy>, followed by a I<delete>, if successfully 
copied.

Returns 1 if successful, I<undef> if fails.

=item Net::xFTP->haveFTP ()

Returns 1 if Net::FTP is installed, 0 otherwise.

=item Net::xFTP->haveSFTP ()

Returns 1 if Net::SFTP is installed, 0 otherwise.

=item Net::xFTP->haveModules ()

Returns a reference to a hash in the form: 
{ 'Net::FTP' => 1|0, 'Net::SFTP' => 1|0 }

=item new ( PROTOCOL, HOST [, OPTIONS ])

This is the constructor.  It returns either a Net::xFTP object or I<undef> 
on failure.  For details, see the "CONSTRUCTOR" section above.  For FTP, 
this method also calls the "login" method to connect.

Returns a Net::xFTP handle object, or I<undef> on failure.  If it fails, 
the reason will be in $@.

=item protocol ()

Returns either C<Net::FTP> or C<Net::SFTP>, depending on which underlying 
module is being used.  Returns an empty string is C<local> is used.

=item put ( LOCAL_FILE [, REMOTE_FILE ] )

Put a file on the remote server. C<LOCAL_FILE> and C<REMOTE_FILE> are 
specified as strings representing the absolute or relative path and file 
name.  If C<REMOTE_FILE> is not specified then the file will be stored in 
the current working directory on the remote machine with the same fname 
(sans directory information) as C<LOCAL_FILE>.  C<LOCAL_FILE> can also be 
an open file-handle (see example in the C<SYNOPSIS> section).  If so, it 
must be passed as a typeglob and C<REMOTE_FILE> must be specified.  For 
I<local> protocol, simply copies C<LOCAL_FILE> to C<REMOTE_FILE>.

Returns 1 if successful, I<undef> if fails.

B<NOTE>: If for some reason the transfer does not complete and an error is
returned then the contents that had been transfered will not be remove
automatically.

=item pwd ()

Returns the full pathname of the current working directory.

=item quit ()

Calls FTP->quit() for FTP, For SFTP, which does not have a terminating 
method, simply deletes the SFTP object.

=item rename ( OLDNAME, NEWNAME )

Rename a file on the remote FTP server from "OLDNAME" to "NEWNAME".  
Calls the I<rename> method for FTP and I<do_rename> for SFTP.  For 
I<local> protocol, simply renames the file.

Returns 1 if successful, I<undef> if fails.

=item rmdir ( DIR )

Remove the directory with the name C<DIR>.  The directory must first be 
empty to remove.  Calls the I<rmdir> method for FTP and I<do_rmdir> for 
SFTP.  For I<local> protocol, simiply removes the directory.

Returns 1 if successful, I<undef> if fails.

=item size ( FILE )

Returns the size in bytes of C<FILE>, or I<undef> on failure.  For FTP, 
the I<size> method is called, for SFTP:  I<do_stat>.  For <local>, perl's 
I<stat> function.

=item Other methods

Even though C<Net::xFTP> is designed for commonality, it may occassionally 
be necessary to call a method specific to a given protocol.  To do this,
simply invoke the method as follows:

$ftp->{xftp}->method ( args )

Example:

print "-FTP size of file = ".$ftp->{xftp}->size('/pub/myfile').".\n"
		if ($ftp->protocol() eq 'Net::FTP');

=item sftpWarnings

Internal module used to capture non-fatal warning messages from Net::SFTP 
methods.

=back

=head1 TODO

Add a C<stat> method when this is supported in Net::FTP.

=head1 BUGS

Please report any bugs or feature requests to
C<bug-net-xftp@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-xFTP>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

This is a derived work from Net::FTP and Net::SFTP.  Net::FTP is 
copyrighted by Graham Barr and Net::SFTP is copyrighted by Benjamin Trott 
and maintained by Dave Rolsky.  Both are copyrighted under the same terms 
as this module.  

Many thanks go to these gentlemen whose work made this module possible.

=head1 SEE ALSO

L<Net::FTP|Net::FTP>

L<Net::SFTP|Net::SFTP>

L<Net::SFTP::Constants|Net::SFTP::Constants>

L<Net::SFTP::Attributes|Net::SFTP::Attributes>

=head1 KEYWORDS

ftp, sftp, xftp, Net::FTP, Net::SFTP

=cut
