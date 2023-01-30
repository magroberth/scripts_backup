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
logfile_db=""

gcloud container clusters get-credentials camara --zone europe-west1-b --project plasma-weft-162417
gcloud container clusters get-credentials freyi-prod --zone europe-west1-b --project plasma-weft-162417
gcloud container clusters get-credentials freyi-test --zone europe-west1-b --project plasma-weft-162417
gcloud container clusters get-credentials kube-cluster-1 --zone europe-west1-b --project plasma-weft-162417

echo "Conectando con cluster $CLUSTER" 2>&1 | tee -a $logfile_db
case $CLUSTER in
	'camara' )
		#gcloud container clusters get-credentials camara --zone europe-west1-b --project plasma-weft-162417
		CLUSTER="--cluster=gke_plasma-weft-162417_europe-west1-b_camara"
		logfile_db="/var/log/backupodoo/backup_db_camara_$FECHA.txt"
		;;
	'freyi-prod' )
		#gcloud container clusters get-credentials freyi-prod --zone europe-west1-b --project plasma-weft-162417
		CLUSTER="--cluster=gke_plasma-weft-162417_europe-west1-b_freyi-prod"
		logfile_db="/var/log/backupodoo/backup_db_freyi-prod_$FECHA.txt"
		;;
	'freyi-test' )
		#gcloud container clusters get-credentials freyi-test --zone europe-west1-b --project plasma-weft-162417
		CLUSTER="--cluster=gke_plasma-weft-162417_europe-west1-b_freyi-test"
		logfile_db="/var/log/backupodoo/backup_db_freyi-test_$FECHA.txt"
		;;
	'kube-cluster-1' )
		#gcloud container clusters get-credentials kube-cluster-1 --zone europe-west1-b --project plasma-weft-162417
		CLUSTER="--cluster=gke_plasma-weft-162417_europe-west1-b_kube-cluster-1"
		logfile_db="/var/log/backupodoo/backup_db_kube-cluster-1_$FECHA.txt"
		;;
esac

if [[ -f $logfile_db ]]; then
	> $logfile_db
else
	touch $logfile_db
fi

if [[ ! -d $main_backup_dir ]]; then
	mkdir $main_backup_dir
fi

function dump()
{
	POD_PG=$(kubectl $CLUSTER  get pod -n $NAMESPACE -o name | awk '{print $2}' FS='/' | grep 'pg\|postgres')
	POD_ODOO=$(kubectl $CLUSTER  get pod -n $NAMESPACE -o name | awk '{print $2}' FS='/' | grep 'odoo')

	if [[ $POD_PG != "" ]]; then
		echo '[INFO] Haciendo backup de BD con postgresql' 2>&1 | tee -a $logfile_db
		echo "[INFO] Obteniendo nombres de BD's..." 2>&1 | tee -a $logfile_db
		DBLIST=$(kubectl $CLUSTER  exec -it $POD_ODOO -n $NAMESPACE -- bash -c "export PGPASSWORD=\${PASSWORD}; psql -A -U \$USER -h \$HOST -d postgres -c \"SELECT datname FROM pg_database WHERE datname NOT IN ('postgres', 'template1', 'template0')\" | head --lines=-1")
		
		for DATABASE in $DBLIST; do
			#DATABASE=$(echo ${DATABASE%?})

			DATABASE=`echo $DATABASE | sed 's/ *$//g'`
			
			if [[ $DATABASE != "datname" ]]; then
				echo "[INFO] Respaldando base de datos: ${DATABASE}" 2>&1 | tee -a $logfile_db  
				mkdir /tmp/$NAMESPACE
				kubectl $CLUSTER  exec -it $POD_PG -n $NAMESPACE -- bash -c "rm -f /tmp/dump* && export PGPASSWORD=\${POSTGRES_PASSWORD} && pg_dump -U \${POSTGRES_USER} -Fc ${DATABASE} > /tmp/${DATABASE}.dump "

				echo "[INFO] Extrayendo base de datos: ${DATABASE}" 2>&1 | tee -a $logfile_db
				kubectl $CLUSTER  -n $NAMESPACE cp $POD_PG:/tmp/${DATABASE}.dump /tmp/$NAMESPACE/${DATABASE}.dump
				cd /tmp/$NAMESPACE
				#echo "[INFO] Comprimiendo base de datos: ${DATABASE}" 2>&1 | tee -a $logfile_db
				#tar -czf /tmp/$NAMESPACE/dump_${DATABASE}.tar.gz ${DATABASE}.dump;
				echo "[INFO] Moviendo base de datos: ${DATABASE} al bucket" 2>&1 | tee -a $logfile_db
				#mv /tmp/$NAMESPACE/dump_${DATABASE}.tar.gz $backup_dir/dump_${DATABASE}_$DATE_LOCAL.tar.gz
				mv /tmp/$NAMESPACE/${DATABASE}.dump $backup_dir/dump_${DATABASE}_$DATE_LOCAL.dump

				#kubectl $CLUSTER  cp $NAMESPACE/$POD_PG:/tmp/${DATABASE}.dump $backup_dir/dump_${DATABASE}_$DATE_LOCAL.dump

				echo "[INFO] Borrando archivos temporales del pod" 2>&1 | tee -a $logfile_db
				rm -f /tmp/$NAMESPACE/${DATABASE}.dump
				kubectl $CLUSTER  exec -it $POD_PG -n $NAMESPACE -- bash -c "rm -f /tmp/${DATABASE}.dump"
				#echo "[INFO] Borrando archivos temporales del host" 2>&1 | tee -a $logfile_db
				#rm -f /tmp/*
				echo "[INFO] Backup de base de datos ${DATABASE} generado satisfactoriamente" 2>&1 | tee -a $logfile_db
			fi
		done
	else
	  echo "[ERROR] No hay pods activos en este NAMESPACE $NAMESPACE" 2>&1 | tee -a $logfile_db
	fi
}

