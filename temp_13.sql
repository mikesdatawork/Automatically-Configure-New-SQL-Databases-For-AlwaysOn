use master; set nocount on
-- declare path name to where backup files reside.
declare @path   varchar(255)
set @path   = 'E:\SQLBACKUPS\NEW_ALWAYSON_DATABASES\'
 
-- create temp table to list all backup files within the backup path if object_id('tempdb..#dirtree') is not null
      drop table #dirtree;
 
create table #dirtree
(
    id      int identity(1,1)
,   [subdirectory]  nvarchar(512)
,   depth       int
,   isfile      bit
);
 
-- populate temp table with backup file list insert into #dirtree ([subdirectory], depth, isfile) exec master..xp_dirtree @path, 1, 1
 
-- delete *.trn files from file list and drop *.bak extension from file list
delete from #dirtree    where   [subdirectory] like '%.trn';
update      #dirtree    set [subdirectory] = replace([subdirectory], '.bak', '')
 
-- produce and execute sql logic to add database to availability group
declare @availability_group     varchar(255)
declare @add_database_to_ag varchar(max)
set @availability_group     = (select name from sys.availability_groups)
set @add_database_to_ag = ''
select  @add_database_to_ag = @add_database_to_ag +
'alter database [' + [subdirectory] + '] set hadr availability group = [' + @availability_group + '];' + char(10)
from    #dirtree order by [subdirectory] asc
exec    (@add_database_to_ag)
