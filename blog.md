https://dev.to/yugabyte/comparing-sql-engines-by-cpu-instructions-for-dml-48a


When comparing databases, people often focus on the response time, but it's also essential to consider the global CPU usage. Running a database in a Docker container automatically assigns it to a Linux control group (cgroup), making it easy to obtain execution statistics using `perf stat -G`. This method offers the benefit of measuring not just one process, but all the database activity when running specific SQL queries. It also enables comparisons with databases that use multiple threads to handle requests, such as YugabyteDB.

Following this idea, I tested a similar workload on multiple databases, inserting two million rows, updating them, counting them, and deleting them. I measured the number of CPU instructions used during that execution and compared PostgreSQL, Oracle, YugabyteDB, and CockroachDB.

## This is NOT a benchmark

I am running the database engines using their latest official Docker images and all default configurations, which is not what is typically used in production. In fact, this setup even demonstrates the limitations of benchmarks: databases have different implementations and trade-offs. It's easy to find workloads that are fast in one database and slow in another. I am measuring on a single instance. It is important to note that even when running on a single node cluster, a distributed database architecture that provides elasticity and resilience with built-in distribution utilizes more CPU instructions than traditional monolithic databases. In a cloud-native environment, the cost remains lower by scaling up and down as needed, rather than constantly provisioning capacity for peak demands.

## Summary

Here is a summary of the results. `Gi` is the number of billion instructions in user space, and `s` is the number of seconds, all reported by `perf stat -e instructions:u -a -G docker/$containerid`. The detailed test and output follow.

| Database    |    sleep    |    insert    |    update    |   select    |   delete    |
|-------------|:-----------:|:------------:|:------------:|:-----------:|:-----------:|
| PostgreSQL  | 0.02Gi/11s  |   53Gi/20s   |   74Gi/39s   |   1Gi/1s    |   10Gi/10s   |
| MySQL       | 0.03Gi/11s  |   68Gi/18s   |   67Gi/21s   |   3Gi/2s    |   47Gi/20s  |
| Oracle      |    6Gi/10s  |   30Gi/22s   |   50Gi/30s   |   4Gi/7s    |  101Gi/48s  |
| SQL Server  |  0.1Gi/11s  |   45Gi/13s   |   22Gi/17s   |   1Gi/1s    |   18Gi/5s   |
| TiDB        |  0.4Gi/11s  |  150Gi/21s   |   141Gi/25s  |   5Gi/1s    |  116Gi/14s  |
| YugabyteDB  |    1Gi/11s  |  377Gi/38s   |  919Gi/114s  |  11Gi/2s    |  422Gi/69s  |
| CockroachDB |    7Gi/11s  | 1344Gi/458s  |  747Gi/395s  |  13Gi/3s    |  799Gi/486s |


All runs follow the same process: start the database in a docker container and keep the container ID in a variable. Then, connect with the right client for the database and run SQL, with `perf stat` measuring the CPU instructions.

I've run all this on an 8-vCPU virtual machine (KVM) with 4 Intel(R) Xeon(R) CPU E5-2699 v3 @ 2.30GHz cores with hyperthreading.

## PostgreSQL

Start the database in a Docker container
```sh
postgres=$(
 docker run -d \
  -e POSTGRES_PASSWORD=postgres \
  postgres:latest \
)
```

Start a client, connect, and create a table
```sql
docker run --rm -i --link $postgres:db -e PGPASSWORD=postgres \
  postgres \
  psql -h db -p 5432 -U postgres -ec '
select version();
drop table if exists demo;
create extension if not exists pgcrypto;
create table demo (
 primary key (id)
 , id uuid default gen_random_uuid()
 , value float
);
'
```
```

NOTICE:  table "demo" does not exist, skipping
                                                       version
---------------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.3 (Debian 16.3-1.pgdg120+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 12.2.0-14) 12.2.0, 64-bit
(1 row)

DROP TABLE
CREATE EXTENSION
CREATE TABLE

```

Measure background activity when sleeping 10 seconds
```sql
perf stat -e instructions:u -G docker/$postgres -a \
docker run --rm -i --link $postgres:db -e PGPASSWORD=postgres \
  postgres \
  psql -h db -p 5432 -U postgres -ec '
select pg_sleep(10);
'
```
```

select pg_sleep(10);

 pg_sleep
----------

(1 row)


 Performance counter stats for 'system wide':

        17,728,103      instructions:u              docker/6ee868ec9bcb10ec206224aa84db9489d70db5c71d46f6ec489da4c8f074d0ab

      10.666744875 seconds time elapsed

```

In PostgreSQL, I run VACUUM after each statement because it is necessary to leave the database ready for further queries. Not doing it here would not account for the real resource usage.

