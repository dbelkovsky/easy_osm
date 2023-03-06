#!/bin/bash

#Руководство по установке OSM-tile сервера на Debian 10. !!! ВАЖНО ЗНАЧИТЕЛЬНО ОТЛИЧАЕТСЯ ОН UBUNTU 
#в убунту и дебиане не все можно  ставить из коробки, кое что придется и собирать, компилировать
# все выполняется под SUDO
#все сборки и команды выполняем в директории пользовятеля, от которого будет рабтать сервис в нашем случае osm
#vars(переменные)
ipaddr=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
USER=osm
cores=$(cat /proc/cpuinfo | grep  "cpu cores" | head -n 1 | awk '{print $4}')

#Установим необходимые пакеты:
sudo apt update --yes && sudo apt upgrade --yes

sudo apt install --yes git\
acl\
wget\
screen\
osm2pgsql\
autoconf\
libtool\
libmapnik-dev\
apache2-dev\
curl\
ttf-dejavu\
fonts-noto-cjk\
fonts-noto-cjk-extra\
fonts-noto-hinted\
fonts-noto-unhinted\ 
ttf-unifont\
npm\
unzip\
gdal-bin\
mapnik-utils\
libmapnik-dev\
python3-pip\
python3-psycopg2\
postgresql-11\
postgresql-11-postgis-2.5-dbgsym\
postgresql-11-postgis-2.5-scripts\
postgresql-11-postgis-2.5\
postgresql-11-postgis-3-dbgsym\
postgresql-11-postgis-3-scripts\
postgresql-11-postgis-3\  
postgresql-client-11\
postgresql-client-11-dbgsym 

#создадим системного пользователя для работы рендеринга
sudo adduser --system  $USER #имя может быть произвольным, но не отличимым от того, которого мы создадим позже для БД

#Переходим в директорию для дальнейшей корректно работы

cd /home/$USER/

#настройка БД
sudo -u postgres createuser $USER # помним про пользователя и его имя должно быть одинаковым как и системный пользователь

#сознаем БД
sudo -u postgres createdb -E UTF8 -O $USER gis #gis это и есть имя БД

#создаем экстеншены в БД
sudo -u postgres psql -c "CREATE EXTENSION hstore;" -d gis
sudo -u postgres psql -c "CREATE EXTENSION postgis;" -d gis
sudo -u postgres psql -c "ALTER TABLE geometry_columns OWNER TO $USER;" -d gis
sudo -u postgres psql -c "ALTER TABLE spatial_ref_sys OWNER TO $USER;" -d gis

#Настройка порта БД, иногда может не соответствовать требуемому значению
sudo sed -i 's/port = 5433/port = 5432/' /etc/postgresql/11/main/postgresql.conf
sudo service postgresql restart

##ставим carto
curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
sudo apt-get install --yes nodejs
sudo -H pip3 install psycopg2==2.8.5
sudo -H pip3 install pyyaml

git clone https://github.com/gravitystorm/openstreetmap-carto.git

#Добавим права на папку владельцу и пользователю postgres
sudo setfacl -R -m u:$USER:rwx /home/$USER
sudo setfacl -R -m u:postgres:rwx /home/$USER

#ПЕреходим в директорию
cd openstreetmap-carto/

#Ставим carto
npm install -g carto
carto -v
carto project.mml > mapnik.xml

#скачиваем карту в формате osm.pbf на примере Калининградской области
wget https://download.geofabrik.de/russia/kaliningrad-latest.osm.pbf

#производим добавление карты в БД
sudo -u $USER osm2pgsql -d gis --create --slim  -G --hstore --tag-transform-script /home/$USER/openstreetmap-carto/openstreetmap-carto.lua -C 2500 --number-processes 1 -S /home/$USER/openstreetmap-carto/openstreetmap-carto.style /home/$USER/openstreetmap-carto/kaliningrad-latest.osm.pbf

