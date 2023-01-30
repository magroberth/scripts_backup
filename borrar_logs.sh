#!/bin/bash

clear

cd /home/magroberth/backups-db-y-fs-odoo
FECHA=$(date '+%Y-%m-%d')
logfile_fs="/var/log/backupodoo/borrado_logs_$FECHA.txt"
CLUSTER="kube-cluster-1"
CLUSTER1="freyi-prod"
backup_fs_retention="4"
backup_db_retention="9"
backup_dir="/mnt_backups"

if [[ -f $logfile_fs ]]; then
	> $logfile_fs
else
	touch $logfile_fs
fi

if [[ ! -d $backup_dir ]]; then
	mkdir $backup_dir
fi

echo "*******************************************************************************" 2>&1 | tee -a $logfile_fs
echo "Iniciando borrado de logs y envio de correo con los siguientes datos de entrada" 2>&1 | tee -a $logfile_fs
echo "=====================================================" 2>&1 | tee -a $logfile_fs
echo "Cluster : $CLUSTER" 2>&1 | tee -a $logfile_fs
echo "Cluster : $CLUSTER1" 2>&1 | tee -a $logfile_fs
echo "Dias de retencion de backup FS : $backup_fs_retention" 2>&1 | tee -a $logfile_fs
echo "Dias de retencion de backup DB : $backup_db_retention" 2>&1 | tee -a $logfile_fs
echo "Directorio para backups : $backup_dir" 2>&1 | tee -a $logfile_fs
echo "=====================================================" 2>&1 | tee -a $logfile_fs
echo "" 2>&1 | tee -a $logfile_fs

#Se borran los archivos de backup 
echo "Borrando los archivos de backup" 2>&1 | tee -a $logfile_fs
find $backup_dir -iname 'filestore*' -atime +$backup_fs_retention -type f -print 2>&1 | tee -a $logfile_fs
find $backup_dir -iname 'filestore*' -atime +$backup_fs_retention -type f -print -exec rm {} \;
find $backup_dir -iname 'dump*' -atime +$backup_db_retention -type f -print 2>&1 | tee -a $logfile_fs
find $backup_dir -iname 'dump*' -atime +$backup_db_retention -type f -print -exec rm {} \;

#Se borran los logs
echo "Borrando los archivos de logs" 2>&1 | tee -a $logfile_fs
find $backup_dir -iname 'backup_fs*' -atime +$backup_fs_retention -type f -print 2>&1 | tee -a $logfile_fs
find $backup_dir -iname 'backup_fs*' -atime +$backup_fs_retention -type f -print -exec rm {} \;
find $backup_dir -iname 'backup_db*' -atime +$backup_db_retention -type f -print 2>&1 | tee -a $logfile_fs
find $backup_dir -iname 'backup_db*' -atime +$backup_db_retention -type f -print -exec rm {} \;
find $backup_dir -iname 'borrado_logs*' -atime +$backup_fs_retention -type f -print 2>&1 | tee -a $logfile_fs
find $backup_dir -iname 'borrado_logs*' -atime +$backup_fs_retention -type f -print -exec rm {} \;

#Se borran los reportes
echo "Borrando reportes existentes" 2>&1 | tee -a $logfile_fs
rm /mnt_backups/1-logs_y_reportes/reporte*

echo "Generando archivo con reporte de respaldos " 2>&1 | tee -a $logfile_fs
tree -hD /mnt_backups/ | tee -a /mnt_backups/1-logs_y_reportes/reporte_$FECHA.txt
echo "Proceso de backup de los odoo de $CLUSTER concluida, se adjunta archivo de reporte y logs" | /usr/bin/mail -s \
	"Respaldo sistemas odoo al $FECHA" devops@guadaltech.es \
	-A "/mnt_backups/1-logs_y_reportes/backup_db_kube-cluster-1_$FECHA.txt" \
	-A "/mnt_backups/1-logs_y_reportes/backup_db_freyi-prod_$FECHA.txt" \
	-A "/mnt_backups/1-logs_y_reportes/backup_fs_kube-cluster-1_$FECHA.txt" \
	-A "/mnt_backups/1-logs_y_reportes/backup_fs_freyi-prod_$FECHA.txt" \
	-A "/mnt_backups/1-logs_y_reportes/reporte_$FECHA.txt"
echo "Proceso de respaldo exitoso!!!" 2>&1 | tee -a $logfile_fs
