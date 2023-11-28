from datetime import datetime
from json import load, dump
from peewee import Field, ForeignKeyField, Model, TextField

from playhouse.sqlite_ext import SqliteExtDatabase

from pathlib import Path

from click import (
    Choice as CHOICE,
    File as FILE,
    Path as PATH,
    argument,
    command,
    option,
)


class TimestampTzField(Field):
    """
    A timestamp field that supports a timezone by serializing the value
    with isoformat.
    """

    field_type = "TEXT"  # This is how the field appears in Sqlite

    def db_value(self, value: datetime) -> str:
        if value:
            if isinstance(value, str):
                value = self.python_value(value)
            return value.isoformat()

    def python_value(self, value: str) -> str:
        if value:
            return datetime.fromisoformat(value)


class BaseModel(Model):
    pass


class Trip(BaseModel):
    title = TextField()


class Airport(BaseModel):
    iata = TextField(unique=True)


class Type(BaseModel):
    name = TextField(unique=True)


class Aircraft(BaseModel):
    registration = TextField(null=True)
    type = ForeignKeyField(Type, backref="type", null=True)


class Flight(BaseModel):
    trip = ForeignKeyField(Trip, backref="flights")
    flight = TextField()
    origin = ForeignKeyField(Airport, backref="origin")
    start = TimestampTzField()
    destination = ForeignKeyField(Airport, backref="destination")
    end = TimestampTzField()
    aircraft = ForeignKeyField(Aircraft, backref="aircraft", null=True)
    notes = TextField(null=True)


@command()
@argument(
    "file",
    type=FILE(),
    default="./rptlog.json",
)
@option(
    "--database-path",
    type=PATH(file_okay=True, dir_okay=False, allow_dash=False, resolve_path=True),
    default="./rptlog.db",
)
def cli(
    file,
    database_path,
):
    database_path = (
        Path(database_path) if not isinstance(database_path, Path) else database_path
    )

    database_path.resolve()
    if database_path.is_file():
        database_path.unlink()

    json_data = load(file)

    db = SqliteExtDatabase(None)
    # Initialise Database
    db.init(
        database_path,
        pragmas={"cache_size": -64 * 1000, "synchronous": 0, "foreign_keys": 1},
    )
    db.connect()
    with db.bind_ctx([Trip, Flight, Airport, Aircraft, Type]):
        db.create_tables([Trip, Flight, Airport, Aircraft, Type])

        with db.atomic():
            for json_trip in json_data["trips"]:
                print(f"Adding trip '{json_trip['title']}'")

                for key in json_trip.keys():
                    if key not in [
                        "title",
                        "flights",
                    ]:
                        raise ValueError(f"Unexpected key in trip: {key}")

                sql_trip, created = Trip.get_or_create(
                    title=json_trip["title"],
                    defaults={},
                )
                for json_flight in json_trip["flights"]:
                    for key in json_flight.keys():
                        if key not in [
                            "flight",
                            "route",
                            "time",
                            "purpose",
                            "aircraft",
                            "seat",
                            "supplierconfirmationnumber",
                            "bookingsiteconfirmationnumber",
                            "agencyconfirmationnumber",
                            "ticketnumber",
                            "cost",
                            "notes",
                            "class",
                        ]:
                            raise ValueError(f"Unexpected key in flight: {key}")

                    sql_origin, created = Airport.get_or_create(
                        iata=json_flight["route"]["origin"],
                        defaults={},
                    )
                    sql_destination, created = Airport.get_or_create(
                        iata=json_flight["route"]["destination"],
                        defaults={},
                    )

                    if json_flight.get("aircraft"):
                        if json_flight["aircraft"].get("type"):
                            sql_aircraft_type, created = Type.get_or_create(
                                name=json_flight["aircraft"]["type"],
                                defaults={},
                            )
                        else:
                            sql_aircraft_type = None

                        sql_aircraft, created = Aircraft.get_or_create(
                            registration=json_flight["aircraft"].get("registration"),
                            type=sql_aircraft_type,
                            defaults={},
                        )
                    else:
                        sql_aircraft = None

                    sql_flight, created = Flight.get_or_create(
                        trip=sql_trip,
                        flight=json_flight["flight"],
                        origin=sql_origin,
                        start=json_flight["time"]["departure"],
                        destination=sql_destination,
                        end=json_flight["time"]["arrival"],
                        aircraft=sql_aircraft,
                        notes=json_flight.get("notes"),
                        defaults={},
                    )


if __name__ == "__main__":
    cli()