Insert two million rows in two transactions of one million rows
```sql
perf stat -e instructions:u -G docker/$postgres -a \
docker run --rm -i --link $postgres:db -e PGPASSWORD=postgres \
  postgres \
  psql -h db -p 5432 -U postgres -ec '
insert into demo(value) select generate_series(1,1000000);
insert into demo(value) select generate_series(1,1000000);
' -c '
vacuum
'
```
```

insert into demo(value) select generate_series(1,1000000);
INSERT 0 1000000

insert into demo(value) select generate_series(1,1000000);
INSERT 0 1000000

vacuum
VACUUM

 Performance counter stats for 'system wide':

    52,812,253,895      instructions:u              docker/6ee868ec9bcb10ec206224aa84db9489d70db5c71d46f6ec489da4c8f074d0ab

      20.423514447 seconds time elapsed

```

Update those two million rows
```sql
perf stat -e instructions:u -G docker/$postgres -a \
docker run --rm -i --link $postgres:db -e PGPASSWORD=postgres \
  postgres \
  psql -h db -p 5432 -U postgres -ec '
update demo set value=value+1;
' -c '
vacuum
'
```
```
update demo set value=value+1;

UPDATE 2000000

vacuum

VACUUM

 Performance counter stats for 'system wide':

    74,393,453,562      instructions:u              docker/6ee868ec9bcb10ec206224aa84db9489d70db5c71d46f6ec489da4c8f074d0ab

      38.580002880 seconds time elapsed

```

Count those two million values
```sql
perf stat -e instructions:u -G docker/$postgres -a \
docker run --rm -i --link $postgres:db -e PGPASSWORD=postgres \
  postgres \
  psql -h db -p 5432 -U postgres -ec '
select count(value) from demo;
'
```
```
select count(value) from demo;

  count
---------
 2000000
(1 row)


 Performance counter stats for 'system wide':

     1,391,096,618      instructions:u              docker/6ee868ec9bcb10ec206224aa84db9489d70db5c71d46f6ec489da4c8f074d0ab

       0.732223707 seconds time elapsed

```

Delete those two million rows
```sql
perf stat -e instructions:u -G docker/$postgres -a \
docker run --rm -i --link $postgres:db -e PGPASSWORD=postgres \
  postgres \
  psql -h db -p 5432 -U postgres -ec '
delete from demo;
' -c '
vacuum
'
```
```
delete from demo;

DELETE 2000000

vacuum

VACUUM

 Performance counter stats for 'system wide':

    10,148,828,821      instructions:u              docker/6ee868ec9bcb10ec206224aa84db9489d70db5c71d46f6ec489da4c8f074d0ab

       9.696420600 seconds time elapsed

```

## YugabyteDB

Start the database in a Docker container
```sh
yugabytedb=$(
 docker run -d \
  yugabytedb/yugabyte:latest \
  yugabyted start --background=false
)
```

Start a client, connect, and create a table
```sql
docker run --rm -i --link $yugabytedb:db postgres \
  psql -h db -p 5433 -U yugabyte -ec '
select version();
drop table if exists demo;
create extension if not exists pgcrypto;
create table demo (
 primary key (id)
 , id uuid default gen_random_uuid()
 , value float
);
'
```
```
NOTICE:  table "demo" does not exist, skipping
                                                                                         version                                                                                    
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 PostgreSQL 11.2-YB-2.21.0.1-b0 on x86_64-pc-linux-gnu, compiled by clang version 16.0.6 (https://github.com/yugabyte/llvm-project.git 1e6329f40e5c531c09ade7015278078682293ebd), 64-bit
(1 row)

DROP TABLE
CREATE EXTENSION
CREATE TABLE

```

Measure background activity when sleeping 10 seconds
```sql
perf stat -e instructions:u -G docker/$yugabytedb -a \
docker run --rm -i --link $yugabytedb:db \
  postgres:latest \
  psql -h db -p 5433 -U yugabyte -e << 'SQL'
select pg_sleep(10);
SQL
```
```
select pg_sleep(10);
 pg_sleep
----------

(1 row)


 Performance counter stats for 'system wide':

       668,261,558      instructions:u              docker/9c32896e86dc88e026e5f80fa3f143f70fa0a7815ee81acca13c750c2a4a8d4c

      10.859333028 seconds time elapsed

```

Insert two million rows in two transactions of one million rows
```sql
perf stat -e instructions:u -G docker/$yugabytedb -a \
docker run --rm -i --link $yugabytedb:db \
  postgres:latest \
  psql -h db -p 5433 -U yugabyte -e << 'SQL'
insert into demo(value) select generate_series(1,1000000);
insert into demo(value) select generate_series(1,1000000);
SQL
```
```
insert into demo(value) select generate_series(1,1000000);
INSERT 0 1000000
insert into demo(value) select generate_series(1,1000000);
INSERT 0 1000000

 Performance counter stats for 'system wide':

   377,180,116,073      instructions:u              docker/9c32896e86dc88e026e5f80fa3f143f70fa0a7815ee81acca13c750c2a4a8d4c

      38.254201842 seconds time elapsed

```

