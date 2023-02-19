
#!/bin/bash

#Руководство по установке OSM-tile сервера на убунту 20.04 
#в убунту и дебиане все можно  ставить из коробки, ничего не надо собирать, компилировать. все уже готово
# все выполняется под SUDO
#vars(переменные)
ipaddr=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
#Установим необходимые пакеты:
apt update && apt upgrade
apt install --yes  wget software-properties-common

#Добавим репозитории для postgres-11  и прочие для mapnik и mod_tile

wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/postgresql-pgdg.list &gt; /dev/null
add-apt-repository ppa:osmadmins/ppa
apt update

#Теперь установим необходимые пакеты:
apt install --yes curl screen locate git tar unzip  bzip2 net-tools postgis-doc postgis postgresql-11-postgis-2.5-dbgsym postgresql-11-postgis-2.5-scripts postgresql-11-postgis-2.5 postgresql-11-postgis-3-dbgsym postgresql-11-postgis-3-scripts postgresql-11-postgis-3 postgresql-11 postgresql-client-11 postgresql-client-common postgresql-common osm2pgsql gdal-bin mapnik-utils python3-pip python3-psycopg2 apache2 libapache2-mod-tile renderd  libmapnik-dev apache2-dev autoconf libtool libxml2-dev libbz2-dev libgeos-dev libgeos++-dev libproj-dev python3-mapnik build-essential libcairo2-dev libcurl4-gnutls-dev libglib2.0-dev libiniparser-dev libmemcached-dev librados-dev fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted ttf-unifont 


#создадим системного пользователя для работы рендеринга
adduser --system --group osm #имя может быть произвольным, но нне отличимым от того, которого мы создадим позже для БД
#Добавим АСL и доступ нашему пользователю в нужную директорию
apt install acl
sudo setfacl -R -m  u:postgres:rwx /home/osm/ 
#Далее все манипуляции будем выполнять в директори нашего пользователя
cd /home/osm/
#создадим пользователя и БД
sudo -u postgres -i
#создаем пользователя
createuser osm # помним про пользователя и его имя должно быть одинаковым как и системный пользователь
#сознаем БД
createdb -E UTF8 -O osm gis #gis это и есть имя БД
#создаем экстеншены в БД
psql -c "CREATE EXTENSION hstore;" -d gis
psql -c "CREATE EXTENSION postgis;" -d gis
psql -c "ALTER TABLE geometry_columns OWNER TO osm;" -d gis
psql -c "ALTER TABLE spatial_ref_sys OWNER TO osm;" -d gis
exit

###MAPNIK
python3
import mapnik  
quit()

#ставим carto
curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
apt-get install -y nodejs
sudo -H pip3 install psycopg2==2.8.5
git clone https://github.com/gravitystorm/openstreetmap-carto
cd openstreetmap-carto/
npm install -g carto
carto -v
carto project.mml > mapnik.xml

#скачиваем карту в формате osm.pbf на примере Калининградской области
wget https://download.geofabrik.de/russia/kaliningrad-latest.osm.pbf
#производим добавление карты в БД
sudo -u osm osm2pgsql -d gis --create --slim  -G --hstore --tag-transform-script ~osm/openstreetmap-carto/openstreetmap-carto.lua -C 2500 --number-processes 1 -S ~osm/openstreetmap-carto/openstreetmap-carto.style ~osm/openstreetmap-carto/kaliningrad-latest.osm.pbf

#Добавляем права на таблицы в 11 postgresql это необходимо
sudo -u postgres -i
psql -c "ALTER DATABASE gis OWNER TO osm;" -d gis;
psql -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO osm;" -d gis;
psql -c "grant all on planet_osm_polygon to postgres;" -d gis;
psql -c "grant all on planet_osm_line to postgres;" -d gis;
psql -c "grant all on planet_osm_point to postgres;" -d gis;
psql -c "grant all on planet_osm_roads to postgres;" -d gis;
psql -c "grant all on geometry_columns to postgres;" -d gis;
psql -c "grant all on spatial_ref_sys to postgres;" -d gis;
exit

#индексируем
sudo -u osm psql -d gis -f indexes.sql
sudo -u osm scripts/get-external-data.py
#устанавливаем шрифты
scripts/get-fonts.sh

#Создаем директории для РендерД
mkdir --parents /run/renderd /var/lib/mod_tile/
chown osm:osm /run/renderd/ -R
chown osm:osm /var/lib/mod_tile/ -R
#правим конфиг для рендерД
cat << EOF >> /etc/renderd.conf
[default]
URI=/osm/
TILEDIR=/var/lib/mod_tile
XML=/home/osm/openstreetmap-carto/mapnik.xml
HOST=localhost
TILESIZE=256
MAXZOOM=20
EOF

#правим сервис рендерД!
cat << EOF > /usr/lib/systemd/system/renderd.service
[Unit]
Description=Daemon that renders map tiles using mapnik
Documentation=man:renderd
After=network.target auditd.service

[Service]
User=osm
PIDFile=/var/run/renderd/renderd.pid
ExecStartPre=/bin/mkdir -p /var/run/renderd
ExecStart=/usr/bin/renderd -f -c /etc/renderd.conf
ExecStop=/usr/bin/killall renderd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
Environment=G_MESSAGES_DEBUG=all
EOF

#Создаем директорию для юнита и конфига
mkdir --parents /etc/systemd/system/renderd.service.d/
touch /etc/systemd/system/renderd.service.d/custom.conf
cat << EOF > /etc/systemd/system/renderd.service.d/custom.conf
[Service]
User=osm
EOF
#перезагружаем сервисы
systemctl daemon-reload
systemctl restart renderd
systemctl restart apache2
#добавляем модуль mod_tile
a2enmod tile
#Прописываем конфиг для apache2
cat << EOF >> /etc/apache2/sites-available/tileserver_site.conf
<VirtualHost *:80>
    ServerName $ipaddr 
    LogLevel info
    Include /etc/apache2/conf-available/renderd.conf

</VirtualHost>
EOF
#Добавим конфиг в АПАЧ
a2ensite tileserver_site.conf
systemctl restart apache2

#Настройка отображения карты
cd /var/www/html/
wget http://cdn.leafletjs.com/leaflet/v1.7.1/leaflet.zip
unzip leaflet.zip
#ВАЖНО ТАКЖЕ ЗАРАНЕЕ В СКРИПТЕ УКАЗАТЬ IP СЕРВЕРА в данном случае он отображается и прописывается автоматически,
cat << EOF > index.html
<!DOCTYPE html>
<html style="height:100%;margin:0;padding:0;">
<title>Leaflet page with OSM render server selection</title>
<meta charset="utf-8">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.3/dist/leaflet.css" />
<script src="https://unpkg.com/leaflet@1.3/dist/leaflet.js"></script>
<script src="https://unpkg.com/leaflet-hash@0.2.1/leaflet-hash.js"></script>
<style type="text/css">
.leaflet-tile-container { pointer-events: auto; }
</style>
</head>
<body style="height:100%;margin:0;padding:0;">
<div id="map" style="height:100%"></div>
<script>
//<![CDATA[
var map = L.map('map').setView([63, 100], 3);

L.tileLayer('http://$ipaddr/osm/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
}).addTo(map);

var hash = L.hash(map)
//]]>
</script>
</body>
</html>
EOF

#перезарускаем сервисы и все готово
systemctl restart apache2
systemctl restart renderd

echo "НАСТРОЙКА ЗАВЕРШЕНА"
