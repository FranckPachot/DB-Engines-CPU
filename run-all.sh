docker compose down
docker compose up -d 
sleep 30
for engine in postgres yugabytedb cockroachdb
do
 docker compose up $engine -d --wait
 container=$(docker-compose ps -q "$engine")
 ls -ld /sys/fs/cgroup/perf_event/docker/$container
 for script in  \
  ./sakila/$engine-sakila-db/$engine-sakila-schema.sql \
  ./sakila/$engine-sakila-db/$engine-sakila-insert-data.sql \
  ./sakila/$engine-sakila-db/$engine-sakila-delete-data.sql \
  ./sakila/$engine-sakila-db/$engine-sakila-drop-objects.sql \
  ./sql/sakila-update.sql \
  /dev/null
 do
  perf stat -e instructions -G docker/$container -a \
   docker compose run -T $engine-cli < "$script" 2>&1 |
   tee out/$engine-$(basename $script).log
 done
done

(
cd out
awk '
/^ +[0-9,]+ +instructions +docker[/][0-9a-f]+/{ ins=$1 }
/^ +[0-9.]+ +seconds time elapsed/ { printf "%-55s %8.3f seconds, %20s instructions \n",FILENAME,$1,ins }
' * | sort -nk4
)

