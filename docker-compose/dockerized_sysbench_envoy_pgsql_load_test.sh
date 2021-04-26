#!/bin/bash

RESULTS_DIR=/results
DURATION_ONE_SB_TEST=30

DB_USER=postgres
DB_PASSWORD=

ENVOY_PGSQL_HOST=127.0.0.1
ENVOY_PGSQL_PORT=1999

# Capture stdout/err
current_epoch=$( date +%s )
exec >"$RESULTS_DIR/script_pgsql_trace_${current_epoch}_$$.log" 2>&1

echo "Testing version:"
/usr/local/bin/envoy --version

# Launch Envoy in the background
/usr/local/bin/envoy -c /etc/envoy.yaml -l debug \
     --log-path "$RESULTS_DIR/envoy_pgsql_log_${current_epoch}.log"  &
envoy_pid=$!

# Wait till it listens at the TCP port $ENVOY_PGSQL_PORT in /proc/net/tcp.
port_hexad=$( printf "%04X" $ENVOY_PGSQL_PORT )
while true; do
    awk -v phex=$port_hexad  '
              BEGIN {
                      listen_port= "00000000:" phex;
                      exit_val=1      # default exit-value: not listening yet
              }
              ( $2 == listen_port ) && ( $3 == "00000000:0000" ) {
                       exit_val=0;
                       exit(exit_val)
              }
              END { exit(exit_val) }
           '   /proc/net/tcp
    [[ $? -eq 0 ]] && break
    echo "Waiting 5 more seconds for Envoy"
    sleep 5
done

# Where the SysBench Lua tests scripts are located:
SBTEST_SCRIPTDIR=/usr/share/sysbench/

# This is the SysBench script to use for this test on Envoy/PgSQL:
# OLTP_SCRIPT_PATH=${OLTP_SCRIPT_PATH}/oltp_read_only.lua
OLTP_SCRIPT_PATH=${SBTEST_SCRIPTDIR}/oltp_read_write.lua

# Prepare the cmd-line arguments to call SysBench
# (Change the --pgsql-port= to 3306 to do a speed comparison of Envoy with
# the raw PostgreSQL server.)
SBTEST_PGSQL_ARGS="--pgsql-db=my_envoy_test
 --pgsql-host=$ENVOY_PGSQL_HOST --pgsql-port=$ENVOY_PGSQL_PORT
 --pgsql-user=$DB_USER --pgsql-password=$DB_PASSWORD
 --tables=8 --table_size=100000 --simple_ranges=1000
 --range_selects=on --distinct_ranges=0 --auto_inc=on"

DB_DRIVER_ARGS="--db-driver=pgsql $SBTEST_PGSQL_ARGS"

# Wait to make sure that the Envoy proxy has a connection to a PgSQL upstream,
# its port $ENVOY_PGSQL_PORT is up but the PGSQL server upstream doesn't need
# to be up yet.
sleep 2                 # TODO: Fix this script test_sql_connection.lua
cat >/tmp/test_sql_connection.lua <<EOF
function thread_init()
  drv = sysbench.sql.driver()
  con = drv:connect()
end
function event()
  local n = con:query_row("SELECT count(*) FROM INFORMATION_SCHEMA.COLUMNS")
  if n < 0 then
    error("No connection to PostgreSQL yet")
  else
    print(n)
  end
end
EOF
ARGS="/tmp/test_sql_connection.lua  ${DB_DRIVER_ARGS} --threads=1 --events=1"
while true; do
    # sysbench $SB_ARGS run
    sysbench $SB_ARGS
    [[ $? -eq 0 ]] && break
    echo "Waiting 5 more seconds for PostgreSQL"
    sleep 5
done

echo "PostgreSQL is also ready. Starting Sysbench tests"

# Run the SysBench during 30 seconds, and show the load database debug
SB_EXTRA_ARGS="--threads=2 --time=$DURATION_ONE_SB_TEST --events=0
               --percentile=0 --db-debug=on"

ARGS="${OLTP_SCRIPT_PATH} ${DB_DRIVER_ARGS} ${SB_EXTRA_ARGS}"

# Start perf capture on the Envoy proxy:

/bin/bash /root/perf_on_envoy.sh &

# Run the SysBench test on the Envoy proxy to PostgreSQL:

sysbench $ARGS prepare

# sysbench $ARGS prewarm

sysbench $ARGS run

sysbench $ARGS cleanup

/usr/bin/curl -s http://localhost:8001/stats > \
        "$RESULTS_DIR/envoy_pgsql_stats_${current_epoch}_$$.log"

# clean-up: the perf capture should also close after some delay:
/bin/kill -SIGINT ${envoy_pid}
# Give time to perf to close its "perf.data" file, to avoid
# that it has "file's data size field is 0 which is unexpected"
while ! /usr/bin/pgrep -x perf; do
    sleep 1
done
/bin/sync
sleep 6

# Obtain the symbol names in the generated perf.data from the current
# /usr/local/bin/envoy, otherwise the symbol names could be lost for a
# flame-graph (having only unresolved symbol addresses).
perf_data=$(
     /usr/bin/find "$RESULTS_DIR" -name envoy_pgsql_perf_\*.data -mmin -2
 )

/usr/bin/perf script -i "$perf_data" | \
       /usr/bin/xz -9 > "${perf_data/.data/.script.txt.xz}"