#Добавляем права на таблицы в 11 postgresql это необходимо
sudo -u postgres psql -c "ALTER DATABASE gis OWNER TO $USER;" -d gis;
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $USER;" -d gis;
sudo -u postgres psql -c "grant all on planet_osm_polygon to postgres;" -d gis;
sudo -u postgres psql -c "grant all on planet_osm_line to postgres;" -d gis;
sudo -u postgres psql -c "grant all on planet_osm_point to postgres;" -d gis;
sudo -u postgres psql -c "grant all on planet_osm_roads to postgres;" -d gis;
sudo -u postgres psql -c "grant all on geometry_columns to postgres;" -d gis;
sudo -u postgres psql -c "grant all on spatial_ref_sys to postgres;" -d gis;

#индексируем
sudo -u $USER psql -d gis -f indexes.sql
sudo -u $USER scripts/get-external-data.py

#устанавливаем шрифты
scripts/get-fonts.sh
cd /home/$USER


######RENDERD & MOD_TILE######
#Ставится он со своими особенностями.
версия mod_tile будет только 5. другая на 10 дебиан не втсает или требует слишком изощренной настройки.

wget https://github.com/openstreetmap/mod_tile/archive/refs/tags/0.5.tar.gz
tar -xf 0.5.tar.gz 
cd mod_tile-0.5/
sudo sed -i 's/7/9/' debian/compat
sudo sed -i 's/0.4-12~precise2/0.4.12~buster/' debian/changelog
./autogen.sh 
sudo dpkg-buildpackage -uc -us
cd ..
#Во время установки возникнет окно, которое требует согласия на изменения конфигов. нужно согласиться.
sudo apt install ./libapache2-mod-tile_0.4.12~buster_amd64.deb ./renderd_0.4.12~buster_amd64.deb

#Готовим директории
sudo mkdir --parents /var/run/renderd /var/lib/mod_tile/

#Правим конфиги:
sudo << EOF > cat /etc/renderd.conf
[renderd]
stats_file=/var/run/renderd/renderd.stats
socketname=/var/run/renderd/renderd.sock
num_threads=$cores
tile_dir=/var/lib/mod_tile

[mapnik]
plugins_dir=/usr/lib/mapnik/3.0/input/
font_dir=/usr/share/fonts/truetype/ttf-dejavu
font_dir_recurse=false

[default]
URI=/osm/
XML=/home/osm/openstreetmap-carto/mapnik.xml
DESCRIPTION=This is the standard osm mapnik style
;ATTRIBUTION=&copy;<a href=\"http://www.openstreetmap.org/\">OpenStreetMap</a> and <a href=\"http://wiki.openstreetmap.org/w\
iki/Contributors\">contributors</a>, <a href=\"http://creativecommons.org/licenses/by-sa/2.0/\">CC-BY-SA</a>
;HOST=tile.openstreetmap.org
;SERVER_ALIAS=http://a.tile.openstreetmap.org
;SERVER_ALIAS=http://b.tile.openstreetmap.org
;HTCPHOST=proxy.openstreetmap.org
HOST=localhost
TILESIZE=256
MAXZOOM=20
EOF

#второй конфиг:

sed -i 's/RUNASUSER=www-data/RUNASUSER=osm/' /etc/init.d/renderd

sed -i 's/DAEMON_ARGS=""/DAEMON_ARGS="-c etc/renderd.conf"/' /etc/init.d/renderd

sudo chown $USER /var/lib/mod_tile/ -R
sudo chown $USER /var/run/renderd/ -R

sudo systemctl daemon-reload
sudo systemctl restart renderd
sudo a2ensite tileserver_site.conf
sudo systemctl reload apache2
sudo systemctl reload apache2

#Настройка отображения карты
cd /var/www/
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
L.tileLayer('http://$ipaddr/$USER/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
}).addTo(map);
var hash = L.hash(map)
//]]>
</script>
</body>
</html>
EOF

#перезарускаем сервисы и все готово
sudo systemctl reload apache2
sudo systemctl reload apache2
sudo systemctl restart apache2
sudo systemctl restart renderd

echo "НАСТРОЙКА ЗАВЕРШЕНА"
