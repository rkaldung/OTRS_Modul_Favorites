#
# --
# $Id: Favorites.pm,v 1.32 2010/09/08 16:39:22 ub Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Favorites;

use strict;
use warnings;

use Kernel::System::Valid;
use Kernel::System::Time;
use Kernel::System::SysConfig;
use Kernel::System::CacheInternal;

use vars qw(@ISA $VERSION);
$VERSION = qw($Revision: 1.32 $) [1];

=head1 NAME

Kernel::System::Favorites - Favorites lib

=head1 SYNOPSIS

All ticket Favorites functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::Config;
    use Kernel::System::Encode;
    use Kernel::System::Log;
    use Kernel::System::Main;
    use Kernel::System::DB;
    use Kernel::System::Favorites;

    my $ConfigObject = Kernel::Config->new();
    my $EncodeObject = Kernel::System::Encode->new(
        ConfigObject => $ConfigObject,
    );
    my $LogObject = Kernel::System::Log->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
    );
    my $MainObject = Kernel::System::Main->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
    );
    my $DBObject = Kernel::System::DB->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
        MainObject   => $MainObject,
    );
    my $FavoritesObject = Kernel::System::Favorites->new(
        ConfigObject => $ConfigObject,
        LogObject    => $LogObject,
        DBObject     => $DBObject,
        MainObject   => $MainObject,
        EncodeObject => $EncodeObject,
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for (qw(DBObject ConfigObject LogObject MainObject EncodeObject)) {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }
    $Self->{ValidObject}         = Kernel::System::Valid->new(%Param);
    $Self->{CacheInternalObject} = Kernel::System::CacheInternal->new(
        %Param,
        Type => 'Favorites',
        TTL  => 60 * 60 * 3,
    );

    return $Self;
}

=item FavoritesList()

return a Favorites list as hash

    my %List = $FavoritesObject->FavoritesList(
        Valid => 0,
    );

=cut

sub FavoritesList {
    my ( $Self, %Param ) = @_;

    # check valid param
    if ( !defined $Param{Valid} ) {
        $Param{Valid} = 1;
    }

    # sql
    my $SQL = 'SELECT  id,name,valid_id,create_time,create_by,change_time,change_by,link   FROM Favorites ';
   

    return if !$Self->{DBObject}->Prepare( SQL => $SQL );
    my %Data;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        $Data{ $Row[0] } = $Row[1];
    }
    return %Data;
}

=item FavoritesGet()

get a Favorites

    my %List = $FavoritesObject->FavoritesGet(
        FavoritesID => 123,
        UserID     => 1,
    );

=cut

sub FavoritesGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(FavoritesID UserID)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Favorites => 'error', Message => "Need $_!" );
            return;
        }
    }

    # sql
    return if !$Self->{DBObject}->Prepare(
        SQL => 'SELECT id,name,valid_id,create_time,create_by,change_time,change_by,link '
            . 'FROM Favorites WHERE id = ?',
        Bind => [ \$Param{FavoritesID} ],
    );
    my %Data;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        $Data{ID}         = $Row[0];
        $Data{Name}       = $Row[1];
        $Data{ValidID}    = $Row[2];
        $Data{CreateTime} = $Row[3];
        $Data{CreateBy}   = $Row[4];
        $Data{ChangeTime} = $Row[5];
        $Data{ChangeBy}   = $Row[6];
	$Data{Link}   	  = $Row[7];

    }
    return %Data;
}

=item FavoritesAdd()

add a ticket Favorites

    my $True = $FavoritesObject->FavoritesAdd(
        Name    => 'Prio',
        ValidID => 1,
        UserID  => 1,
    );

=cut

sub FavoritesAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Name ValidID UserID Link)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Favorites => 'error', Message => "Need $_!" );
            return;
        }
    }

    return if !$Self->{DBObject}->Do(
        SQL => 'INSERT INTO Favorites (name, valid_id, create_time, create_by, '
            . 'change_time, change_by,link) VALUES '
            . '(?, ?, current_timestamp, ?, current_timestamp, ?,?)',
        Bind => [
            \$Param{Name}, \$Param{ValidID}, \$Param{UserID}, \$Param{UserID},\$Param{Link},
        ],
    );

    # get new state id
    return if !$Self->{DBObject}->Prepare(
        SQL  => 'SELECT id FROM Favorites WHERE name = ?',
        Bind => [ \$Param{Name} ],
    );
    my $ID;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        $ID = $Row[0];
    }
    return if !$ID;

    # delete cache
    $Self->{CacheInternalObject}->Delete( Key => 'FavoritesLookup::Name::' . $Param{Name} );
    $Self->{CacheInternalObject}->Delete( Key => 'FavoritesLookup::ID::' . $ID );

    return $ID;
}

