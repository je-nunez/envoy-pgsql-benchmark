# About

A docker-compose version of the benchmark on the Envoy proxy with PostgreSQL
backend using SysBench.

# WIP

This project is a *work in progress*. The implementation is *incomplete* and
subject to change. The documentation can be inaccurate.

# How:

In this directory, run:

      [[ ! -d ./proxy_results ]] && mkdir ./proxy_results
       
      docker-compose pull
       
      docker-compose up --build -d

The results of the tests will be left in the `proxy_results/` directory.
(If another directory is needed, please modify `docker-compose.yaml`.) The
result files left by each docker-compose up of the test containers are
(`<common_suffix>` below is a common suffix generated from the container-id
and initial epoch at the start of the docker-compose up, and is common among
all log files of the same run):

- envoy_pgsql_stats_<common_suffix>.log

The Envoy stats at the end of each Sysbench test, from `http://localhost:8001/stats`

- envoy_pgsql_log_<common_suffix>.log

The Envoy debug logs.

- script_pgsql_trace_<common_suffix>.log

The test script logs itself (contains Perf and SysBench messages).

- envoy_pgsql_perf_<common_suffix>.data

The Perf-Record file during the Sysbench tests.

- envoy_pgsql_perf_<common_suffix>.script.txt.xz

The Perf-Script text file generated (with symbol names) from the Perf-Record
file above.

Note: To generate (externally, after the containers have run) the
[FlameGraph](https://github.com/brendangregg/FlameGraph), use the
`envoy_pgsql_perf_<common_suffix>.script.txt.xz` file with the symbol names:

       xzcat 'proxy_results/envoy_pgsql_perf_<common_suffix>.script.txt.xz' | \
            ${your_flamegraph_install_dir}/stackcollapse-perf.pl | \
            ${your_flamegraph_install_dir}/flamegraph.pl > envoy_flamegraph.svg

