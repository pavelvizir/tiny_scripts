USE [master]
declare @listofdb table (db varchar(50),recreate int)
declare @db varchar(50)
declare @recreate int
declare @command varchar(2000)
-- \n\n -> \n, ^(\w+)$ -> ('$1',0),
insert into @listofdb (db,recreate) values
('db1',0),
('db2',0),
('db3',0),
('db4',0),
('db5',0),
('db6',0),
('db7',0),
('db8',0),
('db9',0),
('db31',1),
('db32',1)

while exists (select db from @listofdb)
begin
	set @db = (select top 1 db from @listofdb order by db)
	set @recreate = (select top 1 recreate from @listofdb order by db)

if db_id(@db) is not null set @command = 'EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N''' + @db + ''';
ALTER DATABASE [' + @db + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [' + @db + '];'
	if @recreate = 1 set @command = @command + '
select 1 --- here goes create database param. //Add use master into loop body, get default db location prior to'
	print @command
--	exec(@command)
	delete from @listofdb where db = @db
	set @command = ''
end