nss=$(kubectl $CLUSTER  get ns -o name | awk '{print $2}' FS='/')
echo "Comenzando proceso de respaldo de Base de datos en fecha y hora $DATE_LOCAL" 2>&1 | tee -a $logfile_db

echo "" 2>&1 | tee -a $logfile_db
echo "**************************************************************" 2>&1 | tee -a $logfile_db
echo "*********************** INICIO *******************************" 2>&1 | tee -a $logfile_db
echo "**************************************************************" 2>&1 | tee -a $logfile_db
echo "" 2>&1 | tee -a $logfile_db
for ns in $nss; do
	echo "Verificando archivo de configuracion en $ns" 2>&1 | tee -a $logfile_db
	NAMESPACE=$ns

	cm=$(kubectl $CLUSTER  -n $ns get configmap -o name | awk '{print $2}' FS='/' | egrep config-backup)
	if [[ $cm != "" ]]; then
		backup_db=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_db}')
		backup_db_engine=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_db_engine}')
		backup_db_retention=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_db_retention}')
		backup_filestore=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_filestore}')
		backup_fs_retention=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_filestore_retention}')
#		backup_name_filter=$(kubectl $CLUSTER  -n $ns get configmap $cm -o jsonpath='{.data.backup_name_filter}')
		echo "=====================================================" 2>&1 | tee -a $logfile_db
		echo "Realizar backup de BD : $backup_db" 2>&1 | tee -a $logfile_db
		echo "Motor de BD : $backup_db_engine" 2>&1 | tee -a $logfile_db
		echo "Dias de retencion de backup de base de datos : $backup_db_retention" 2>&1 | tee -a $logfile_db		
#		echo "Filtro para extraccion de BD : $backup_name_filter" 2>&1 | tee -a $logfile_db		
		echo "=====================================================" 2>&1 | tee -a $logfile_db
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

#		echo "Hacemos limpieza de los archivos de backup de acuerdo al tiempo de retencion" 2>&1 | tee -a $logfile_db

#		cmd="find $backup_dir -iname 'dump*' -atime +$backup_db_retention -type f -print -exec rm {} \;"
#		cmd2="find $backup_dir -iname 'backup_db*' -atime +$backup_db_retention -type f -print -exec rm {} \;"

#		echo "Ejecutando comando $cmd " 2>&1 | tee -a $logfile_db
#		eval $cmd; eval $cmd2

		if [[ $backup_db == "true" ]]; then
			echo 'Hacemos el backup de la BD segun el motor correspondiente, de momento solo activo con postgres' 2>&1 | tee -a $logfile_db
			
			case $backup_db_engine in
				'postgres' )
					echo "" 2>&1 | tee -a $logfile_db
					echo "**************************************************************" 2>&1 | tee -a $logfile_db
					dump
					echo "**************************************************************" 2>&1 | tee -a $logfile_db
					echo "" 2>&1 | tee -a $logfile_db
					;;
			esac
		fi		
	fi
done
DATE_FINAL=$(date '+%Y-%m-%d_%H-%M-%S')
echo "Finalizado proceso de respaldo de Base de datos en fecha y hora $DATE_FINAL" 2>&1 | tee -a $logfile_db
cp $logfile_db /mnt_backups/1-logs_y_reportes/
echo 'Fin!!!' 2>&1 | tee -a $logfile_db

rm -f /tmp/*.dump



