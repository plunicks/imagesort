#!/usr/bin/perl

use strict;

use Tk;
use Tk::Pane;
use Tk::JPEG;
use Tk::PNG;
use File::Copy qw(move);
use Getopt::Long qw(:config gnu_getopt);
use String::ShellQuote;
use List::MoreUtils qw(any);


## Configuration
my %options = (
    format => 'tab',
    );

GetOptions(\%options,
           'dry-run|n!',
           'format|f=s',
    );

my @formats = qw(tab sh csv none);
unless (any { $_ eq $options{format} } @formats) {
    die "Valid formats are: @formats\n";
}


## State
my @files = grep {
    -r $_ || warn "Cannot read $_: $!\n";
    -r
} @ARGV;

my $ii = -1; # index of current image
my $main = MainWindow->new;
my $scrolled = $main->Scrolled('Pane',
                               -scrollbars => '',
                               -width => $main->width,
                               -height => $main->height,
    )->pack(-expand => 1, -fill => 'both');
my $imagit = $scrolled->Label->pack(-expand => 1, -fill => 'both');
my $old_width;
my $old_height;
my $redraw_after;
my %groups;


## Functions
sub min {
    $_[0] <= $_[1] ? $_[0] : $_[1]
}

sub max {
    $_[0] >= $_[1] ? $_[0] : $_[1]
}

# Display the list of files, indicating the current file.
# This format is based on that of Data::Printer.
sub show_list {
    print STDERR "[\n";
    for my $i (0..$#files) {
        # width of index part depends on number of files:
        my $width = (length scalar @files) + 2;
        printf STDERR (
            qq{%3s %-${width}s %s\n},
            $i == $ii ? '->' : '',
            "[$i]",
            $files[$i],
            );
    }
    print STDERR "]\n";
}

sub show_image {
    my (%opts) = @_;

    &show_list unless $opts{quiet};

    unless (@files) {
        $ii = -1;
        $imagit->configure(-image => undef);
        warn "no images\n" unless $opts{quiet};
        return;
    }
    $ii %= @files;

    warn "show image $ii: $files[$ii]\n"
        unless $opts{quiet};

    my $img1 = $main->Photo(
        'fullscale',
        -file => $files[$ii],
        );

    my $xfactor = $img1->width / $scrolled->width;
    my $yfactor = $img1->height / $scrolled->height;
    my $factor = max(1, max($xfactor, $yfactor));

    my $scaled_width = int($img1->width / $factor);
    my $scaled_height = int($img1->height / $factor);

    $scrolled->configure(
        -width => $main->width,
        -height => $main->height,
        );

    # scale image
    my $img2 = $main->Photo('resized',
                            -width => $scaled_width,
                            -height => $scaled_height);

    $img2->copy(
        $img1,
        -shrink,
        -subsample => $factor,
        );

    $imagit->configure(
        -image => 'resized',
        -width => $img2->width,
        -height => $img2->height,
        );

    # save the width and height of the main window so
    # we can re-display the image when it's resized
    $old_width = $main->width;
    $old_height = $main->height;

    &set_title;
}

sub redraw_image {
    &show_image(quiet => 1);
    $redraw_after = undef;
}

sub prev_image {
    return unless @files;
    $ii = ($ii - 1) % @files;
    show_image;
}

sub next_image {
    return unless @files;
    $ii = ($ii + 1) % @files;
    show_image;
}

sub set_title {
    $main->configure(-title => @files ? $files[$ii] : '(no files)');
}

sub get_dir {
    $_[0];
}

sub sort_image {
    my ($key) = @_;
    return unless @files;

    my $file = $files[$ii];

    warn "sort $file to $key\n";
    if (!$options{'dry-run'}) {
        my $dir = get_dir($key);

        -d $dir || mkdir $dir || exit 1;

        move($file, $dir) || return;
    }

    push @{$groups{$key}}, $file;
    splice @files, $ii, 1;

    $ii = -1 if !@files;
    show_image;
}

sub quit {
    for my $key (sort keys %groups) {
        for my $file (@{$groups{$key} || []}) {
            if ($options{format} eq 'tab') {
                print "$file\t$key\n";
            } elsif ($options{format} eq 'sh') {
                printf "mv %s %s\n",
                shell_quote($file), shell_quote(get_dir($key));
            } elsif ($options{format} eq 'csv') {
                printf "%s,%s\n",
                shell_quote(get_dir($key)), shell_quote($file);
            }
        }
    }
    exit 0;
}


## Bindings
$main->bind('<Prior>' => \&prev_image);
$main->bind('<Up>'    => \&prev_image);
$main->bind('<Left>'  => \&prev_image);

$main->bind('<Next>'  => \&next_image);
$main->bind('<Down>'  => \&next_image);
$main->bind('<Right>' => \&next_image);

$main->bind('<Configure>', => sub {
    my $w = shift;
    if (ref $w eq 'MainWindow' && $ii >= 0 &&
        defined $old_width && defined $old_height) {
        $main->afterCancel($redraw_after) if $redraw_after;
        $redraw_after = $main->after(10, \&redraw_image);
    }});

# letter keys sort images into directories
for my $key ('a'..'z') {
    $main->bind("<$key>" => sub { sort_image $key } );
}

$main->bind('<Escape>' => \&quit);


## Main
$main->after(100, \&next_image);

MainLoop;
