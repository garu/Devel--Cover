# Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB;

use strict;
use warnings;

our $VERSION = "0.19";

use Devel::Cover::DB::File  0.19;
use Devel::Cover::Criterion 0.19;

use Carp;
use Data::Dumper;
use File::Path;

my $DB = "cover.4";  # Version 4 of the database.

sub new
{
    my $class = shift;
    my $self  =
    {
        criteria       => [ qw( statement branch path condition pod time ) ],
        criteria_short => [ qw( stmt      branch path cond      pod time ) ],
        collected      => [],
        indent         => 1,
        cover          => {},
        @_
    };

    $self->{all_criteria}       = [ @{$self->{criteria}},       "total" ];
    $self->{all_criteria_short} = [ @{$self->{criteria_short}}, "total" ];
    $self->{collected}          = [ @{$self->{criteria}} ]
        unless @{$self->{collected}};

    bless $self, $class;

    my $file;
    if (defined $self->{db})
    {
        $self->validate_db;
        $file = "$self->{db}/$DB";
        open F, "<$file" or croak "Unable to open $file: $!";
        $self->{filehandle} = *F{IO};
    }

    $self->read if defined $self->{filehandle};

    if (defined $file)
    {
        close F or croak "Unable to close $file: $!";
    }

    croak "No input db, filehandle or cover" unless defined $self->{cover};

    $self
}

sub     criteria       { @{$_[0]->{    criteria      }} }
sub     criteria_short { @{$_[0]->{    criteria_short}} }
sub all_criteria       { @{$_[0]->{all_criteria      }} }
sub all_criteria_short { @{$_[0]->{all_criteria_short}} }

sub read
{
    my $self = shift;
    local $/;
    my $db;
    my $fh = $self->{filehandle};
    eval <$fh>;
    croak $@ if $@;
    $self->{cover}     = $db->{cover};
    $self->{collected} = $db->{collected};
    $self->{indent}    = $db->{indent};
    $self
}

sub write
{
    my $self = shift;
    $self->{db} = shift if @_;
    croak "No db specified" unless length $self->{db};
    $self->validate_db;
    my $db =
    {
        cover     => $self->{cover},
        collected => $self->{collected},
        indent    => $self->{indent},
    };
    local $Data::Dumper::Indent   = $self->indent;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Useperl  = 1;  # TODO - remove this when possible
    my $file = "$self->{db}/$DB";
    open OUT, ">$file" or croak "Cannot open $file\n";
    print OUT Data::Dumper->Dump([$db], ["db"]);
    close OUT or croak "Cannot close $file\n";
    $self
}

sub delete
{
    my $self = shift;
    $self->{db} = shift if @_;
    croak "No db specified" unless length $self->{db};
    rmtree($self->{db});
    $self
}

sub cover_hash
{
    my $self = shift;
    $self->{cover}
}

sub validate_db
{
    my $self = shift;
    unless (-d $self->{db})
    {
        mkdir $self->{db}, 0777 or croak "Cannot mkdir $self->{db}: $!\n";
    }
    $self
}

sub collected
{
    my $self = shift;
    $self->{collected} = shift if @_;
    @{$self->{collected}}
}

sub indent
{
    my $self = shift;
    $self->{indent} = shift if @_;
    $self->{indent}
}

sub merge
{
    my ($self, $from) = @_;

    # When the database gets big, it's quicker to merge into what's
    # already there.

    _merge_hash($from->cover, $self->cover);
    $_[0] = $from;
}

sub _merge_hash
{
    my ($into, $from) = @_;
    for my $fkey (keys %{$from})
    {
        my $fval = $from->{$fkey};
        my $fval_ref = ref $fval;

        if (defined $into->{$fkey} and UNIVERSAL::isa($into->{$fkey}, "ARRAY"))
        {
            _merge_array($into->{$fkey}, $fval);
        }
        elsif (defined $fval && UNIVERSAL::isa($fval, "HASH"))
        {
            if (defined $into->{$fkey} and
                UNIVERSAL::isa($into->{$fkey}, "HASH"))
            {
                _merge_hash($into->{$fkey}, $fval);
            }
            else
            {
                $into->{$fkey} = $fval;
            }
        }
        else
        {
            # A scalar (or a blessed scalar).  We know there is no into
            # array, or we would have just merged with it.

            $into->{$fkey} = $fval;
        }
    }
}