Update those two million rows
```sql
perf stat -e instructions:u -G docker/$yugabytedb -a \
docker run --rm -i --link $yugabytedb:db \
  postgres:latest \
  psql -h db -p 5433 -U yugabyte -e << 'SQL'
update demo set value=value+1;
SQL
```
```
update demo set value=value+1;
UPDATE 2000000

 Performance counter stats for 'system wide':

   918,965,397,040      instructions:u              docker/9c32896e86dc88e026e5f80fa3f143f70fa0a7815ee81acca13c750c2a4a8d4c

     113.679966282 seconds time elapsed

```

Count those two million values
```sql
perf stat -e instructions:u -G docker/$yugabytedb -a \
docker run --rm -i --link $yugabytedb:db \
  postgres:latest \
  psql -h db -p 5433 -U yugabyte -e << 'SQL'
select count(value) from demo;
SQL
```
```
select count(value) from demo;
  count
---------
 2000000
(1 row)


 Performance counter stats for 'system wide':

    11,168,496,896      instructions:u              docker/9c32896e86dc88e026e5f80fa3f143f70fa0a7815ee81acca13c750c2a4a8d4c

       2.475239412 seconds time elapsed
```

Delete those two million rows
```sql
perf stat -e instructions:u -G docker/$yugabytedb -a \
docker run --rm -i --link $yugabytedb:db \
  postgres:latest \
  psql -h db -p 5433 -U yugabyte -e << 'SQL'
delete from demo;
SQL
```
```
delete from demo;
DELETE 2000000

 Performance counter stats for 'system wide':

   421,678,154,604      instructions:u              docker/9c32896e86dc88e026e5f80fa3f143f70fa0a7815ee81acca13c750c2a4a8d4c

      68.652693864 seconds time elapsed

```

## Oracle

Start the database in a Docker container
```sh
oracle=$(
 docker run -d \
  -e ORACLE_PASSWORD=franck -e APP_USER=franck -e APP_USER_PASSWORD=franck \
  gvenzl/oracle-free:slim
)
```

I created a user because using the system ones is different (for example, system tablespaces have additional checksums by default).

Start a client, connect, and create a table
```sql
docker run --rm -i --link $oracle:db \
  container-registry.oracle.com/database/sqlcl:latest \
  -s franck/franck@//db/FREEPDB1 <<'SQL'
select banner_full from v$version;
drop table if exists demo;
create table demo (
 primary key (id)
 , id raw(16) default sys_guid()
 , value float
);
SQL
```
```
BANNER_FULL
_______________________________________________________________________________________________________
Oracle Database 23ai Free Release 23.0.0.0.0 - Develop, Learn, and Run for Free
Version 23.4.0.24.05

Table DEMO dropped.

Table DEMO created.

```

Measure background activity when sleeping 10 seconds with `sqlcl`
```sql
perf stat -e instructions:u -G docker/$oracle -a \
docker run --rm -i --link $oracle:db \
  container-registry.oracle.com/database/sqlcl:latest \
  -s franck/franck@//db/FREEPDB1 @ /dev/stdin <<'SQL'
exec dbms_session.sleep(10);
SQL
```
```

PL/SQL procedure successfully completed.


 Performance counter stats for 'system wide':

       833,762,410      instructions:u              docker/8db3df9fbc74f04e20a28e016cc0b91e04a99dc88ae3ef1923172eb6ac724aa0

      16.695102734 seconds time elapsed
```


It takes an additional 7 seconds to connect because `sqlcl` is a Java application that is very slow to start and connect. I cannot use it for this test. Then, instead if running a container with the database client, I'll connect from `sqlplus` within the database container. I didn't find an official image to run only sqlplus without starting a database.

Measure background activity when sleeping 10 seconds with `sqlplus`
```sql
perf stat -e instructions:u -G docker/$oracle -a \
docker exec -i $oracle \
  sqlplus -s franck/franck@//localhost/FREEPDB1 @ /dev/stdin <<'SQL'
exec dbms_session.sleep(10);
SQL
```
```

PL/SQL procedure successfully completed.


 Performance counter stats for 'system wide':

     6,350,743,728      instructions:u              docker/8db3df9fbc74f04e20a28e016cc0b91e04a99dc88ae3ef1923172eb6ac724aa0

      10.188907434 seconds time elapsed

```

Oracle is not auto-commit by default, so I add a COMMIT statement after each DML statement.

Insert two million rows in two transactions of one million rows
```sql
perf stat -e instructions:u -G docker/$oracle -a \
docker run --rm -i --link $oracle:db \
  container-registry.oracle.com/database/sqlcl:latest \
  -s franck/franck@//db/FREEPDB1 @ /dev/stdin <<'SQL'
insert into demo(value) select rownum from xmltable('1 to 1000000');
commit;
insert into demo(value) select rownum from xmltable('1 to 1000000');
commit;
SQL
```
```

1,000,000 rows inserted.

Commit complete.

1,000,000 rows inserted.

Commit complete.

 Performance counter stats for 'system wide':

    29,948,655,538      instructions:u              docker/8db3df9fbc74f04e20a28e016cc0b91e04a99dc88ae3ef1923172eb6ac724aa0

      22.445749204 seconds time elapsed

```

