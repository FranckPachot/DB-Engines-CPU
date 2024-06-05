drop table if exists demo;
alias vacuum=prompt;

create or replace function generate_series( "start" in int, "stop" in int )
  return varchar2 SQL_MACRO(TABLE) as
begin
 return 'select to_number(column_value) as generate_series from xmltable('''
  ||generate_series."start"||' to '||generate_series."stop"
  ||''')';
end;
/

select version();
