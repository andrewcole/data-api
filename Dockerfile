FROM docker.io/library/python:3.9.18-bullseye AS builder

# Install sqlite-utils PIP package
RUN pip install sqlite-utils==3.35.2 peewee

FROM builder AS galog-builder

# Add galog files
ADD galog/ .

# Create database
RUN sqlite-utils insert galog.db flights galog.json --pk=id --flatten

# Normalize type and reg columns
RUN sqlite-utils extract galog.db flights type reg \
  --rename reg registration \
  --table aircraft

# Normalize type column
RUN sqlite-utils extract galog.db aircraft type \
  --table type

# Normalize crew column
RUN sqlite-utils extract galog.db flights crew \
  --rename crew name \
  --table crew \
  --fk-column crew_id

# Normalize pic column
RUN sqlite-utils extract galog.db flights pic \
  --rename pic name \
  --table crew \
  --fk-column pic_id

# Convert columns
RUN sqlite-utils convert galog.db flights \
  date 'r.parsedate(value)'
RUN sqlite-utils transform galog.db flights \
  --type singleengine_dual float \
  --type singleengine_command float \
  --type instrument_simulator float
 
# Create log view
RUN sqlite-utils create-view galog.db log \
  'select \
    flights.`date` as `Date`, \
    type.`type` as `Type`, \
    aircraft.`registration` as `Reg`, \
    pic.`name` as PIC, \
    crew.`name` as Crew, \
    flights.`route` as `Route`, \
    flights.`details` as `Details`, \
    flights.`singleengine_dual` as `Dual`, \
    flights.`singleengine_command` as `Command`, \
    flights.`instrument_simulator` as `Simulator`, \
    flights.`links_blog` as `Blog`, \
    flights.`links_photos` as `Photos` \
  from \
    flights \
    inner join crew as pic on flights.`pic_id` = pic.`id` \
    inner join crew as crew on flights.`crew_id` = crew.`id` \
    inner join aircraft on flights.`aircraft_id` = aircraft.`id` \
    inner join type on aircraft.`type_id` = type.`id` \
  order by flights.`date`'

FROM builder AS rptlog-builder

# Add rptlog files
ADD rptlog/ .

# Create database
RUN python3 rptlog.py
 
# Create log view
RUN sqlite-utils create-view rptlog.db log \
  'select \
    trip.`title` as trip, \
    flight.`flight` as flight, \
    origin.`iata` as origin, \
    destination.`iata` as destination, \
    flight.`start` as start, \
    flight.`end` as end, \
    aircraft.`id` as aircraft_id, \
    aircraft.`registration` as registration, \
    type.`name` as type \
  from \
    trip \
    inner join flight on flight.`trip_id` = trip.`id` \
    inner join airport as origin on flight.`origin_id` = origin.`id` \
    inner join airport as destination on flight.`destination_id` = destination.`id` \
    inner join aircraft on flight.`aircraft_id` = aircraft.id \
    inner join type on aircraft.`type_id` = type.id \
  order by \
    flight.`start`'

FROM builder AS openflights-builder

# Add airports.dat file
ADD https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat .
ADD https://raw.githubusercontent.com/jpatokal/openflights/master/data/planes.dat .

# Create database
RUN sqlite-utils insert openflights.db airports airports.dat --csv --no-headers --detect-types
RUN sqlite-utils insert openflights.db planes planes.dat --csv --no-headers --detect-types

# Rename columns
RUN sqlite-utils transform openflights.db airports \
  --rename untitled_1 airport_id \
  --rename untitled_2 name \
  --rename untitled_3 city \
  --rename untitled_4 country \
  --rename untitled_5 iata \
  --rename untitled_6 icao \
  --rename untitled_7 latitude \
  --rename untitled_8 longitude \
  --rename untitled_9 altitude \
  --rename untitled_10 timezone \
  --rename untitled_11 dst \
  --rename untitled_12 tz \
  --rename untitled_13 type \
  --rename untitled_14 source
RUN sqlite-utils transform openflights.db planes \
  --rename untitled_1 name \
  --rename untitled_2 iata \
  --rename untitled_3 icao

FROM builder AS postcodes-builder

# Add australian_postcodes.json
ADD https://raw.githubusercontent.com/matthewproctor/australianpostcodes/master/australian_postcodes.json .

# Create database
RUN sqlite-utils insert postcodes.db postcodes australian_postcodes.json --detect-types

# Final image
FROM docker.io/datasetteproject/datasette:0.64.5

COPY --from=galog-builder galog.db /mnt/galog.db
COPY --from=rptlog-builder rptlog.db /mnt/rptlog.db
COPY --from=openflights-builder openflights.db /mnt/openflights.db
COPY --from=postcodes-builder postcodes.db /mnt/postcodes.db

CMD "datasette" "-p" "8001" "-h" "0.0.0.0" "/mnt/galog.db" "/mnt/rptlog.db" "/mnt/openflights.db" "/mnt/postcodes.db"