Update those two million rows
```sql
perf stat -e instructions:u -G docker/$oracle -a \
docker run --rm -i --link $oracle:db \
  container-registry.oracle.com/database/sqlcl:latest \
  -s franck/franck@//db/FREEPDB1 @ /dev/stdin <<'SQL'
update demo set value=value+1;
commit;
SQL
```
```

2,000,000 rows updated.


 Performance counter stats for 'system wide':

    50,447,105,827      instructions:u              docker/8db3df9fbc74f04e20a28e016cc0b91e04a99dc88ae3ef1923172eb6ac724aa0

      30.286655516 seconds time elapsed

```

Count those two million values
```sql
perf stat -e instructions:u -G docker/$oracle -a \
docker run --rm -i --link $oracle:db \
  container-registry.oracle.com/database/sqlcl:latest \
  -s franck/franck@//db/FREEPDB1 @ /dev/stdin <<'SQL'
select count(value) from demo;
SQL
```
```

   COUNT(VALUE)
_______________
        2000000


 Performance counter stats for 'system wide':

     4,446,769,589      instructions:u              docker/8db3df9fbc74f04e20a28e016cc0b91e04a99dc88ae3ef1923172eb6ac724aa0

       6.698948743 seconds time elapsed

```

Delete those two million rows
```sql
perf stat -e instructions:u -G docker/$oracle -a \
docker run --rm -i --link $oracle:db \
  container-registry.oracle.com/database/sqlcl:latest \
  -s franck/franck@//db/FREEPDB1 @ /dev/stdin <<'SQL'
delete from demo;
commit;
SQL
```
```

2,000,000 rows deleted.


 Performance counter stats for 'system wide':

   101,012,043,703      instructions:u              docker/8db3df9fbc74f04e20a28e016cc0b91e04a99dc88ae3ef1923172eb6ac724aa0

      47.742493451 seconds time elapsed

```

## PostgreSQL

Start the database in a Docker container
```sh
sqlserver=$(
 docker run -d \
  -e ACCEPT_EULA=Y -e SA_PASSWORD=MS-SQLServer \
  mcr.microsoft.com/mssql/server:2022-latest \
)
```

Start a client, connect, and create a table
```sql
docker run --rm -i --link $sqlserver:db \
  mcr.microsoft.com/mssql-tools \
  /opt/mssql-tools/bin/sqlcmd -S db -U SA -P MS-SQLServer -e -Q '
select @@version;
create database franck;
go
alter database franck set allow_snapshot_isolation on;
alter database franck set read_committed_snapshot on;
go
use franck;
drop table if exists demo;
create table demo (
 primary key (id)
 , id uniqueidentifier default newid()
 , value float
);
'
```
```

select @@version;
create database franck;

--------------------------------------------------------------------
Microsoft SQL Server 2022 (RTM-CU13) (KB5036432) - 16.0.4125.3 (X64)
        May  1 2024 15:05:56
        Copyright (C) 2022 Microsoft Corporation
        Developer Edition (64-bit) on Linux (Ubuntu 22.04.4 LTS) <X64>


(1 rows affected)
alter database franck set allow_snapshot_isolation on;
alter database franck set read_committed_snapshot on;

use franck;
drop table if exists demo;
create table demo (
 primary key (id)
 , id uniqueidentifier default newid()
 , value float
);

Changed database context to 'franck'.

```

Measure background activity when sleeping 10 seconds
```sql
perf stat -e instructions:u -G docker/$sqlserver -a \
docker run --rm -i --link $sqlserver:db \
  mcr.microsoft.com/mssql-tools \
  /opt/mssql-tools/bin/sqlcmd  -d franck -S db -U SA -P MS-SQLServer -e -Q "
waitfor delay '00:00:10';
"
```
```

waitfor delay '00:00:10';


 Performance counter stats for 'system wide':

       100,374,968      instructions:u            docker/85de543fbd9b1124794c2ef6537798a57edf01954da32d9d398b04b14d642712                     

      10.648215142 seconds time elapsed

```

Insert two million rows in two transactions of one million rows
```sql
perf stat -e instructions:u -G docker/$sqlserver -a \
docker run --rm -i --link $sqlserver:db \
  mcr.microsoft.com/mssql-tools \
  /opt/mssql-tools/bin/sqlcmd  -d franck -S db -U SA -P MS-SQLServer -e -Q "
insert into demo(value) select value from generate_series(1,1000000);
insert into demo(value) select value from generate_series(1,1000000);
"
```
```

insert into demo(value) select value from generate_series(1,1000000);
insert into demo(value) select value from generate_series(1,1000000);


(1000000 rows affected)

(1000000 rows affected)

 Performance counter stats for 'system wide':

    44,794,000,275      instructions:u            docker/85de543fbd9b1124794c2ef6537798a57edf01954da32d9d398b04b14d642712                     

      13.099580529 seconds time elapsed

```

