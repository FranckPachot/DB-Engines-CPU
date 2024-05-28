# DB-Engines-CPU
A tool to measure the CPU usage when running the same workload on different databases 

⚠️  this is not a benchmark:
- the configuration of the databases are not tuned equally
- what is run on each may not be optimal (especially the Sakila scripts are different for each DB)
- we account for the background processes during the run so a longer response time counts more of them

## Usage

The Docker Compose defines how to start the database engines and their CLI.

For example, you can start YugabyteDB and create the Sakila schema:
```
docker compose down
docker compose up yugabytedb -d --wait
docker compose run -T yugabytedb-cli < ./sakila/yugabytedb-sakila-db/yugabytedb-sakila-schema.sql
```
To insert Sakila data and get the number of CPU instructions with Linux Perf Stat, we identify the CGROUP and call `perf` while running the script:
```
 container=$(docker-compose ps -q yugabytedb )
 ls -ld /sys/fs/cgroup/perf_event/docker/$container
  perf stat -e instructions -G docker/$container -a \
   docker compose run -T yugabytedb-cli < ./sakila/yugabytedb-sakila-db/yugabytedb-sakila-insert-data.sql
```
It displays the number of CPU instructions counted by `perf stat -e instructions` for the whole engine (group):
![image](https://github.com/FranckPachot/DB-Engines-CPU/assets/33070466/745f89ae-c5e5-45d2-8718-d09928e574f1)


## Run all scripts on all databases

You can run:
```
sh run-all.sh
```
and check the elapsed time and CPU instructions
```
(
cd out
awk '
BEGIN{e["postgres"]="🐘";e["oracle"]="🅾️ ";e["yugabytedb"]="▝▞";e["cockroachdb"]="🪳";}
{ split(FILENAME,f,"/") ; gsub(f[1],"*",f[2]) }
/^ +[0-9,]+ +instructions +docker[/][0-9a-f]+/{ ins=$1 }
/^ +[0-9.]+ +seconds time elapsed/ { printf "%-30s %30s instructions %15s %1s\n",f[2],ins,f[1],e[f[1]] }
' */small* | sort  -k1,1 -k2,2n | awk '$1>l{print ""}{print}{l=$1}'
) | tee out/summary.txt
```
![image](https://github.com/FranckPachot/DB-Engines-CPU/assets/33070466/f3fb5d0f-4e62-42f7-90a5-8f4ce1d29ebb)

