insert into demo(value) select generate_series from generate_series(1,100000);
vacuum;
