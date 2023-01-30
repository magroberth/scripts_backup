#!/bin/bash

clear

cd /home/magroberth/backups-db-y-fs-odoo

CLUSTER=$1
TIPO=$2
DATE_LOCAL=$(date '+%Y-%m-%d_%H-%M-%S')

sudo ln -sf /scripts/kdump /bin/kdump
backup_dir=""
logfile_db="/var/log/backupodoo/backup_db_$DATE_LOCAL.log"
logfile_fs="/var/log/backupodoo/backup_fs_$DATE_LOCAL.log"
main_backup_dir="/mnt_backups"
bucket_backups_name="bucket-backups-freyi"
NAMESPACE=""

if [[ -f $logfile_db ]]; then
	> $logfile_db
else
	touch $logfile_db
fi
if [[ -f $logfile_fs ]]; then
	> $logfile_fs
else
	touch $logfile_fs
fi

if [[ ! -d $main_backup_dir ]]; then
	mkdir $main_backup_dir
fi

echo "Conectando con cluster $CLUSTER" 2>&1 | tee -a $logfile_db
echo "Conectando con cluster $CLUSTER" 2>&1 | tee -a $logfile_fs
case $CLUSTER in
	'camara' )
		gcloud container clusters get-credentials camara --zone europe-west1-b --project plasma-weft-162417
		;;
	'freyi-prod' )
		gcloud container clusters get-credentials freyi-prod --zone europe-west1-b --project plasma-weft-162417
		;;
	'freyi-test' )
		gcloud container clusters get-credentials freyi-test --zone europe-west1-b --project plasma-weft-162417
		;;
	'kube-cluster-1' )
		gcloud container clusters get-credentials kube-cluster-1 --zone europe-west1-b --project plasma-weft-162417
		;;
esac


function dump()
{
	POD_PG=$(kubectl get pod -n $NAMESPACE -o name | awk '{print $2}' FS='/' | grep 'pg\|postgres')
	POD_ODOO=$(kubectl get pod -n $NAMESPACE -o name | awk '{print $2}' FS='/' | grep 'odoo')

	if [[ $POD_ODOO != "" && $POD_PG != "" ]]; then
		case $TIPO in
			'bd' )
				echo "[INFO] Get databases names..." 2>&1 | tee -a $logfile_db
				DBLIST=$(kubectl exec -it $POD_ODOO -n $NAMESPACE -- bash -c "export PGPASSWORD=\${PASSWORD}; psql -A -U \$USER -h \$HOST -d postgres -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('postgres', 'template1', 'template0')\" | head --lines=-1")
				
				for DATABASE in $DBLIST; do
					#DATABASE=$(echo ${DATABASE%?})

					DATABASE=`echo $DATABASE | sed 's/ *$//g'`
					
					if [[ $DATABASE != "datname" ]]; then
						echo "[INFO] Respaldando base de datos: ${DATABASE}" 2>&1 | tee -a $logfile_db  
						
						kubectl exec -it $POD_PG -n $NAMESPACE -- bash -c "rm -f /tmp/dump* && export PGPASSWORD=\${POSTGRES_PASSWORD} && pg_dump -U \${POSTGRES_USER} -Fc ${DATABASE} > /tmp/${DATABASE}.dump "

						echo "[INFO] Extrayendo base de datos: ${DATABASE}" 2>&1 | tee -a $logfile_db
						kubectl -n $NAMESPACE cp $POD_PG:/tmp/${DATABASE}.dump /tmp/${DATABASE}.dump
						cd /tmp
						#echo "[INFO] Comprimiendo base de datos: ${DATABASE}" 2>&1 | tee -a $logfile_db
						#tar -czf /tmp/dump_${DATABASE}.tar.gz ${DATABASE}.dump;
						echo "[INFO] Moviendo base de datos: ${DATABASE} al bucket" 2>&1 | tee -a $logfile_db
						#mv /tmp/dump_${DATABASE}.tar.gz $backup_dir/dump_${DATABASE}_$DATE_LOCAL.tar.gz
						mv /tmp/${DATABASE}.dump $backup_dir/dump_${DATABASE}_$DATE_LOCAL.dump

						#kubectl cp $NAMESPACE/$POD_PG:/tmp/${DATABASE}.dump $backup_dir/dump_${DATABASE}_$DATE_LOCAL.dump

						echo "[INFO] Borrando archivos temporales del pod" 2>&1 | tee -a $logfile_db
						rm -f ${DATABASE}.dump
						kubectl exec -it $POD_PG -n $NAMESPACE -- bash -c "rm -f /tmp/${DATABASE}.dump"
						#echo "[INFO] Borrando archivos temporales del host" 2>&1 | tee -a $logfile_db
						#rm -f /tmp/*
					fi
				done
				echo "[INFO] Backup de bases de datos generado satisfactoriamente" 2>&1 | tee -a $logfile_db
				;;
			'fs' )
				echo "[INFO] Extrayendo filestore a respaldar"  2>&1 | tee -a $logfile_fs
				kubectl -n $NAMESPACE cp $POD_ODOO:/var/lib/odoo/filestore /tmp/filestore
				cd /tmp/filestore
				
				for fs in $(ls -1 /tmp/filestore); do
					echo "[INFO] Comprimiendo fs $fs"  2>&1 | tee -a $logfile_fs
					#tar -czf /tmp/fs_${fs}.tar.gz ${fs}
					zip -q -0 -r /tmp/fs_${fs}.zip ${fs}
					echo "[INFO] Moviendo fs: ${fs} al bucket" 2>&1 | tee -a $logfile_fs
					mv /tmp/fs_${fs}.zip $backup_dir/filestore_${fs}_$DATE_LOCAL.zip
				done

				echo "[INFO] Borrando archivos temporales" 2>&1 | tee -a $logfile_fs
				rm -rf /tmp/filestore
				echo "[INFO] Backup de falestore generado satisfactoriamente" 2>&1 | tee -a $logfile_fs
				;;
		esac
		
	else
	  echo "[ERROR] No hay pods activos en este NAMESPACE $NAMESPACE" 2>&1 | tee -a $logfile_fs
	  echo "[ERROR] No hay pods activos en este NAMESPACE $NAMESPACE" 2>&1 | tee -a $logfile_db
	fi
}

