package Net::xFTP;

require 5.001;

use warnings;
use strict;
use vars qw(@ISA $VERSION);
use Carp;
#use Cwd;
use File::Copy;

#use Net::FTP;
#use Net::SFTP;
our $haveFTP = 0;
our $haveSFTP = 0;
eval 'use Net::FTP; $haveFTP = 1; 1';
eval 'use Net::SFTP; $haveSFTP = 1; 1';
die "..Must have either Net::FTP and or Net::SFTP!"
		unless ($haveFTP || $haveSFTP);

our $VERSION = '0.01';

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
	foreach my $i (keys %args)
	{
#print "<BR>xFTP: arg($i)=$args{$i}=\n";
		if ($i =~ s/^xftp_//)   #EXTRACT OUT OUR SPECIAL ARGS ("xftp_*")
		{
			$xftp_args{$i} = $args{"xftp_$i"};
#print "<BR>+++xFTP: xftp_args($i)=$xftp_args{$i}=\n";

			delete $args{"xftp_$i"};
		}
	}
#foreach my $xxx (keys %args) { print "<BR>xFTP: NOW arg($xxx)=$args{$xxx}=\n"; };
	if ($xftp->{pkg} =~ /Net::SFTP/ && $haveSFTP)
	{
		foreach my $i (keys %args)
		{
			delete $args{$i}  if ($i =~ /^ftp_/)   #EXTRACT OUT OUR SPECIAL ARGS ("xftp_*")
		}
		my $saveEnvHome = $ENV{HOME};
		$ENV{HOME} = $xftp_args{home}  if ($xftp_args{home});
#print "<BR>ENV(HOME)1=$ENV{HOME}=\n";
		eval { $xftp->{xftp} = Net::SFTP->new($host, %args, warn => \&sftpWarnings); };
		$xftp->{xftp_lastmsg} = $@  if ($@);
		$ENV{HOME} = $saveEnvHome;
#print "<BR>ENV(HOME)2=$ENV{HOME}=\n";
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
#print "-???- realpath=$realpath= xftp=$self->{xftp}=\n";
		my @dirHash;
		eval { @dirHash = $self->{xftp}->ls($realpath) };
		return  if ($@);
		my $t;
		@dirlist = ();
		for (my $i=0;$i<=$#dirHash;$i++)
		{
			$t = $dirHash[$i]->{filename};
#print STDERR "-fn=$t= LONG=".$dirHash[$i]->{longname}."= attb=".$dirHash[$i]->{longname}."=\n";
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
#print "-???- realpath=$realpath= xftp=$self->{xftp}=\n";
		my @dirHash;
		eval { @dirHash = $self->{xftp}->ls($realpath) };
		return  if ($@);
		my $t;
		@dirlist = ();
		for (my $i=0;$i<=$#dirHash;$i++)
		{
			$t = $dirHash[$i]->{longname};
#print STDERR "-fn=$t= LONG=".$dirHash[$i]->{longname}."= attb=".$dirHash[$i]->{longname}."=\n";
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
			shift @d;      #REMOVE "TOTAL" LINE.
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

sub cwd  #SET THE "CURRENT" DIRECTORY.
{
#print STDERR "-xFTP.cwd: PARMS=".join('|',@_)."=\n";
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
#print STDERR "-xFTP.cwd: fullwd=$fullwd= at=$@= cwd=$cwd=\n";
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
	return $ok;
}

sub get
{
	my $self = shift;

	return undef  unless (@_ >= 1);
	my @args = @_;
	if ($self->{pkg} =~ /Net::SFTP/)
	{
		$args[0] = $self->{cwd} . '/' . $args[0]  unless ($args[0] =~ m#^\/#);
	}
	unless (@args >= 2)
	{
		$args[1] = $args[0];
		$args[1] = $1  if ($args[1] =~ m#([^\/\\]+)$#);
	}
	my $ok;
	if (!$self->{pkg})
	{
		$args[0] = $self->{cwd} . '/' . $args[0]  unless ($args[0] =~ m#^\/#);
		$ok = copy($args[0], $args[1]);
		unless ($ok)
		{
			$self->{xftp_lastmsg} = $! || 'Local copy failed for unknown reasons';
		}
	}
	else
	{
		eval { $ok = $self->{xftp}->get(@args) };
		$self->{xftp_lastmsg} = $@  if ($@);
	}
	return $ok ? 1 : undef;
}

sub put    #SFTP returns OK=1 on SUCCESS.
{
	my $self = shift;

	return undef  unless (@_ >= 1);
	my @args = @_;
	unless (@args >= 2)
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
		$ok = copy($args[0], $args[1]);
		unless ($ok)
		{
			$self->{xftp_lastmsg} = $! || 'Local copy failed for unknown reasons';
		}
	}
	else
	{
		eval { $ok = $self->{xftp}->put(@args) };
		$self->{xftp_lastmsg} = $@  if ($@);
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
		return ($_ == 1) ? 1 : undef;
		unlink($path)
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
		eval { $ok = $self->{xftp}->do_remove($oldfile, $newfile) };
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
#print "--mkdir: path=$path= pkg=$self->{pkg}=\n";
	my $tryRecursion = shift||0;
	$path =~ s#[\/\\]$##  unless ($path eq '/');

	my $ok = '';
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		eval { $ok = $self->{xftp}->mkdir($path, $tryRecursion) };
#print "--1mkdir: tr=$tryRecursion= path=$path= ok=$ok= at=".($@ ? $@ : '')."=\n";
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
#print "--mkdir: path=$path=\n";
			eval { $ok = $self->{xftp}->do_mkdir($path, Net::SFTP::Attributes->new()) };
			$self->{xftp_lastmsg} = $@  if ($@);
#print "--mkdir: path=$path= tr=$tryRecursion= ok=$ok= at=".($@ ? $@ : '')."=\n";
			last  unless ($tryRecursion && $ok ne '0');
#print "--mkdir: continuing recursively!\n";
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
#print STDERR "-xFTP.mkdir: ok=$ok= path=$path=\n";
			$self->{xftp_lastmsg} = $! || 'local mkdir failed for unknown reasons'
					unless ($ok);
#print STDERR "-xFTP.mkdir: ok=$ok= \n";
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
	my $tryRecursion = shift||0;
	$path =~ s#[\/\\]$##  unless ($path eq '/');

	my $ok;
	if ($self->{pkg} =~ /Net::FTP/ && $haveFTP)
	{
		eval { $ok = $self->{xftp}->rmdir($path, $tryRecursion) };
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
#print "-!!!- sftpWarnings called!($res[0]|$res[1]) ($@)\n";
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
#print "-xFTP.isadir: curdir=$curdir= path=$path= ok=$ok= \n";
#print "-xFTP.isadir: at=$@=\n"  if ($@);
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

Jim Turner, C<< <turnerjw@wwol.com> >>

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

	die "..This server connection needs Net::SFTP!" 
		unless (Net::xFTP->haveSFTP());

	$ftp = Net::xFTP->new('SFTP', "some.host.name", Debug => 0,
			user => 'userid', password => 'opensesme')
		or die "Cannot connect to some.host.name: $@";

	$ftp->cwd('/pub')
		or die "Cannot change working directory ", $ftp->message();

	my $current_remote_path = $ftp->pwd();

	my @filesAndSubfolders = $ftp->ls('/pub');

	$ftp->mkdir('myownfolder')
		or die "Cannot make subdirectory ", $ftp->message();

	$ftp->get('some.file')
		or die "get failed ", $ftp->message();

	$ftp->put('my.file', 'myownfolder/new.filename')
		or die "put failed ", $ftp->message();

	$ftp->delete('some.file')
		or die "Cannot delete file ", $ftp->message();

	$ftp->quit();

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
functionality are welcome.  I know this is bare-bones (now), but I am 
currently very busy with other (mostly billable) projects. :)

=head1 CONSTRUCTOR

=over 4

=item new ( PROTOCOL, HOST [, OPTIONS ])

This is the constructor for a new Net::FTP object.  The first two 
arguments are required and are positional.  Sebsequent arguments (OPTIONS) 
are in the form "name => value".

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
required.  This is a do-nothing method for SFTP and local.

=item binary

Transfer file in binary mode. No transformation will be done if using 
FTP.  This is a do-nothing method for SFTP and local.

=item chmod ( PERMISSIONS, PATH )

Sets the permissions on C<PATH>, which can be either a file or subdirectory.  
C<PERMISSIONS> is an octal number expressed as a decimal.  Common values are 
777 (full access), 755 (rwxr-xr-x) and 644 (rw-r--r--).

=item cwd ( [ DIR ] )

Attempt to change directory to the directory given in C<$dir>.  If
C<$dir> is C<"..">, the FTP C<CDUP> command is used to attempt to
move up one directory.  If no directory is given then an attempt is made
to change the directory to the root directory.  For SFTP, the new directory 
is saved and subsequent relative paths have this value appended to them.

=item delete ( FILENAME )

Send a request to the server to delete C<FILENAME>.  Calls either the 
FTP->delete method or SFTP->do_remove method.  For local, calls Perl's 
I<unlink> function.

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

Returns undef on failure.

=item get ( REMOTE_FILE [, LOCAL_FILE ] )

Get C<REMOTE_FILE> from the server and store locally.  If C<LOCAL_FILE>
is not specified, then a file with the same name as C<REMOTE_FILE> sans 
the path information will be created on the current working directory of 
the machine the program is running on.  For I<local> protocol, simply 
copys C<REMOTE_FILE> to C<LOCAL_FILE>.

Returns 1 if successful, undef if fails.

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

Returns undef on failure.

=item message ()

Returns the last error message from the most recent method call.  For FTP, 
simply calles I<$FTP->message()>.  For SFTP, we must eval / trap the error 
from @_ and or use some method's call-back function option.

=item mkdir ( DIR [, RECURSE ])

Create a new directory with the name C<DIR>. If C<RECURSE> is I<true> then
C<mkdir> will attempt to create all the directories in the given path.

Calls the C<mkdir> method in FTP or C<do_mkdir> method in SFTP.

Returns 1 if successful, undef if fails.

=item Net::xFTP->haveFTP ()

Returns 1 if Net::FTP is installed, 0 otherwise.

=item Net::xFTP->haveSFTP ()

Returns 1 if Net::SFTP is installed, 0 otherwise.

=item Net::xFTP->haveModules ()

Returns a reference to a hash in the form: 
{ 'Net::FTP' => 1|0, 'Net::SFTP' => 1|0 }

=item new ( PROTOCOL, HOST [, OPTIONS ])

This is the constructor.  It returns either a Net::xFTP object or undef on 
failure.  For details, see the "CONSTRUCTOR" section above.  For FTP, this 
method also calls the "login" method to connect.

=item protocol ()

Returns either C<Net::FTP> or C<Net::SFTP>, depending on which underlying 
module is being used.  Returns an empty string is C<local> is used.

=item put ( LOCAL_FILE [, REMOTE_FILE ] )

Put a file on the remote server. C<LOCAL_FILE> and C<REMOTE_FILE> are 
specified as strings representing the absolute or relative path and file 
name.  If C<REMOTE_FILE> is not specified then the file will be stored in 
the current working directory on the remote machine with the same fname 
(sans directory information) as C<LOCAL_FILE>.  For I<local> protocol, 
simply copies C<LOCAL_FILE> to C<REMOTE_FILE>.

Returns 1 if successful, undef if fails.

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

=item rmdir ( DIR [, RECURSE ])

Remove the directory with the name C<DIR>. If C<RECURSE> is I<true> then
C<rmdir> will attempt to delete everything inside the directory if using
FTP.  Currently I<NOT SUPPORTED> in SFTP or vial the I<local> protocol.

=item size ( FILE )

Returns the size in bytes of C<FILE>, or I<undef> on failure.

=item Other methods

Even though C<Net::xFTP> is designed for commonality, it may occassionally 
be necessary to call a method specific to a given protocol.  To do this,
simply invoke the method as follows:

$ftp->{xftp}->method ( args )

Example:

$ftp->{xftp}->size('/pub/myfile')  if ($ftp->protocol() eq 'Net::FTP');

=item sftpWarnings

Internal module used to capture non-fatal warning messages from Net::SFTP 
methods.

=back

=head1 TODO

Add additional features that are supported by either or both Net::FTP and 
Net::SFTP, ie. allow filehandles in C<GET> and C<PUT>.

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

=cut
