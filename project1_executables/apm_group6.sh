#!/bin/bash
# APM Project 1 Group 6

# ---------- config ----------
# User defined ip address for ifstat network measuring tool
IP=$1

# User defined number of seconds the test should run for (default: 900s)
TIME=${2:-900} 

# Network interface to measure
NET=ens33

# Hard dis to measure
DISK=sda

# Number of seconds between each measurment
STEP=5

# If no ip address if given, exit the program, and print a message defining the correct program usage format
if [ -z "$IP" ]; then
  echo "Usage: $0 <IP_address>"
  exit 1
fi

# List of apps to measure
APPS=(./APM1 ./APM2 ./APM3 ./APM4 ./APM5 ./APM6)

# Starting time, in seconds
START=$(date +%s)

# Temporary files for ifstat and iostat output
TMP_IF=ifstat.tmp
TMP_IO=iostat.tmp

# Filename to save collective data to
SAVE_FILE=system_metrics.csv

# List of app process IDs
PIDS=()

# ---------- cleanup ----------
# Stops all related processes (app processes and temporary file writing processes),
# Deletes temporary files
cleanup() {
  echo "Stopping everything..."
  kill $IF_PID $IO_PID 2>/dev/null
  for p in "${PIDS[@]}"; do
    kill "$p" 2>/dev/null
  done
  rm -f $TMP_IF $TMP_IO
}
trap cleanup EXIT

# ---------- start apps ----------
# Starts all of the applications that will be monitored.
# Defines the start_apps() function.
start_apps() {
# Loops through each app in the APPS array
  for app in "${APPS[@]}"; do
    if [ -x "$app" ]; then
      $app "$IP" &
      pid=$!
      PIDS+=($pid)
      name=$(basename "$app")
      echo "Started $name (PID $pid)"
      > "${name}_metrics.csv"
    else
      echo "Can't run $app"
    fi
  done
}

# ---------- background monitors ----------
watch_ifstat() {
  if ifstat -n 1 1 >/dev/null 2>&1; then
    ifstat -n 1 $NET | awk -v iface="$NET" '
      $1 == iface { print $2 "," $3; fflush(); }
    ' > $TMP_IF &
  else
    sar -n DEV 1 | awk -v iface="$NET" '
      $2 == iface { print $5 "," $6; fflush(); }
    ' > $TMP_IF &
  fi
  IF_PID=$!
}

watch_iostat() {
  iostat -x -k -d 1 | awk -v d="$DISK" '
    BEGIN { skip=1 }
    /^Device:/ { next }
    $1 == d {
      if (skip) { skip=0; next }
      if ($9 == "") next
      print $9; fflush();
    }
  ' > $TMP_IO &
  IO_PID=$!
}




# ---------- collect process metrics ----------
proc_metrics() {
  now=$(date +%s)
  sec=$((now - START))
  for i in "${!PIDS[@]}"; do
    pid=${PIDS[$i]}
    name=$(basename "${APPS[$i]}")
    if ps -p $pid > /dev/null 2>&1; then
      vals=$(ps -p $pid -o %cpu=,%mem=)
      echo "$sec,$vals" >> "${name}_metrics.csv"
    else
      echo "$sec,0,0" >> "${name}_metrics.csv"
    fi
  done
}

# ---------- collect system metrics ----------
sys_metrics() {
  now=$(date +%s)
  sec=$((now - START))
  if [ -s "$TMP_IF" ]; then
    line=$(tail -n1 $TMP_IF)
  else
    line="0,0"
  fi
  if [ -s "$TMP_IO" ]; then
    io=$(tail -n1 $TMP_IO)
  else
    io="0"
  fi
  free=$(df -m / | awk 'NR==2{print $4}')
  echo "$sec,$line,$io,$free" >> $SAVE_FILE
}

# ---------- main ----------
> $SAVE_FILE
start_apps
watch_ifstat
watch_iostat

echo "Collecting data for $TIME seconds..."
END=$((START + TIME))

# Fixed timestamps. Variable t recieving timestamp from STEP and
# Collecting data on each planned second (5 10 15 20).
for ((t = STEP; t <= TIME; t += STEP)); do
  target=$((START + t))
  
  while [ $(date +%s) -lt $target ]; do
    sleep 0.2
  done
  
  sec=$((t))
  proc_metrics
  sys_metrics
done

echo "Done!"