sub _merge_array
{
    my ($into, $from) = @_;
    for my $i (@$into)
    {
        my $f = shift @$from;
        if (UNIVERSAL::isa($i, "ARRAY") ||
            !defined $i && UNIVERSAL::isa($f, "ARRAY"))
        {
            _merge_array($i, $f || []);
        }
        elsif (UNIVERSAL::isa($i, "HASH") ||
              !defined $i && UNIVERSAL::isa($f, "HASH") )
        {
            _merge_hash($i, $f || {});
        }
        else
        {
            if (defined $f)
            {
                $i ||= 0;
                if ($f =~ /^\d+$/ && $i =~ /^\d+$/)
                {
                    $i += $f;
                }
                elsif ($i ne $f)
                {
                    warn "<$i> does not match <$f> - using later value";
                    $i = $f;
                }
            }
        }
    }
    push @$into, @$from;
}

sub calculate_summary
{
    my $self = shift;
    my %options = @_;

    return if defined $self->{summary} && !$options{force};
    my $s = $self->{summary} = {};

    for my $file ($self->cover->items)
    {
        $self->cover->get($file)->calculate_summary($self, $file, \%options);
    }

    for my $file ($self->cover->items)
    {
        $self->cover->get($file)->calculate_percentage($self, $s->{$file});
    }

    my $t = $self->{summary}{Total};
    for my $criterion ($self->criteria)
    {
        next unless exists $t->{$criterion};
        my $c = "Devel::Cover::\u$criterion";
        $c->calculate_percentage($self, $t->{$criterion});
    }
    Devel::Cover::Criterion->calculate_percentage($self, $t->{total});
}

sub trimmed_file
{
    my ($f, $len) = @_;
    substr $f, 0, 3 - $len, "..." if length $f > $len;
    $f
}

