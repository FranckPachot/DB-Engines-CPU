docker compose down
for engine in yugabytedb
do
 docker compose up $engine -d --wait
 container=$(docker-compose ps -q "$engine")
 ls -ld /sys/fs/cgroup/perf_event/docker/$container
 for script in  \
  ./sakila/yugabytedb-sakila-db/yugabytedb-sakila-schema.sql \
  ./sakila/yugabytedb-sakila-db/yugabytedb-sakila-insert-data.sql \
  ./sql/sakila-update \
  /dev/null
 do
  perf stat -e instructions -G docker/$container -a \
   docker compose run -T $engine-cli < "$script" 2>&1 |
   tee out/$(basename $script).log
 done
done
(
cd out
awk '
/^ +[0-9,]+ +instructions +docker[/][0-9a-f]+/{ ins=$1 }
/^ +[0-9.]+ +seconds time elapsed/ { printf "%40s %20s seconds, %20s instructions\n",FILENAME,$1,ins }
' $(ls -t)
)