nss=$(kubectl get ns -o name | awk '{print $2}' FS='/')
case $TIPO in
	'bd' )
		echo "Comenzando proceso de respaldo de $TIPO en fecha y hora $DATE_LOCAL" 2>&1 | tee -a $logfile_db
		;;
	'fs' )
		echo "Comenzando proceso de respaldo de $TIPO en fecha y hora $DATE_LOCAL" 2>&1 | tee -a $logfile_fs
		;;
esac

for ns in $nss; do
	echo "" 2>&1 | tee -a $logfile_db
	echo "**************************************************************" 2>&1 | tee -a $logfile_db
	echo "*********************** INICIO *******************************" 2>&1 | tee -a $logfile_db
	echo "**************************************************************" 2>&1 | tee -a $logfile_db
	echo "Verificando archivo de configuracion en $ns" 2>&1 | tee -a $logfile_db
	echo "" 2>&1 | tee -a $logfile_fs
	echo "**************************************************************" 2>&1 | tee -a $logfile_fs
	echo "*********************** INICIO *******************************" 2>&1 | tee -a $logfile_fs
	echo "**************************************************************" 2>&1 | tee -a $logfile_fs
	echo "Verificando archivo de configuracion en $ns" 2>&1 | tee -a $logfile_fs
	NAMESPACE=$ns

	cm=$(kubectl -n $ns get configmap -o name | awk '{print $2}' FS='/' | egrep config-backup)
	if [[ $cm != "" ]]; then
		backup_db=$(kubectl -n $ns get configmap $cm -o jsonpath='{.data.backup_db}')
		backup_db_engine=$(kubectl -n $ns get configmap $cm -o jsonpath='{.data.backup_db_engine}')
		backup_db_retention=$(kubectl -n $ns get configmap $cm -o jsonpath='{.data.backup_db_retention}')
		backup_filestore=$(kubectl -n $ns get configmap $cm -o jsonpath='{.data.backup_filestore}')
		backup_fs_retention=$(kubectl -n $ns get configmap $cm -o jsonpath='{.data.backup_filestore_retention}')
		case $TIPO in
			'bd' )
				echo "=====================================================" 2>&1 | tee -a $logfile_db
				echo "Realizar backup de BD : $backup_db" 2>&1 | tee -a $logfile_db
				echo "Motor de BD : $backup_db_engine" 2>&1 | tee -a $logfile_db
				echo "Dias de retencion de backup de base de datos : $backup_db_retention" 2>&1 | tee -a $logfile_db		
				echo "=====================================================" 2>&1 | tee -a $logfile_db
				;;
			'fs' )
				echo "=====================================================" 2>&1 | tee -a $logfile_fs
				echo "Realizar backup de Filestore : $backup_filestore" 2>&1 | tee -a $logfile_fs
				echo "Dias de retencion de backup : $backup_fs_retention" 2>&1 | tee -a $logfile_fs
				echo "=====================================================" 2>&1 | tee -a $logfile_fs
				;;
		esac
		backup_dir="$main_backup_dir/$ns"

		#Montamos la unidad bucket antes de crear el directorio correspondiente
		gcsfuse $bucket_backups_name $main_backup_dir

		if [[ ! -d $backup_dir ]]; then
			mkdir $backup_dir
		fi

		echo "Hacemos limpieza de los archivos de backup de acuerdo al tiempo de retencion" 2>&1 | tee -a $logfile_db
		echo "Hacemos limpieza de los archivos de backup de acuerdo al tiempo de retencion" 2>&1 | tee -a $logfile_fs

		cmd="find $backup_dir -iname 'dump*' -atime +$backup_db_retention -type f -print -exec rm {} \;"
		cmd1="find $backup_dir -iname 'filestore*' -atime +$backup_fs_retention -type f -print -exec rm {} \;"
		echo "Ejecutando comando $cmd " 2>&1 | tee -a $logfile_db
		eval $cmd
		echo "Ejecutando comando $cmd1 " 2>&1 | tee -a $logfile_fs
		eval $cmd1

		if [[ $backup_db == "true" ]]; then
			echo 'Hacemos el backup de la BD segun el motor correspondiente, de momento solo activo con postgres' 2>&1 | tee -a $logfile_db
			
			case $backup_db_engine in
				'postgres' )
					echo 'Haciendo backup de BD con postgresql' 2>&1 | tee -a $logfile_db
					echo 'Haciendo backup de filestore' 2>&1 | tee -a $logfile_fs
					dump
					;;
			esac
		fi		
	fi
done
DATE_FINAL=$(date '+%Y-%m-%d_%H-%M-%S')
case $TIPO in
	'bd' )
		echo "Finalizado proceso de respaldo de $TIPO en fecha y hora $DATE_FINAL" 2>&1 | tee -a $logfile_db
		echo 'Fin!!!' 2>&1 | tee -a $logfile_db
		;;
	'fs' )
		echo "Finalizado proceso de respaldo de $TIPO en fecha y hora $DATE_FINAL" 2>&1 | tee -a $logfile_fs
		echo 'Fin!!!' 2>&1 | tee -a $logfile_fs
		;;
esac
rm -rf /tmp/filestore*
rm -f /tmp/*.dump
rm -f /tmp/fs*



