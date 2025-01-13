#!/usr/bin/env bash
echo "Running bash version: $BASH_VERSION"

# Example usage:
#   ./garmin_daily.sh "2025-01-08"


echo "Running Garmin Daily Data script"
echo "APP_DIR is $APP_DIR"

OUTPUT_FOLDER="data"


# Check if APP_DIR is defined and exists
if [ -n "$APP_DIR" ] && [ -d "$APP_DIR" ] && [ -f "$APP_DIR/config.cfg" ]; then
  CONFIG_FILE="$APP_DIR/config.cfg"
else
  CONFIG_FILE="./config.cfg"
fi

# Load configuration file
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
  echo "Loaded configuration file $CONFIG_FILE"
else
  echo "Configuration file $CONFIG_FILE not found!"
  exit 1
fi

# Validate input
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "username or password not defined in $CONFIG_FILE"
  exit 1
fi

# Use the provided date or default to today's date
TODAY=$(date +%Y-%m-%d)

# Check if arguments are provided
if [ $# -eq 0 ]; then
  # No arguments, use today's date and make an array
  DATES=("$TODAY")
else
  # Use all provided arguments as dates
  DATES=("$@")
fi

if [ -n "$APP_DIR" ] && [ -d "$APP_DIR" ] && [ ! -d "$APP_DIR/$OUTPUT_FOLDER" ]; then
  echo "Folder '$OUTPUT_FOLDER' does not exist. Creating it now."
  cd "$APP_DIR"
  mkdir "$OUTPUT_FOLDER"
  cd ..
else
  APP_DIR="."
  echo "Folder '$OUTPUT_FOLDER' already exists."
fi

HEADER_USER_AGENT="User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:133.0) Gecko/20100101 Firefox/133.0"
HEADER_ACCEPT_ENCODING="Accept-Encoding: gzip, deflate"
HEADER_ACCEPT="Accept: application/json, text/plain, */*"
HEADER_ACCEPT_LANGUAGE="Accept-Language: en-US,en;q=0.5"
HEADER_CONNECTION="Connection: keep-alive"

# 1. Perform the login request and capture the JSON response
LOGIN_RESPONSE="$(curl -s \
  --cookie-jar cookies.txt \
  'https://sso.garmin.com/portal/api/login?clientId=GarminConnect&locale=en-US&service=https%3A%2F%2Fconnect.garmin.com%2Fmodern' \
  --compressed \
  -X POST \
  -H "${HEADER_USER_AGENT}" \
  -H "${HEADER_ACCEPT_ENCODING}" \
  -H "${HEADER_ACCEPT}" \
  -H "${HEADER_ACCEPT_LANGUAGE}" \
  -H "${HEADER_CONNECTION}" \
  -H 'Content-Type: application/json' \
  -H 'Referer: https://sso.garmin.com/portal/sso/en-US/sign-in?clientId=GarminConnect&service=https%3A%2F%2Fconnect.garmin.com%2Fmodern' \
  -H 'Origin: https://sso.garmin.com' \
  --data-raw "{\"username\": \"${USERNAME}\", \"password\": \"${PASSWORD}\", \"rememberMe\": false, \"captchaToken\": \"\"}" \
  )"
 
# 2. Extract fields using jq
SERVICE_URL="$(echo "$LOGIN_RESPONSE" | jq -r '.serviceURL')"
SERVICE_TICKET_ID="$(echo "$LOGIN_RESPONSE" | jq -r '.serviceTicketId')"
LOGIN_STATUS="$(echo "$LOGIN_RESPONSE" | jq -r '.responseStatus.httpStatus')"

# Print the extracted values
echo "Service URL:       $SERVICE_URL"
echo "Service Ticket ID: $SERVICE_TICKET_ID"
echo "Login Status:       $LOGIN_STATUS"

# 3. Perform a second call using the SERVICE_TICKET_ID
SERVICE_TICKET_RESPONSE="$(curl -s -L\
  --cookie cookies.txt \
  --cookie-jar cookies.txt \
  "https://connect.garmin.com/modern?ticket=${SERVICE_TICKET_ID}" \
  -H "${HEADER_USER_AGENT}" \
  -H "${HEADER_ACCEPT_ENCODING}" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
  -H "${HEADER_ACCEPT_LANGUAGE}" \
  -H "${HEADER_CONNECTION}" \
  -H 'Referer: https://sso.garmin.com/' \
  -H 'Upgrade-Insecure-Requests: 1' \
  -w "%{http_code}" \
  )"

# Optional: Print the second call response
echo "Service ticket http status:${SERVICE_TICKET_RESPONSE: -3}"
echo

TOKEN_RESPONSE="$(curl -s -L \
  --cookie cookies.txt \
  --cookie-jar cookies.txt \
  'https://connect.garmin.com/services/auth/token/here' \
  -X POST \
  -H "${HEADER_USER_AGENT}" \
  -H "${HEADER_ACCEPT_ENCODING}" \
  -H "${HEADER_ACCEPT}" \
  -H "${HEADER_ACCEPT_LANGUAGE}" \
  -H "${HEADER_CONNECTION}" \
  -H "Referer: $SERVICE_URL" \
  -H 'Content-Type: application/json;charset=utf-8' \
  -H 'Origin: https://connect.garmin.com' \
  --data-raw '{"tokenType":"HereToken"}' \
  )"

ACCESS_TOKEN="$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')"
echo "Access Token: $ACCESS_TOKEN"
echo

