-- Restores databases locally if the folder (E:\SQLBACKUPS\NEW_ALWAYSON_DATABASES\) has backup files in it ( sent from other member server ).  If no files exist; step will not perform any actions.
 
use master;
set nocount on
-- declare path name to where backups reside.
declare @path   varchar(255)
set @path   = 'E:\SQLBACKUPS\NEW_ALWAYSON_DATABASES\'
 
-- create temp table to list all backup files within the backup path if object_id('tempdb..#dirtree') is not null
      drop table #dirtree;
 
create table #dirtree
(
    id      int identity(1,1)
,   subdirectory    nvarchar(512)
,   depth       int
,   isfile      bit
);
 
-- populate temp table with backup file list insert into #dirtree (subdirectory, depth, isfile) exec master..xp_dirtree @path, 1, 1
 
-- restore the databases with no recovery - restore full backups first, then transaction logs second if not exists(select 1 from #dirtree)
    begin
        print 'There are no new databases to add to the AlwaysOn configuration.'
        -- enable database full and log backup jobs
        exec    msdb..sp_update_job @job_name = 'DATABASE BACKUP LOG  - All Databases', @enabled = 1;
        exec    msdb..sp_update_job @job_name = 'DATABASE BACKUP FULL - All Databases', @enabled = 1;
        -- stop job at this step
        exec msdb..sp_stop_job 'ALWAYSON - CONFIGURE NEW DATABASES'
    end
    else
        begin
        print 'New Databases exist so they will be added to the AlwaysOn configuration.'
        declare @restore    varchar(max)
        set @restore    = ''
        select  @restore    = @restore + 
            case 
                when right(subdirectory, 3) = 'bak' then 'restore database ['   + replace(subdirectory, '.bak', '') +       '] from disk = ''' + @path + subdirectory + ''' with norecovery;' + char(10)
                when right(subdirectory, 3) = 'trn' then 'restore log ['        + replace(subdirectory, '.trn', '') +       '] from disk = ''' + @path + subdirectory + ''' with norecovery;' + char(10)
            end
        from    #dirtree where subdirectory like '%.bak' or subdirectory like '%.trn' order by id asc
        exec (@restore)
    end
