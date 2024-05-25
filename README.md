# DB-Engines-CPU
A tool to measure the CPU usage when running the same workload on different databases (this is not a benchmark)

The Docker Compose defines how to start the database engines and their CLI.

For example, you can start YugabyteDB and create the Sakila schema:
```
docker compose down
docker compose up yugabytedb -d --wait
docker compose run -T yugabytedb-cli < ./sakila/yugabytedb-sakila-db/yugabytedb-sakila-schema.sql
```
docker compose run -T yugabytedb-cli ./sakila/yugabytedb-sakila-db/yugabytedb-sakila-schema.sql
To insert Sakila data and get the number of CPU instructions with perf, we identify the CGROUP and use `perf`:
```
 container=$(docker-compose ps -q yugabytedb )
 ls -ld /sys/fs/cgroup/perf_event/docker/$container
  perf stat -e instructions -G docker/$container -a \
   docker compose run -T yugabytedb-cli < ./sakila/yugabytedb-sakila-db/yugabytedb-sakila-insert-data.sql

```

You can run:
```
sh run-all.sh
```
and check the elapsed time and CPU instructions
awk '
/^ +[0-9,]+ +instructions +docker[/][0-9a-f]+/{ ins=$1 }
/^ +[0-9.]+ +seconds time elapsed/ { printf "%40s %20s seconds, %20s instructions\n",FILENAME,$1,ins }
' $(ls -t)
```