REFRESH_TOKEN_RESPONSE="$(curl -s -L \
  --cookie cookies.txt \
  --cookie-jar cookies.txt \
  "$SERVICE_URL/di-oauth/exchange" \
  --compressed \
  -X POST \
  -H "${HEADER_USER_AGENT}" \
  -H "${HEADER_ACCEPT_ENCODING}" \
  -H "${HEADER_ACCEPT}" \
  -H "${HEADER_ACCEPT_LANGUAGE}" \
  -H "${HEADER_CONNECTION}" \
  -H "Referer: $SERVICE_URL" \
  -H 'Origin: https://connect.garmin.com' \
  -H 'Content-Length: 0' \
  )"

EXCHANGE_ACCESS_TOKEN="$(echo "$REFRESH_TOKEN_RESPONSE" | jq -r '.access_token')"
EXCHANGE_REFRESH_TOKEN="$(echo "$REFRESH_TOKEN_RESPONSE" | jq -r '.refresh_token')"

echo "Access Token:  $EXCHANGE_ACCESS_TOKEN"
echo
echo "Refresh Token: $EXCHANGE_REFRESH_TOKEN"
echo

for DATE in "${DATES[@]}"; do
  echo
  echo "Processing date: $DATE"
  
  OUTPUT_FILE="$APP_DIR/$OUTPUT_FOLDER/daily_$DATE.json"
  echo "{ \"date\": \"$DATE\"" > "$OUTPUT_FILE"

  get_service_data() {
    local URL="$1"
    local DATE="$2"
    local SERVICE="$3"
    
    local HTTP_RESPONSE="$(curl -s -L \
    --cookie cookies.txt \
    --cookie-jar cookies.txt \
    "$URL" \
    --compressed \
    -H "${HEADER_USER_AGENT}" \
    -H "${HEADER_ACCEPT_ENCODING}" \
    -H "${HEADER_ACCEPT}" \
    -H "${HEADER_ACCEPT_LANGUAGE}" \
    -H "${HEADER_CONNECTION}" \
    -H "Authorization: Bearer $EXCHANGE_ACCESS_TOKEN" \
    -H "Referer: $SERVICE_URL/$SERVICE/$DATE/0" \
    -H "DI-Backend: connectapi.garmin.com" \
    -w "%{http_code}" \
    -o temp_output.txt \
    )"

    local HTTP_STATUS=${HTTP_RESPONSE: -3}
    local OUTPUT="$(cat temp_output.txt)"
    local RESPONSE=("$HTTP_STATUS" "$OUTPUT")
    echo "${RESPONSE[@]}" # return the whole array
  }

  # Fetch sleep data
  echo "Fetching sleep data for date: $DATE"
  SLEEP_RESPONSE=($(get_service_data "https://connect.garmin.com/sleep-service/sleep/dailySleepData?date=$DATE&nonSleepBufferMinutes=60" "$DATE" "sleep"))
  echo "HTTP Status: ${SLEEP_RESPONSE[0]}"
  echo ",\"sleep\":${SLEEP_RESPONSE[1]}" >> "$OUTPUT_FILE"
  echo "Completed sleep request for date: $DATE"

  # Fetch weight data
  echo "Fetching weight data for date: $DATE"
  WEIGHT_RESPONSE=($(get_service_data "https://connect.garmin.com/weight-service/weight/dayview/$DATE" "$DATE" "weight"))
  echo "HTTP Status: ${WEIGHT_RESPONSE[0]}"
  echo "${WEIGHT_RESPONSE[1]}" | jq -r '.totalAverage.weight'
  echo ",\"weight\":${WEIGHT_RESPONSE[1]}" >> "$OUTPUT_FILE"
  echo "Completed weight request for date: $DATE"

  # Fetch HR data
  echo "Fetching heart rate data for date: $DATE"
  HR_RESPONSE=($(get_service_data "https://connect.garmin.com/wellness-service/wellness/dailyHeartRate?date=$DATE" "$DATE" "heart-rate"))
  echo "HTTP Status: ${HR_RESPONSE[0]}"
  echo ",\"heartrate\":${HR_RESPONSE[1]}" >> "$OUTPUT_FILE"
  echo "Completed heart rate request for date: $DATE"

  # Fetch stress data
  echo "Fetching stress data for date: $DATE"
  STRESS_RESPONSE=($(get_service_data "https://connect.garmin.com/wellness-service/wellness/dailyStress/$DATE" "$DATE" "stress"))
  echo "HTTP Status: ${STRESS_RESPONSE[0]}"
  echo ",\"stress\":${STRESS_RESPONSE[1]}" >> "$OUTPUT_FILE"
  echo "Completed heart rate request for date: $DATE"

  # Fetch pulse ox data
  echo "Fetching pulse ox data for date: $DATE"
  PULSEOX_RESPONSE=($(get_service_data "https://connect.garmin.com/wellness-service/wellness/daily/spo2acclimation/$DATE" "$DATE" "pulse-ox"))
  echo "HTTP Status: ${PULSEOX_RESPONSE[0]}"
  echo ",\"pulse-ox\":${PULSEOX_RESPONSE[1]}" >> "$OUTPUT_FILE"
  echo "Completed pulse ox request for date: $DATE"

  # Close the JSON array
  echo "}" >> "$OUTPUT_FILE"
  echo "Daily data saved to: ${OUTPUT_FILE}"
done
