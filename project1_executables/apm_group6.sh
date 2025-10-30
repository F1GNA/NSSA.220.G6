#!/bin/bash
# APM Project 1 Group 6

# ---------- config ----------
IP=$1
TIME=${2:-900} 
NET=ens33
DISK=sda
STEP=5

if [ -z "$IP" ]; then
  echo "Usage: $0 <IP_address>"
  exit 1
fi

APPS=(./APM1 ./APM2 ./APM3 ./APM4 ./APM5 ./APM6)
START=$(date +%s)

TMP_IF=ifstat.tmp
TMP_IO=iostat.tmp
SAVE_FILE=system_metrics.csv

PIDS=()

# ---------- cleanup ----------
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
start_apps() {
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
  ifstat $NET 1 | awk '/^[0-9]/ {print $1","$2; fflush();}' > $TMP_IF &
  IF_PID=$!
}

watch_iostat() {
  iostat -dk 1 $DISK | awk -v d=$DISK '
    /^Device:/ {next}
    $1==d {print $4; fflush();}' > $TMP_IO &
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

while [ $(date +%s) -lt $END ]; do
  proc_metrics
  sys_metrics
  sleep $STEP
done

echo "Done!"
