#!/bin/bash

clear

cd /home/magroberth/backups-db-y-fs-odoo

CLUSTER=$1
DATE_LOCAL=$(date '+%Y-%m-%d_%H-%M-%S')
FECHA=$(date '+%Y-%m-%d')
sudo ln -sf /scripts/kdump /bin/kdump
backup_dir=""
main_backup_dir="/mnt_backups"
bucket_backups_name="bucket-backups-freyi"
NAMESPACE=""
DUMPOK="true"
logfile_fs=""

gcloud container clusters get-credentials camara --zone europe-west1-b --project plasma-weft-162417
gcloud container clusters get-credentials freyi-prod --zone europe-west1-b --project plasma-weft-162417
gcloud container clusters get-credentials freyi-test --zone europe-west1-b --project plasma-weft-162417
gcloud container clusters get-credentials kube-cluster-1 --zone europe-west1-b --project plasma-weft-162417

echo "Conectando con cluster $CLUSTER" 2>&1 | tee -a $logfile_fs
case $CLUSTER in
	'camara' )
		#gcloud container clusters get-credentials camara --zone europe-west1-b --project plasma-weft-162417
		CLUSTER="--cluster=gke_plasma-weft-162417_europe-west1-b_camara"
		logfile_fs="/var/log/backupodoo/backup_fs_camara_$FECHA.txt"
		;;
	'freyi-prod' )
		#gcloud container clusters get-credentials freyi-prod --zone europe-west1-b --project plasma-weft-162417
		CLUSTER="--cluster=gke_plasma-weft-162417_europe-west1-b_freyi-prod"
		logfile_fs="/var/log/backupodoo/backup_fs_freyi-prod_$FECHA.txt"
		;;
	'freyi-test' )
		#gcloud container clusters get-credentials freyi-test --zone europe-west1-b --project plasma-weft-162417
		CLUSTER="--cluster=gke_plasma-weft-162417_europe-west1-b_freyi-test"
		logfile_fs="/var/log/backupodoo/backup_fs_freyi-test_$FECHA.txt"
		;;
	'kube-cluster-1' )
		#gcloud container clusters get-credentials kube-cluster-1 --zone europe-west1-b --project plasma-weft-162417
		CLUSTER="--cluster=gke_plasma-weft-162417_europe-west1-b_kube-cluster-1"
		logfile_fs="/var/log/backupodoo/backup_fs_kube-cluster-1_$FECHA.txt"
		;;
esac

if [[ -f $logfile_fs ]]; then
	> $logfile_fs
else
	touch $logfile_fs
fi

if [[ ! -d $main_backup_dir ]]; then
	mkdir $main_backup_dir
fi


function dump()
{
	POD_ODOO=$(kubectl $CLUSTER  get pod -n $NAMESPACE -o name | awk '{print $2}' FS='/' | grep 'odoo')

	if [[ $POD_ODOO != "" ]]; then
		echo '[INFO] Haciendo backup de filestore' 2>&1 | tee -a $logfile_fs
		echo "[INFO] Extrayendo filestore a respaldar"  2>&1 | tee -a $logfile_fs
		mkdir /tmp/$NAMESPACE
		kubectl $CLUSTER  -n $NAMESPACE cp $POD_ODOO:/var/lib/odoo/filestore /tmp/$NAMESPACE/filestore

		if [[ -d /tmp/$NAMESPACE/filestore ]]; then
			cd /tmp/$NAMESPACE/filestore
			
			for fs in $(ls -1 /tmp/$NAMESPACE/filestore); do
				echo "[INFO] Comprimiendo fs $fs"  2>&1 | tee -a $logfile_fs
				#tar -czf /tmp/fs_${fs}.tar.gz ${fs}
				zip -q -0 -r /tmp/$NAMESPACE/fs_${fs}.zip ${fs}
				echo "[INFO] Moviendo fs: ${fs} al bucket" 2>&1 | tee -a $logfile_fs
				mv /tmp/$NAMESPACE/fs_${fs}.zip $backup_dir/filestore_${fs}_$DATE_LOCAL.zip
			done

			echo "[INFO] Borrando archivos temporales" 2>&1 | tee -a $logfile_fs
			rm -rf /tmp/$NAMESPACE/filestore*
			rm -f /tmp/$NAMESPACE/fs*
			echo "[INFO] Backup de filestore generado satisfactoriamente" 2>&1 | tee -a $logfile_fs
		else
			DUMPOK="false"
			echo "[INFO] Backup de filestore no ha podido ser generado por error en la extraccion del mismo" 2>&1 | tee -a $logfile_fs
		fi
	else
	  echo "[INFO] No hay pods activos en este NAMESPACE $NAMESPACE" 2>&1 | tee -a $logfile_fs
	  DUMPOK="false"
	fi
}