Update those two million rows
```sql
perf stat -e instructions:u -G docker/$sqlserver -a \
docker run --rm -i --link $sqlserver:db \
  mcr.microsoft.com/mssql-tools \
  /opt/mssql-tools/bin/sqlcmd  -d franck -S db -U SA -P MS-SQLServer -e -Q "
update demo set value=value+1;
"
```
```
update demo set value=value+1;


(2000000 rows affected)

 Performance counter stats for 'system wide':

    21,674,930,278      instructions:u            docker/85de543fbd9b1124794c2ef6537798a57edf01954da32d9d398b04b14d642712                     

      16.542750712 seconds time elapsed

```

Count those two million values
```sql
perf stat -e instructions:u -G docker/$sqlserver -a \
docker run --rm -i --link $sqlserver:db \
  mcr.microsoft.com/mssql-tools \
  /opt/mssql-tools/bin/sqlcmd  -d franck -S db -U SA -P MS-SQLServer -e -Q "
select count(value) from demo;
"
```
```
select count(value) from demo;


-----------
    2000000

(1 rows affected)

 Performance counter stats for 'system wide':

     1,064,211,968      instructions:u            docker/85de543fbd9b1124794c2ef6537798a57edf01954da32d9d398b04b14d642712                     

       0.672937713 seconds time elapsed

```

Delete those two million rows
```sql
perf stat -e instructions:u -G docker/$sqlserver -a \
docker run --rm -i --link $sqlserver:db \
  mcr.microsoft.com/mssql-tools \
  /opt/mssql-tools/bin/sqlcmd  -d franck -S db -U SA -P MS-SQLServer -e -Q "
delete from demo;
"
```
```
delete from demo;


(2000000 rows affected)

 Performance counter stats for 'system wide':

    17,697,977,289      instructions:u            docker/85de543fbd9b1124794c2ef6537798a57edf01954da32d9d398b04b14d642712                     

       4.760425858 seconds time elapsed

```

## CockroachDB

Start the database in a Docker container
```sh
cockroachdb=$(
docker run -d \
 cockroachdb/cockroach \
 bash -c 'cockroach start-single-node --insecure'
)
```

Start a client, connect, and create a table
```sql
docker run --rm -i --link $cockroachdb:db postgres \
  psql -h db -p 26257 -U root -d defaultdb -e <<'SQL'
select version();
drop table if exists demo;
create table demo (
 primary key (id)
 , id uuid default gen_random_uuid()
 , value float
);
SQL
```
```
select version();
                                                 version
---------------------------------------------------------------------------------------------------------
 CockroachDB CCL v24.1.0 (x86_64-pc-linux-gnu, built 2024/05/15 21:28:29, go1.22.2 X:nocoverageredesign)
(1 row)

drop table if exists demo;
DROP TABLE
create table demo (
 primary key (id)
 , id uuid default gen_random_uuid()
 , value float
);
CREATE TABLE

```

Measure background activity when sleeping 10 seconds
```sql
perf stat -e instructions:u -G docker/$cockroachdb -a \
docker run --rm -i --link $cockroachdb:db postgres \
  psql -h db -p 26257 -U root -d defaultdb -e <<'SQL'
select pg_sleep(10);
SQL
```
```
select pg_sleep(10);
 pg_sleep
----------
 t
(1 row)


 Performance counter stats for 'system wide':

     7,449,329,979      instructions:u              docker/17aa81758d4af146a23dd785c046e2b27f5926ccc561f7a67c654d1e5d7f587d

      10.676270411 seconds time elapsed

```

Insert two million rows in two transactions of one million rows
```sql
perf stat -e instructions:u -G docker/$cockroachdb -a \
docker run --rm -i --link $cockroachdb:db postgres \
  psql -h db -p 26257 -U root -d defaultdb -e <<'SQL'
insert into demo(value) select generate_series(1,1000000);
insert into demo(value) select generate_series(1,1000000);
SQL
```
```
insert into demo(value) select generate_series(1,1000000);
INSERT 0 1000000
insert into demo(value) select generate_series(1,1000000);
INSERT 0 1000000

 Performance counter stats for 'system wide':

 1,344,459,032,711      instructions:u              docker/17aa81758d4af146a23dd785c046e2b27f5926ccc561f7a67c654d1e5d7f587d

     457.629554299 seconds time elapsed

```

Update those two million rows
```sql
perf stat -e instructions:u -G docker/$cockroachdb -a \
docker run --rm -i --link $cockroachdb:db postgres \
  psql -h db -p 26257 -U root -d defaultdb -e <<'SQL'
update demo set value=value+1;
SQL
```
```
update demo set value=value+1;
UPDATE 2000000

 Performance counter stats for 'system wide':

   747,076,086,139      instructions:u              docker/17aa81758d4af146a23dd785c046e2b27f5926ccc561f7a67c654d1e5d7f587d

     395.113462545 seconds time elapsed

```

