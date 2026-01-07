use master; set nocount on
 
-- enable database full and log backup jobs
exec    msdb..sp_update_job @job_name = 'DATABASE BACKUP LOG  - All Databases', @enabled = 1;
exec    msdb..sp_update_job @job_name = 'DATABASE BACKUP FULL - All Databases', @enabled = 1;
 
-- remove former backup files
declare @remove_former_backups  varchar(500)
set @remove_former_backups  = 'exec xp_cmdshell ''del /Q E:\SQLBACKUPS\NEW_ALWAYSON_DATABASES\*.*'''
exec    (@remove_former_backups)