nss=$(kubectl $CLUSTER get ns -o name | awk '{print $2}' FS='/')
echo "Comenzando proceso de respaldo de Filestore en $CLUSTER fecha y hora $DATE_LOCAL" 2>&1 | tee -a $logfile_fs

echo "" 2>&1 | tee -a $logfile_fs
echo "**************************************************************" 2>&1 | tee -a $logfile_fs
echo "*********************** INICIO *******************************" 2>&1 | tee -a $logfile_fs
echo "**************************************************************" 2>&1 | tee -a $logfile_fs
echo "" 2>&1 | tee -a $logfile_fs
for ns in $nss; do
	echo "Verificando archivo de configuracion en $ns" 2>&1 | tee -a $logfile_fs
	NAMESPACE=$ns

	cm=$(kubectl $CLUSTER  -n $ns get configmap -o name | awk '{print $2}' FS='/' | egrep config-backup)
	if [[ $cm != "" ]]; then
		backup_db=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_db}')
		backup_db_engine=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_db_engine}')
		backup_db_retention=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_db_retention}')
		backup_filestore=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_filestore}')
		backup_fs_retention=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_filestore_retention}')
#		backup_name_filter=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_name_filter}')
		echo "=====================================================" 2>&1 | tee -a $logfile_fs
		echo "Realizar backup de Filestore : $backup_filestore" 2>&1 | tee -a $logfile_fs
		echo "Dias de retencion de backup : $backup_fs_retention" 2>&1 | tee -a $logfile_fs
#		echo "Filtro para extraccion de FS : $backup_name_filter" 2>&1 | tee -a $logfile_db		
		echo "=====================================================" 2>&1 | tee -a $logfile_fs
		backup_dir="$main_backup_dir/$ns"
		export CLUSTER=$CLUSTER
		export backup_fs_retention=$backup_fs_retention
		export backup_db_retention=$backup_db_retention
		export main_backup_dir=$main_backup_dir

		montado=$(df -h | grep -i bucket-backups-freyi)
		if [[ $montado == "" ]];then
			#Montamos la unidad bucket antes de crear el directorio correspondiente
			gcsfuse $bucket_backups_name $main_backup_dir
		fi
		if [[ ! -d $backup_dir ]]; then
			mkdir $backup_dir
		fi

#		echo "Hacemos limpieza de los archivos de backup de acuerdo al tiempo de retencion" 2>&1 | tee -a $logfile_fs

#		cmd1="find $backup_dir -iname 'filestore*' -atime +$backup_fs_retention -type f -print -exec rm {} \;"
#		cmd2="find $backup_dir -iname 'backup_fs*' -atime +$backup_fs_retention -type f -print -exec rm {} \;"

#		echo "Ejecutando comando $cmd1 " 2>&1 | tee -a $logfile_fs
#		eval $cmd1; eval $cmd2

		if [[ $backup_db == "true" ]]; then
			case $backup_db_engine in
				'postgres' )
					echo "" 2>&1 | tee -a $logfile_fs
					echo "**************************************************************" 2>&1 | tee -a $logfile_fs
					dump
					echo "**************************************************************" 2>&1 | tee -a $logfile_fs
					echo "" 2>&1 | tee -a $logfile_fs
					;;
			esac
		fi		
	fi
done
DATE_FINAL=$(date '+%Y-%m-%d_%H-%M-%S')
echo "Finalizado proceso de respaldo de Filestore en en $CLUSTER fecha y hora $DATE_FINAL" 2>&1 | tee -a $logfile_fs

# cmd="/home/magroberth/backups-db-y-fs-odoo/./borrar_logs.sh '$CLUSTER' '$DATE_LOCAL' '$backup_fs_retention' '$backup_db_retention' '$main_backup_dir' '$logfile_fs'"
# echo "Ejecutando comando " 2>&1 | tee -a $logfile_fs
# echo $cmd 2>&1 | tee -a $logfile_fs
# echo $cmd > /home/magroberth/borrado.sh
# chmod +x /home/magroberth/borrado.sh
# /home/magroberth/./borrado.sh
echo 'Fin!!!' 2>&1 | tee -a $logfile_fs

cp $logfile_fs /mnt_backups/1-logs_y_reportes/
rm -rf /tmp/filestore*
rm -f /tmp/fs*