Count those two million values
```sql
perf stat -e instructions:u -G docker/$cockroachdb -a \
docker run --rm -i --link $cockroachdb:db postgres \
  psql -h db -p 26257 -U root -d defaultdb -e <<'SQL'
select count(value) from demo;
SQL
```
```
select count(value) from demo;
  count
---------
 2000000
(1 row)

 Performance counter stats for 'system wide':

    12,906,358,871      instructions:u              docker/17aa81758d4af146a23dd785c046e2b27f5926ccc561f7a67c654d1e5d7f587d

       2.983402815 seconds time elapsed

```

Delete those two million rows
```sql
perf stat -e instructions:u -G docker/$cockroachdb -a \
docker run --rm -i --link $cockroachdb:db postgres \
  psql -h db -p 26257 -U root -d defaultdb -e <<'SQL'
delete from demo;
SQL
```
```
delete from demo;
DELETE 2000000

 Performance counter stats for 'system wide':

   799,367,485,634      instructions:u              docker/17aa81758d4af146a23dd785c046e2b27f5926ccc561f7a67c654d1e5d7f587d

     486.132498193 seconds time elapsed

```

## MySQL

Start the database in a Docker container
```sh
mysql=$(
docker run -d \
 -e MYSQL_ROOT_PASSWORD=secret -e MSQL_DATABASE=db -e MYSQL_USER=franck -e MYSQL_PASSWORD=franck -e MYSQL_ROOT_HOST=% \
 mysql:latest \
)
```

Start a client, connect, and create a table
```sql
docker run --rm -i --link $mysql:db mysql:latest \
  mysql -h db -P 3306 -u root -psecret -v <<'SQL'
select version();
create database if not exists db;
use db;
drop table if exists demo;
create table demo (
 primary key (id)
 , id binary(32) default (UUID_TO_BIN(UUID()))
 , value float
);
SQL
```
```
mysql: [Warning] Using a password on the command line interface can be insecure.
--------------
select version()
--------------

version()
8.4.0
--------------
create database if not exists db
--------------

--------------
drop table if exists demo
--------------

--------------
create table demo (
 primary key (id)
 , id binary(32) default (UUID_TO_BIN(UUID()))
 , value float
)
--------------

```

Measure background activity when sleeping 10 seconds
```sql
perf stat -e instructions:u -G docker/$mysql -a \
docker run --rm -i --link $mysql:db mysql:latest \
  mysql -h db -P 3306 -u root -psecret -v -e '
do sleep(10);
'
```
```
mysql: [Warning] Using a password on the command line interface can be insecure.
--------------
do sleep(10)
--------------


 Performance counter stats for 'system wide':

        26,942,875      instructions:u              docker/379507f1eac6f65bd3a88b7eeaf6c3cc2e084912fa76b22118521e8e35f37f31

      10.634240192 seconds time elapsed

```

Generating rows in MySQL is a bit more difficult. I'm using a WITH clause and CROSS JOIN.

Insert two million rows in two transactions of one million rows
```sql
perf stat -e instructions:u -G docker/$mysql -a \
docker run --rm -i --link $mysql:db mysql:latest \
  mysql -h db -P 3306 -u root -psecret -v -e '
INSERT INTO db.demo(value)
with x as ( SELECT 0 as x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 )
select x1.x+10*x2.x+100*x3.x+1000*x4.x+10000*x5.x+100000*x6.x from x x1 , x x2 , x x3, x x4, x x5, x x6;
commit;
INSERT INTO db.demo(value)
with x as ( SELECT 0 as x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 )
select x1.x+10*x2.x+100*x3.x+1000*x4.x+10000*x5.x+100000*x6.x from x x1 , x x2 , x x3, x x4, x x5, x x6;
commit;
'
```
```
mysql: [Warning] Using a password on the command line interface can be insecure.
--------------
INSERT INTO db.demo(value)
with x as ( SELECT 0 as x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 )
select x1.x+10*x2.x+100*x3.x+1000*x4.x+10000*x5.x+100000*x6.x from x x1 , x x2 , x x3, x x4, x x5, x x6
--------------

--------------
commit
--------------

--------------
INSERT INTO db.demo(value)
with x as ( SELECT 0 as x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 )
select x1.x+10*x2.x+100*x3.x+1000*x4.x+10000*x5.x+100000*x6.x from x x1 , x x2 , x x3, x x4, x x5, x x6
--------------

--------------
commit
--------------


 Performance counter stats for 'system wide':

    68,011,238,184      instructions:u              docker/f02f5a42cadc39cdbbc7c1c2213bd5697032cdaeee1e3881a17fa091dd87a9e0

      18.342903060 seconds time elapsed

```

Update those two million rows
```sql
perf stat -e instructions:u -G docker/$mysql -a \
docker run --rm -i --link $mysql:db mysql:latest \
  mysql -h db -P 3306 -u root -psecret -v -e '
update db.demo set value=value+1;
'
```
```
mysql: [Warning] Using a password on the command line interface can be insecure.
--------------
update db.demo set value=value+1
--------------


 Performance counter stats for 'system wide':

    67,272,334,190      instructions:u              docker/f02f5a42cadc39cdbbc7c1c2213bd5697032cdaeee1e3881a17fa091dd87a9e0

      21.026414415 seconds time elapsed

```

