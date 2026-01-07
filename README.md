![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        

# Automatically Configure New SQL Databases For AlwaysOn
**Post Date: September 30, 2016**        



## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Author](#Author)  
- [License](#License)       

## About-Process

<p>Here is an incredibly simple way to automatically configure new databases for AlwaysOn. Is there a better way? Of course; but this is just one method to get you going in the direction of automating your AlwaysOn environment.
In this example; I'll be using a simple Sharepoint Database Server.
About the MSFT
It's a basic 2 Member Node Cluster configuration (with file share node majority)
About SQL Server:
It's SQL Server 2014 Enterprise
What do you need for this configuration to work?
An SQL Server Agent Service Account that has OS, and SQL Rights on both Servers
2 Folders with the same name and path on each server.
2 Jobs with the same name, steps and logic.
About the Job Steps… All pure SQL.
Folder Names on each server: E:\SQLBACKUPS\NEW_ALWAYSON_DATABASES
Agent Jobs on each server: ALWAYSON – CONFIGURE NEW DATABASES
The folders are THE most important part of this process, and overall this depends heavily on the extended stored procedure: xp_dirtree
I'll go ahead, and layout the logic of each Job Step ( There are only 5 Job steps ) and we'll get to that later. For now; here's the basic idea of how this works.
  
* Checks to see servers involved in AlwaysOn configuration.
* Checks to see Availability Group
* Checks to see what databases are not presently configured for AlwaysOn.
* Changes those databases to Full Recovery.
* Disables Full Database backup job.
* Disables Transaction Log backup job.
* Runs 1 full backup locally to E:\SQLBACKUPS\ as the 'First_Backup_MyDatabase'.
* Deletes any backup files in the destination on the other servers folder path: %MyOtherServerName%\E$\SQLBACKUPS\NEW_ALWAYSON_DATABASES
* Runs 1 full backup across the network to the other member server.
* Runs 1 transaction log backup across the network to other member server.
* Checks local folder (E:\SQLBACKUPS\NEW_ALWAYSON_DATABASES) to see if any database backup files are found in it.
* If backup files DO NOT exist. ( stop the job at this step (Step 2). This is represented in the log as a 'Job Cancellation', not a 'Job Failure'. It's just like right-clicking and stopping a job.
* If Backup files exist it builds a list of those backup files using xp_dirtree. Fyi; Backup files were sent to the local folder from the very same Job on the other server.
* Connects to Replica, Availability Groups, etc.
* Adds databases to Availability Group
* Re-Enables Full Backup Job.
* Re-Enables Transaction Log Backup Job.
* Drops the backup files from the local folder E:\SQLBACKUPS\NEW_ALWAYSON_DATABASES

That's it. 
Don't forget to re-enable your jobs for full database, and transaction log backups.
So yeah… Basically; both Jobs do exactly the same thing. Checks for new databases, makes a backup across to another server, and restores them there (along with various other configs naturally). You can set these Jobs to run every hour or so, or only on the weekends; what have you. By the way… You may notice some peculiarities with the logic. Just change it where needed. Also; I incorporated waitfor delay periodically. That's just what I do to give some seconds between each process. For example; when it's deleting files in the NEW_ALWAYS_ON folder, I give it about 20 seconds in case there are quite a bit a files in there, and some of which might be substantial in size; it might take a few seconds to remove them all.
Here's the Job Steps:

STEP 1: Set Database Properties Perform Full Backups </p>      


## SQL-Logic
```SQL
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
```


STEP 2: Restore Databases Locally
      

## SQL-Logic
```SQL
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
```

<p>STEP 3: Connect To Replicas</p>      


## SQL-Logic
```SQL
use master;
set nocount on
 
declare @availability_group varchar(255)
declare @connect_to_replica varchar(max)
set @availability_group = (select name from sys.availability_groups)
set @connect_to_replica =
'
-- Wait for the replica to start communicating begin try declare @conn bit declare @count int declare @replica_id uniqueidentifier declare @group_id uniqueidentifier set @conn = 0 set @count = 30 -- wait for 5 minutes 
 
if (serverproperty(''IsHadrEnabled'') = 1)
    and (isnull((
    select member_state 
    from master.sys.dm_hadr_cluster_members 
    where upper(member_name COLLATE Latin1_General_CI_AS) = upper(cast(serverproperty(''ComputerNamePhysicalNetBIOS'') as nvarchar(256)) COLLATE Latin1_General_CI_AS)), 0) != 0)
    and (isnull((select state from master.sys.database_mirroring_endpoints), 1) = 0) begin
    select @group_id = ags.group_id 
    from    master.sys.availability_groups as ags 
    where   name = N''' + @availability_group + '''
    select  @replica_id = replicas.replica_id 
    from    master.sys.availability_replicas as replicas 
    where   upper(replicas.replica_server_name COLLATE Latin1_General_CI_AS) = upper(@@SERVERNAME COLLATE Latin1_General_CI_AS) and group_id = @group_id
    while   @conn != 1 and @count != 0
    begin
        set @conn = isnull((select connected_state from master.sys.dm_hadr_availability_replica_states as states where states.replica_id = @replica_id), 1)
        if @conn = 1
        begin
            -- exit loop when the replica is connected, or if the query cannot find the replica status
            break
        end
        waitfor delay ''00:00:10''
        set @count = @count - 1
    end
end
end try
begin catch
    -- If the wait loop fails, do not stop execution of the alter database statement end catch '
 
exec (@connect_to_replica)
```

<p>STEP 4: Add Databases To Availability Groups </p>      


## SQL-Logic
```SQL
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
```

<p>STEP 5: Remove Former New AlwaysOn Database Backups </p>      


## SQL-Logic
```SQL
use master; set nocount on
 
-- enable database full and log backup jobs
exec    msdb..sp_update_job @job_name = 'DATABASE BACKUP LOG  - All Databases', @enabled = 1;
exec    msdb..sp_update_job @job_name = 'DATABASE BACKUP FULL - All Databases', @enabled = 1;
 
-- remove former backup files
declare @remove_former_backups  varchar(500)
set @remove_former_backups  = 'exec xp_cmdshell ''del /Q E:\SQLBACKUPS\NEW_ALWAYSON_DATABASES\*.*'''
exec    (@remove_former_backups)
```


[![WorksEveryTime](https://forthebadge.com/images/badges/60-percent-of-the-time-works-every-time.svg)](https://shitday.de/)

## Author

[![Gist](https://img.shields.io/badge/Gist-MikesDataWork-<COLOR>.svg)](https://gist.github.com/mikesdatawork)
[![Twitter](https://img.shields.io/badge/Twitter-MikesDataWork-<COLOR>.svg)](https://twitter.com/mikesdatawork)
[![Wordpress](https://img.shields.io/badge/Wordpress-MikesDataWork-<COLOR>.svg)](https://mikesdatawork.wordpress.com/)

      
## License
[![LicenseCCSA](https://img.shields.io/badge/License-CreativeCommonsSA-<COLOR>.svg)](https://creativecommons.org/share-your-work/licensing-types-examples/)

![Mikes Data Work](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_02.png "Mikes Data Work")

