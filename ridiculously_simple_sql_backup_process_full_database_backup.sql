use master; set nocount on
 
-- create temporary table to hold new databases if object_id('tempdb..#pending_alwayson_config') is not null
drop    table   #pending_alwayson_config
create  table   #pending_alwayson_config
(
    [server_name]   varchar(255)
,   [database_name] varchar(255)
)
 
-- populate temporary table with list of databases which are not added to AlwaysOn configuration insert into #pending_alwayson_config
    select
        'server_name'   = upper(@@servername)
    ,   'database_name' = upper(sd.name)
    from
         master.sys.databases sd
         left join master.sys.dm_hadr_database_replica_cluster_states sdhdrcs on sd.name = sdhdrcs.database_name
    where
         sd.name not in (select database_name from master.sys.dm_hadr_database_replica_cluster_states)
         and sd.database_id > 4
         and sd.state_desc = 'online'
    order by
        sd.name asc
 
declare @availability_group         varchar(255)
declare @other_member_server        varchar(255) 
declare @remove_former_backups      varchar(500)
declare @change_recovery            varchar(max)
declare @set_ao_configs_for_db      varchar(max)
set @availability_group         = (select name from sys.availability_groups)
set @other_member_server        = (select member_name from sys.dm_hadr_cluster_members  where member_type_desc = 'cluster_node' and [member_name] not in (@@servername))
set @remove_former_backups      = 'exec xp_cmdshell ''del \\' + @other_member_server + '\E$\SQLBACKUPS\NEW_ALWAYSON_DATABASES\*.bak'''
set @change_recovery            = ''
set @set_ao_configs_for_db      = ''
 
select  @change_recovery            = @change_recovery +
'alter database [' + name + '] set recovery full;' + char(10)
from    #pending_alwayson_config pac join sys.databases sd on pac.database_name = sd.name
where   sd.recovery_model_desc      = 'simple'
 
select  @set_ao_configs_for_db      = @set_ao_configs_for_db +
'backup database ['             + [database_name] +     '] to disk = ''E:\SQLBACKUPS\First_Backup_' + upper([database_name]) + '.bak'' with format, compression;' + char(10) +
'alter availability group ['            + @availability_group +     '] add database [' + [database_name] + '];' + char(10) +
'backup database ['             + [database_name] +     '] to disk = ''\\' + @other_member_server + '\E$\SQLBACKUPS\NEW_ALWAYSON_DATABASES\' + upper([database_name]) + '.bak'' with format;' + char(10) +
'waitfor delay ''00:00:03'';'           + char(10) +     
'backup log ['                  + [database_name] +     '] to disk = ''\\' + @other_member_server + '\E$\SQLBACKUPS\NEW_ALWAYSON_DATABASES\' + upper([database_name]) + '.trn'';' + char(10)
from    #pending_alwayson_config
 
-- 1. disable full and transaction log backup jobs (yours might be different) change the backup job names accordingly
exec    msdb..sp_update_job @job_name = 'DATABASE BACKUP LOG  - All Databases', @enabled = 0;
exec    msdb..sp_update_job @job_name = 'DATABASE BACKUP FULL - All Databases', @enabled = 0;
 
-- 2. delete any existing backup files if they exist at the destination server
exec    (@remove_former_backups)
 
-- 3. give extra 20 seconds time for files to be deleted at destination server
waitfor     delay '00:00:20'
 
-- 4. if any databases are found to have simple recovery model; change to 'full'
exec    (@change_recovery)
 
-- 5. create backup files to local location as 'First_Backup_*', then add to availability group, then backup databases to destination server as MyDatabaseName.bak/.trn
exec    (@set_ao_configs_for_db)