Count those two million values
```sql
perf stat -e instructions:u -G docker/$mysql -a \
docker run --rm -i --link $mysql:db mysql:latest \
  mysql -h db -P 3306 -u root -psecret -v -e '
select count(value) from db.demo;
'
```
```
mysql: [Warning] Using a password on the command line interface can be insecure.
--------------
select count(value) from db.demo
--------------

count(value)
2000000

 Performance counter stats for 'system wide':

     3,324,827,627      instructions:u              docker/f02f5a42cadc39cdbbc7c1c2213bd5697032cdaeee1e3881a17fa091dd87a9e0

       2.400244863 seconds time elapsed

```

Delete those two million rows
```sql
perf stat -e instructions:u -G docker/$mysql -a \
docker run --rm -i --link $mysql:db mysql:latest \
  mysql -h db -P 3306 -u root -psecret -v -e '
delete from db.demo;
'
```
```
mysql: [Warning] Using a password on the command line interface can be insecure.
--------------
delete from db.demo
--------------


 Performance counter stats for 'system wide':

    47,284,490,837      instructions:u              docker/f02f5a42cadc39cdbbc7c1c2213bd5697032cdaeee1e3881a17fa091dd87a9e0

      19.846219766 seconds time elapsed

```

## TiDB

Start the database in a Docker container
```sh
tidb=$(
 docker run -d \
  pingcap/tidb \
  tiup playground
)
```

When using the same CREATE TABLE as with MySQL, I got:
```
ERROR 3770 (HY000): Default value expression of column 'id' contains a disallowed function: `UUID_TO_BIN`
```
then I'll not use DEFAULT but put it in the INSERT.


Start a client, connect, and create a table
```sql
docker run --rm -i --link $tidb:db mysql:latest \
  mysql -h db -P 4000 -u root -v <<'SQL'
select version();
create database if not exists db;
use db;
drop table if exists demo;
create table demo (
 primary key (id)
 , id binary(32) -- default (UUID_TO_BIN(UUID())) -- 
 , value float
);
SQL
```
```
--------------
select version()
--------------

version()
8.0.11-TiDB-v7.5.1
--------------
create database if not exists db
--------------

--------------
drop table if exists demo
--------------

--------------
create table demo (
 primary key (id)
 , id binary(32) -- default (UUID_TO_BIN(UUID())) --
 , value float
)
--------------

```

Measure background activity when sleeping 10 seconds
```sql
perf stat -e instructions:u -G docker/$tidb -a \
docker run --rm -i --link $tidb:db mysql:latest \
  mysql -h db -P 4000 -u root -v -e '
do sleep(10);
'
```
```

--------------
do sleep(10)
--------------


 Performance counter stats for 'system wide':

       380,037,170      instructions:u            docker/13bcdc86b1e35ec92185d7c8ab7c169fd444c2205dfb41533012089e5b79ed78                     

      10.615474417 seconds time elapsed

```

Insert two million rows in two transactions of one million rows
```sql
perf stat -e instructions:u -G docker/$tidb -a \
docker run --rm -i --link $tidb:db mysql:latest \
  mysql -h db -P 4000 -u root -v -e '
INSERT INTO db.demo(id,value)
with x as ( SELECT 0 as x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 )
select UUID_TO_BIN(UUID()),x1.x+10*x2.x+100*x3.x+1000*x4.x+10000*x5.x+100000*x6.x from x x1 , x x2 , x x3, x x4, x x5, x x6;
commit;
INSERT INTO db.demo(id,value)
with x as ( SELECT 0 as x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 )
select UUID_TO_BIN(UUID()),x1.x+10*x2.x+100*x3.x+1000*x4.x+10000*x5.x+100000*x6.x from x x1 , x x2 , x x3, x x4, x x5, x x6;
commit;
'
```
```

--------------
INSERT INTO db.demo(id,value)
with x as ( SELECT 0 as x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 )
select UUID_TO_BIN(UUID()),x1.x+10*x2.x+100*x3.x+1000*x4.x+10000*x5.x+100000*x6.x from x x1 , x x2 , x x3, x x4, x x5, x x6
--------------

--------------
commit
--------------

--------------
INSERT INTO db.demo(id,value)
with x as ( SELECT 0 as x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 )
select UUID_TO_BIN(UUID()),x1.x+10*x2.x+100*x3.x+1000*x4.x+10000*x5.x+100000*x6.x from x x1 , x x2 , x x3, x x4, x x5, x x6
--------------

--------------
commit
--------------


 Performance counter stats for 'system wide':

   149,930,979,032      instructions:u            docker/13bcdc86b1e35ec92185d7c8ab7c169fd444c2205dfb41533012089e5b79ed78


      21.158571597 seconds time elapsed

```

Update those two million rows
```sql
perf stat -e instructions:u -G docker/$tidb -a \
docker run --rm -i --link $tidb:db mysql:latest \
  mysql -h db -P 4000 -u root -v -e '
update db.demo set value=value+1;
'
```
```

--------------
update db.demo set value=value+1
--------------

ERROR 1105 (HY000) at line 2: Your query has been cancelled due to exceeding the allowed memory limit for a single SQL query. Please try narrowing your query scope or increase the tidb_mem_quota_query limit and try again.[conn=2097160]

```

Doing the same with a larger `tidb_mem_quota_query` (4 GB):
```sql
perf stat -e instructions:u -G docker/$tidb -a \
docker run --rm -i --link $tidb:db mysql:latest \
  mysql -h db -P 4000 -u root -v -e '
set tidb_mem_quota_query = 4 << 30 ;
update db.demo set value=value+1;
'
```
```

--------------
set tidb_mem_quota_query = 4 << 30
--------------

--------------
update db.demo set value=value+1
--------------


 Performance counter stats for 'system wide':

   141,189,414,795      instructions:u            docker/11f53b1f64a1b596b0b47e66ad0d5bb4396299ce6f629d9a2c05283ecdf859e5                     

      25.442668815 seconds time elapsed

```

Count those two million values
```sql
perf stat -e instructions:u -G docker/$tidb -a \
docker run --rm -i --link $tidb:db mysql:latest \
  mysql -h db -P 4000 -u root -v -e '
select count(value) from db.demo;
'
```
```

--------------
select count(value) from db.demo
--------------

count(value)
2000000

 Performance counter stats for 'system wide':

     5,365,236,600      instructions:u            docker/13bcdc86b1e35ec92185d7c8ab7c169fd444c2205dfb41533012089e5b79ed78                     

       1.023350939 seconds time elapsed

```

Delete those two million rows
```sql
perf stat -e instructions:u -G docker/$tidb -a \
docker run --rm -i --link $tidb:db mysql:latest \
  mysql -h db -P 4000 -u root -v -e '
delete from db.demo;
'
```
```

--------------
delete from db.demo
--------------


 Performance counter stats for 'system wide':

   116,478,067,922      instructions:u            docker/13bcdc86b1e35ec92185d7c8ab7c169fd444c2205dfb41533012089e5b79ed78                     

      14.375729026 seconds time elapsed

```

## In conclusion

With those simple tests, the most popular open-source monolithic databases, PostgreSQL and MySQL, perform well and similarly. This is interesting because they have a completely different implementation: PostgreSQL uses heap tables with in-place multi-version concurrency control, whereas MySQL stores the table in its primary key B-Tree, and past versions are moved to the transactional undo log. The reason is that those databases have been there for a long time, and those simple workloads were optimized for each different architecture.

For the same reason, Oracle Database also performs well in terms of CPU usage, which is crucial given that it runs under a commercial license with an initial price and annual fees based on the physical CPU cores in most platforms, without the possibility of scaling down and reducing the support fees.

I have also run SQL Server, which has shown very good performance and has displayed the best results here. This is interesting to note, especially given that it was recently ported to Linux. Initially, I thought that it was faster because it does not use Multi-Version Concurrency Control like the others (and then paying the price of locks and deadlocks) but I re-ran the test after enabling Read Committed Snapshot Isolation and got the same result.

The three Distributed SQL databases that can be started in a container were tested. They have built-in resilience based on Raft to distribute and replicate and LSM Trees to store the distributed tables and indexes. 

TiDB shows good numbers. They are higher than the monolithic databases, but this is expected for a horizontally scalable database. Unlike monolithic databases that handle all tasks (parsing SQL, optimizing, executing the plan, reading and modifying the data pages, and transaction control structures) within a single process accessing local memory, distributed SQL databases must utilize a protocol to distribute read and write operations across multiple nodes.

I don't understand why CockroachDB uses so many CPU instructions for inserts and deletes. Even though CockroachDB doesn't offer packed rows, I created a simple two-column table where this disparity should not be noticeable. I generated a [perf report](https://dev.to/yugabyte/flamegraphs-on-steroids-with-profilerfirefoxcom-203f) and have seen many samples in the call stack (https://share.firefox.dev/3KwItMA) in Peeble's seek functions, their rewrite of RocksDB in Golang. Please comment if you think something is wrong with the setup. CockroachDB has only a subset of features available for free in the community edition, so maybe some optimizations are only available in the Enterprise edition. I tried the last version (`:latest-v20.2`) that allowed to use the `--storage-engine=rocksdb` and got slightly better numbers (513Gi/105s for the insert, 358Gi/54s for the update, 353Gi/44s for the select, 237Gi/33s).

YugabyteDB shows numbers closer to monolithic databases, with higher CPU utilization due to its use of multi-threading for batch processing of reads and writes. The advantages of this approach may not be immediately apparent when dealing with small, single-session queries. However, in distributed systems, while individual response times may be slightly higher, the overall throughput can increase significantly due to its scalable architecture. Note also that YugabyteDB calculates checksums by default to detect disk corruption. This uses CPU but is mandatory to avoid data loss.
