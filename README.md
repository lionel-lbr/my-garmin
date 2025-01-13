# Scrap Garmin Connect and take ownership of your data

Will download the following bio-metric of a given the day and store then in a json file: sleep, weight, heartrate, stress and pulse-ox

## From shell

Run `./garmin-daily.sh` to get data of day (of current date)

Run `./garmin-daily.sh <date>` to get data from a specific date such as `./garmin-daily.sh 2025-01-12`

Or you can also run with a series or dates such as `./garmin-daily.sh 2025-01-12 2025-01-11 2025-01-10`

## With Docker:

Build:
`docker build -t my-garmin-image .`

Run:
`docker run --rm -v <your app folder>>:/my-garmin -e APP_DIR=/my-garmin my-garmin-image`

## Credentials

The script will load you credentials from the `config.cfg` file. It should define `username` and `password` variables as:

```
USERNAME="your username"
PASSWORD="your password"
```