=item FavoritesUpdate()

update a existing ticket Favorites

    my $True = $FavoritesObject->FavoritesUpdate(
        FavoritesID     => 123,
        Name           => 'New Prio',
        ValidID        => 1,
        CheckSysConfig => 0,   # (optional) default 1
        UserID         => 1,
    );

=cut

sub FavoritesUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(FavoritesID Name ValidID UserID Link)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Favorites => 'error', Message => "Need $_!" );
            return;
        }
    }

    # check CheckSysConfig param
    if ( !defined $Param{CheckSysConfig} ) {
        $Param{CheckSysConfig} = 1;
    }

    return if !$Self->{DBObject}->Do(
        SQL => 'UPDATE Favorites SET name = ?, valid_id = ?, '
            . 'change_time = current_timestamp, change_by = ?, link = ? WHERE id = ?',
        Bind => [
            \$Param{Name}, \$Param{ValidID}, \$Param{UserID},\$Param{Link}, \$Param{FavoritesID},
        ],
    );

    # delete cache
    $Self->{CacheInternalObject}->Delete( Key => 'FavoritesLookup::Name::' . $Param{Name} );
    $Self->{CacheInternalObject}->Delete( Key => 'FavoritesLookup::ID::' . $Param{FavoritesID} );

    # create a time object locally, needed for the local SysConfigObject
    my $TimeObject = Kernel::System::Time->new( %{$Self} );

    # check all sysconfig options
    if ( $Param{CheckSysConfig} ) {

        # create a sysconfig object locally for performance reasons
        my $SysConfigObject = Kernel::System::SysConfig->new(
            %{$Self},
            TimeObject => $TimeObject,
        );

        # check all sysconfig options and correct them automatically if neccessary
        $SysConfigObject->ConfigItemCheckAll();
    }

    return 1;
}

=item FavoritesLookup()

returns the id or the name of a Favorites

    my $FavoritesID = $FavoritesObject->FavoritesLookup(
        Favorites => '3 normal',
    );

    my $Favorites = $FavoritesObject->FavoritesLookup(
        FavoritesID => 1,
    );

=cut

sub FavoritesLookup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Favorites} && !$Param{FavoritesID} ) {
        $Self->{LogObject}->Log( Favorites => 'error', Message => 'Need Favorites or FavoritesID!' );
        return;
    }

    # check cache
    my $CacheKey;
    my $Key;
    my $Value;
    if ( $Param{Favorites} ) {
        $Key      = 'Favorites';
        $Value    = $Param{Favorites};
        $CacheKey = 'FavoritesLookup::Name::' . $Param{Favorites};
    }
    else {
        $Key      = 'FavoritesID';
        $Value    = $Param{FavoritesID};
        $CacheKey = 'FavoritesLookup::ID::' . $Param{FavoritesID};
    }

    my $Cache = $Self->{CacheInternalObject}->Get( Key => $CacheKey );
    return $Cache if $Cache;

    # db query
    my $SQL;
    my @Bind;
    if ( $Param{Favorites} ) {
        $SQL = 'SELECT id FROM Favorites WHERE name = ?';
        push @Bind, \$Param{Favorites};
    }
    else {
        $SQL = 'SELECT name FROM Favorites WHERE id = ?';
        push @Bind, \$Param{FavoritesID};
    }
    return if !$Self->{DBObject}->Prepare( SQL => $SQL, Bind => \@Bind );
    my $Data;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        $Data = $Row[0];
    }

    # set cache
    $Self->{CacheInternalObject}->Set( Key => $CacheKey, Value => $Data );

    # check if data exists
    if ( !defined $Data ) {
        $Self->{LogObject}->Log(
            Favorites => 'error',
            Message  => "No $Key for $Value found!",
        );
        return;
    }

    return $Data;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

=head1 VERSION

$Revision: 1.32 $ $Date: 2010/09/08 16:39:22 $

=cut

