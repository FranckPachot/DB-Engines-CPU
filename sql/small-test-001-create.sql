create table demo(id int generated always as identity primary key, value float, c1 int, c2 int, c3 int, c4 int, c5 int);
create index demo_value on demo(value asc);