sub print_summary
{
    my $self = shift;
    my %options = map(($_ => 1), @_ ? @_ : @{$self->{collected}});
    $options{total} = 1 if keys %options;

    my $n = keys %options;

    my $oldfh = select STDOUT;

    $self->calculate_summary(%options);

    my $format = sub
    {
        my ($part, $criterion) = @_;
        $options{$criterion} && exists $part->{$criterion}
            ? sprintf "%5.2f", $part->{$criterion}{percentage}
            : "n/a"
    };

    my $fw = 77 - $n * 7;
    $fw = 28 if $fw < 28;

    my $fmt = "%-${fw}s" . " %6s" x $n . "\n";
    printf $fmt, "-" x $fw, ("------") x $n;
    printf $fmt, "File",
                 map { $self->{all_criteria_short}[$_] }
                 grep { $options{$self->{all_criteria}[$_]} }
                 (0 .. $#{$self->{all_criteria}});
    printf $fmt, "-" x $fw, ("------") x $n;

    my $s = $self->{summary};
    for my $file (grep($_ ne "Total", sort keys %$s), "Total")
    {
        printf $fmt,
               trimmed_file($file, $fw),
               map { $format->($s->{$file}, $_) }
               grep { $options{$_} }
               @{$self->{all_criteria}};

    }

    printf $fmt, "-" x $fw, ("------") x $n;
    print "\n\n";

    select $oldfh;
}

sub cover
{
    my $self = shift;

    return $self->{cover} if $self->{cover_valid};

    unless (UNIVERSAL::isa($self->{cover}, "Devel::Cover::DB::Cover"))
    {
        bless $self->{cover}, "Devel::Cover::DB::Cover";
        for my $file (values %{$self->{cover}})
        {
            bless $file, "Devel::Cover::DB::File";
            while (my ($crit, $criterion) = each %$file)
            {
                my $class = "Devel::Cover::" . ucfirst lc $crit;
                bless $criterion, "Devel::Cover::DB::Criterion";
                for my $line (values %$criterion)
                {
                    for my $o (@$line)
                    {
                        die "<$crit:$o>" unless ref $o;
                        bless $o, $class;
                        bless $o, $class . "_" . $o->type if $o->can("type");
                        # print "blessed $crit, $o\n";
                    }
                }
            }
        }
    }

    unless (exists &Devel::Cover::DB::Base::items)
    {
        *Devel::Cover::DB::Base::items = sub
        {
            my $self = shift;
            keys %$self
        };

        *Devel::Cover::DB::Base::values = sub
        {
            my $self = shift;
            values %$self
        };

        *Devel::Cover::DB::Base::get = sub
        {
            my $self = shift;
            my ($get) = @_;
            $self->{$get}
        };

        my $classes =
        {
            Cover     => [ qw( files file ) ],
            File      => [ qw( criteria criterion ) ],
            Criterion => [ qw( locations location ) ],
            Location  => [ qw( data datum ) ],
        };
        my $base = "Devel::Cover::DB::Base";
        while (my ($class, $functions) = each %$classes)
        {
            my $c = "Devel::Cover::DB::$class";
            no strict "refs";
            @{"${c}::ISA"} = $base;
            *{"${c}::$functions->[0]"} = \&{"${base}::values"};
            *{"${c}::$functions->[1]"} = \&{"${base}::get"};
        }

        *Devel::Cover::DB::File::DESTROY = sub {};
        unless (exists &Devel::Cover::DB::File::AUTOLOAD)
        {
            *Devel::Cover::DB::File::AUTOLOAD = sub
            {
                # Work around a change in bleadperl from 12251 to 14899.
                my $func = $Devel::Cover::DB::AUTOLOAD || $::AUTOLOAD;

                # print STDERR "autoloading <$func>\n";
                (my $f = $func) =~ s/^.*:://;
                carp "Undefined subroutine $f called"
                    unless grep { $_ eq $f }
                                @{$self->{all_criteria}},
                                @{$self->{all_criteria_short}};
                no strict "refs";
                *$func = sub { shift->{$f} };
                goto &$func
            };
        }
    }

    $self->{cover_valid} = 1;

    $self->{cover}
}

=for old

sub print_details_hash
{
    my $self = shift;
    my (@files) = @_;
    @files = sort keys %{$self->{cover}} unless @files;
    for my $file (@files)
    {
        print "$file\n\n";
        my $lines = $self->{cover}{$file}{statement};
        my $fmt = "%-5d: %6s %s\n";

        open F, $file or carp("Unable to open $file: $!"), next;

        while (<F>)
        {
            if (exists $lines->{$.})
            {
                my @c = @{$lines->{$.}};
                printf "%5d: %6d %s", $., shift(@c)->[0], $_;
                printf "     : %6d\n", shift(@c)->[0] while @c;
            }
            else
            {
                printf "%5d:        %s", $., $_;
            }
        }

        close F or croak "Unable to close $file: $!";
        print "\n\n";
    }
}

sub print_details
{
    my $self = shift;
    my (@files) = @_;
    my $cover = $self->cover;
    @files = sort $cover->items unless @files;
    for my $file (@files)
    {
        print "$file\n\n";
        my $f = $cover->file($file);
        my $statement = $f->statement;
        my $fmt = "%-5d: %6s %s\n";

        open F, $file or carp("Unable to open $file: $!"), next;

        while (<F>)
        {
            if (defined (my $location = $statement->location($.)))
            {
                my @c = @{$location};
                printf "%5d: %6d %s", $., shift(@c)->[0], $_;
                printf "     : %6d\n", shift(@c)->[0] while @c;
            }
            else
            {
                printf "%5d:        %s", $., $_;
            }
        }

        close F or croak "Unable to close $file: $!";
        print "\n\n";
    }
}

=cut

1

__END__

=head1 NAME

Devel::Cover::DB - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::DB;

 my $db = Devel::Cover::DB->new(db => "my_coverage_db");
 $db->print_summary(statement => 1, pod => 1);
 $db->print_details;

=head1 DESCRIPTION

This module provides access to a database of code coverage information.

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head2 new

 my $db = Devel::Cover::DB->new(db => "my_coverage_db");

Contructs the DB from the specified database.

=head2 cover

 my $cover = $db->cover;

Returns a Devel::Cover::DB::Cover object.  From here all the coverage
data may be accessed.

 my $cover = $db->cover;
 for my $file ($cover->items)
 {
     print "$file\n";
     my $f = $cover->file($file);
     for my $criterion ($f->items)
     {
         print "  $criterion\n";
         my $c = $f->criterion($criterion);
         for my $location ($c->items)
         {
             my $l = $c->location($location);
             print "    $location @$l\n";
         }
     }
 }

Data for different criteria will be in different formats, so that will
need special handling, but I'll deal with that when we have the data for
different criteria.

If you don't want to remember all the method names, use values() instead
of files(), criteria() and locations() and get() instead of file(),
criterion() and location().

Instead of calling $file->criterion("x") you can also call $file->x.

=head1 BUGS

Huh?

=head1 VERSION

Version 0.19 - 29th September 2002

=head1 LICENCE

Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut