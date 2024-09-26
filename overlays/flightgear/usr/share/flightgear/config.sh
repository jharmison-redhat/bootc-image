#!/usr/bin/sh

# define aircraft model
AIRCRAFT_MODEL=F-35B

# flight dynamics model
FLIGHT_MODEL=org.flightgear.fgaddon.stable_2020.F-35B-yasim

# initial settings
ALTITUDE=15000
THROTTLE_SETTING=1
SPEED=400

# autopilot settings
AP_HEADING=180
AP_SPEED=250
AP_ALTITUDE=5000

# Langley AFB lat/lon
LAT_DEGREES=37.0835
LON_DEGREES=-76.3592

# simulated time of day
TIMEOFDAY=afternoon

# Additional model specific parameters to pass to FlightGear
EXTRA_ARGS=()
