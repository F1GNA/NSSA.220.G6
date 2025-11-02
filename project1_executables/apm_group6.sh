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
# Loops through each application path in the APPS array
  for app in "${APPS[@]}"; do
  # Checks here if the file is executable.
    if [ -x "$app" ]; then
    # If the file is executable, it runs the app, passes it as the $IP variable, and uses & to run it in the background.
      $app "$IP" &
      # The $! here gets the PID of the most recent background command
      pid=$!
      # Adds the new PUD to our PIDS array
      PIDS+=($pid)
      # Gets the filename from the path. For example, APM1 comes from ./APM1
      name=$(basename "$app")
      echo "Started $name (PID $pid)"
      # This is to create an empty file with the specified name
      > "${name}_metrics.csv"
      # Otherwise, the program should declare that it can't run that specific app and move on to the next app to check if it's runnable. 
    else
      echo "Can't run $app"
    fi
  done
}

# ---------- background monitors ----------
# These functions start the long-running system monitors:

# This creates the watch_ifstat() network monitoring function
watch_ifstat() {
# Code tries to run ifstat and if the command succeeds, then it means that ifstat is installed, and the then block runs.
  if ifstat -n 1 1 >/dev/null 2>&1; then
  # This line runs ifstat every 1 second on the $NET interface. The output from this is piped to awk.
  # The awk command finds the line for the correct interface and prints the 2nd and 3rd columns, separated by a comma. fflush() ensures that the data is written to the file immediately. 
  # The output from awk is redirected to the temporary file $TMP_IF, and the whole command runs in the background.
  # Runs an else block if the ifstat command fails.
    ifstat -n 1 $NET | awk -v iface="$NET" '
      $1 == iface { print $2 "," $3; fflush(); }
    ' > $TMP_IF &
  else
  # This is a fallback of sorts. It uses sar, which is a different monitoring tool, to get the same data. The awk logic is just for sar's different output format.
    sar -n DEV 1 | awk -v iface="$NET" '
      $2 == iface { print $5 "," $6; fflush(); }
    ' > $TMP_IF &
  fi
  # Stores the PID of the ifstat or sar background processes so it can be killed by the cleanup() function.
  IF_PID=$!
}

# This defines the watch_iostat() function that is for disk monitoring
watch_iostat() {
# Runs iostat in extended mode (-x), for devices (-d), every 1 second (1). The output is piped to awk. 
# awk stuff:
  # Before starting, sets a skip flag to 1
  # Skips any header lines
  # Once it finds a line for the correct disk, we use an if block
  # If the skip flag is 1, we set it to 0, skip the first line. This is to ignore iostat's first output and not the current data
  # The print line prints the 9th column (disk writes in kB/s) and flushes the output.
  iostat -x -k -d 1 | awk -v d="$DISK" '
    BEGIN { skip=1 }
    /^Device:/ { next }
    $1 == d {
      if (skip) { skip=0; next }
      if ($9 == "") next
      print $9; fflush();
    }
  ' > $TMP_IO &
  # Line above redirects the output to the disk temp file and runs in the background
  # Line below stores the PID of the process for the cleanup() function. 
  IO_PID=$!
}




# ---------- collect process metrics ----------
# These functions are called inside the main loop to grab the data:

# This defines the function to get per-process metrics
proc_metrics() {
# This gets the exact current time
  now=$(date +%s)
  # This calculates the elapsed time in seconds
  sec=$((now - START))
  # This for loop here loops through the indices (0, 1, 2, etc.) of the PIDS array
  for i in "${!PIDS[@]}"; do
  # This gets the PID at the current index
    pid=${PIDS[$i]}
    # This gets the app name from the APPS array at the same index
    name=$(basename "${APPS[$i]}")
    # This checks if the process with that PID is still running
    if ps -p $pid > /dev/null 2>&1; then
    # If it is still running, this runs ps formatted to show only %CPU and %Memory with no headers
      vals=$(ps -p $pid -o %cpu=,%mem=)
      # This appends the elapsed time and the CPU/Memory values to that app's specific CSV file
      echo "$sec,$vals" >> "${name}_metrics.csv"
      # Else block here for if the process is dead
    else
    # If the process is dead, this appends a 0,0 entry to show the process stopped
      echo "$sec,0,0" >> "${name}_metrics.csv"
    fi
  done
}

# ---------- collect system metrics ----------
# This defines the function to get system-wide metrics
sys_metrics() {
# These two lines calculate the elapsed time
  now=$(date +%s)
  sec=$((now - START))
  # This checks if the network temp file is not empty (-s)
  if [ -s "$TMP_IF" ]; then
  # If it has data, it gets the last line (which is the most recent value)
    line=$(tail -n1 $TMP_IF)
    # If the file is empty, then it uses 0,0 as the default.
  else
    line="0,0"
  fi
  # This does the same check for the disk temp file
  if [ -s "$TMP_IO" ]; then
    io=$(tail -n1 $TMP_IO)
  else
    io="0"
  fi
  # This runs df -m / (or disk free space in MB) and uses awk to grab the 4th column from the 2nd line (NR==2), which is the available space.
  free=$(df -m / | awk 'NR==2{print $4}')
  # This appends all the collected data (time, network, disk, free space) as a new line in the main system_metrics.csv file.
  echo "$sec,$line,$io,$free" >> $SAVE_FILE
}

# ---------- main ----------
# This is the main.
# This controls the timing

# This empties the main system_metrics.csv file before starting
> $SAVE_FILE
# These three lines below this comment call the functions to start everything:
start_apps
watch_ifstat
watch_iostat

# This prints a status message
echo "Collecting data for $TIME seconds..."
END=$((START + TIME))

# Fixed timestamps. Variable t receiving timestamp from STEP and
# Collecting data on each planned second (5 10 15 20).
for ((t = STEP; t <= TIME; t += STEP)); do
  target=$((START + t))

  # This loop constantly checks the current time:
  while [ $(date +%s) -lt $target ]; do
  # Sleeps for a very short time (of 200ms) to avoid maxing out the CPU, then it checks the time again
    sleep 0.2
    # The while loop only exits when the current time ($(date +%s)) is finally equal to or greater than the target time. This ensures the collection happens at the 5-second mark, not 5 seconds after the last collection finished
  done
  
  sec=$((t))
  # This calls the collection functions to log the data
  proc_metrics
  sys_metrics
done

echo "Done!"
