#!/bin/bash
#set -x -e

# This script for installation OSM Tile Server on Ubuntu 20.04

# Script must  be run under sudo

# VARS

read -e -p "Enter server IP address or FQDN: " -i "$(curl -s https://ipecho.net/plain)" IP #its public IP

# If you need use it variable for local IP $(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

#USER
read -e -p "Enter username(default "osm"): " -i "osm" USER
read -e -p "Enter database name(default "gis"): " -i "gis" DB

InstallPackages() {

    # Add repos  and install all needed packages mapnik and etc

    cat /etc/os-release | grep 20.04 &>/dev/null

    if [[ $? -eq 0 ]]; then
        # Ubuntu 20.04 is MATCH
        apt update && apt upgrade --yes
        apt install --yes wget \
            software-properties-common \
            dirmngr \
            ca-certificates \
            apt-transport-https lsb-release \
            curl
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/postgresql-pgdg.list
        add-apt-repository --yes ppa:osmadmins/ppa
        apt update
        ##now installing all important packages
        apt install --no-install-recommends --yes screen \
            locate \
            git \
            tar \
            unzip \
            bzip2 \
            net-tools \
            postgis-doc \
            postgis \
            postgresql-15 \
            postgresql-client-15 \
            postgresql-client-common \
            postgresql-15-postgis-3 \
            postgresql-15-postgis-3-dbgsym \
            postgresql-15-postgis-3-scripts \
            osm2pgsql \
            gdal-bin \
            mapnik-utils \
            python3-pip \
            python3-yaml \
            python3-pretty-yaml \
            python3-psycopg2 \
            python3-mapnik \
            apache2 \
            libmapnik-dev \
            apache2-dev \
            autoconf \
            libtool \
            libxml2-dev \
            libbz2-dev \
            libgeos-dev \
            libgeos++-dev \
            libproj-dev \
            build-essential \
            libcairo2-dev \
            libcurl4-gnutls-dev \
            libglib2.0-dev \
            libiniparser-dev \
            libmemcached-dev \
            librados-dev \
            fonts-dejavu \
            fonts-noto-cjk \
            fonts-noto-cjk-extra \
            fonts-noto-hinted \
            fonts-noto-unhinted \
            ttf-unifont \
            acl
    else
        echo "Its not a Ubuntu 20.04"
        exit 1
    fi

}

CreateUser() {

    # Create system user for map service

    adduser --system --group $USER #The name can be arbitrary but indistinguishable from the one we will create later for the database
    usermod -aG sudo $USER

}

ConfigurePostgres() {

    # Modifycation config postgresql for HPC

    num=$(free -g | grep Mem | awk '{print $2}')
    pers=25
    pers1=1.7
    pers2=13
    pers3=33
    cur_per=$(echo "($num*$pers)/100" | bc)   #min 4
    cur_per1=$(echo "($num*$pers1)/100" | bc) #min 60
    cur_per2=$(echo "($num*$pers2)/100" | bc) #min 8
    cur_per3=$(echo "($num*$pers3)/100" | bc) #min 4

    if [[ $num -gt 7 ]]; then
        sed -i "s|\shared_buffers = 128MB|shared_buffers = ${cur_per}GB|g" /etc/postgresql/15/main/postgresql.conf
        #sed -i "s|\#work_mem = 4MB|work_mem = ${cur_per1}GB|g" /etc/postgresql/15/main/postgresql.conf
        sed -i "s|\#maintenance_work_mem = 64MB|maintenance_work_mem = ${cur_per2}GB|g" /etc/postgresql/15/main/postgresql.conf
        sed -i "s|\#effective_cache_size = 4GB|effective_cache_size = ${cur_per3}GB|g" /etc/postgresql/15/main/postgresql.conf
        sed -i "s|\peer|trust|g" /etc/postgresql/15/main/pg_hba.conf
        #settings for HUGE PAGES
        touch /etc/sysctl.d/$num-custom.conf
        ppid=$(head -1 /var/lib/postgresql/15/main/postmaster.pid)
        result=$(grep ^VmPeak /proc/$ppid/status | awk '{print $2}')
        vmpeak=$(echo "$result/2048" | bc)
        echo "vm.nr_hugepages = $vmpeak" | tee -a /etc/sysctl.d/$num-custom.conf
        sysctl -p /etc/sysctl.d/$num-custom.conf
        systemctl restart postgresql@15-main
    elif [[ $num -gt 59 ]]; then
        sed -i "s|\shared_buffers = 128MB|shared_buffers = ${cur_per}GB|g" /etc/postgresql/15/main/postgresql.conf
        sed -i "s|\#work_mem = 4MB|work_mem = ${cur_per1}GB|g" /etc/postgresql/15/main/postgresql.conf
        sed -i "s|\#maintenance_work_mem = 64MB|maintenance_work_mem = ${cur_per2}GB|g" /etc/postgresql/15/main/postgresql.conf
        sed -i "s|\#effective_cache_size = 4GB|effective_cache_size = ${cur_per3}GB|g" /etc/postgresql/15/main/postgresql.conf
        sed -i "s|\peer|trust|g" /etc/postgresql/15/main/pg_hba.conf
        # Settings for HUGE PAGES
        touch /etc/sysctl.d/$num-custom.conf
        ppid=$(head -1 /var/lib/postgresql/15/main/postmaster.pid)
        result=$(grep ^VmPeak /proc/$ppid/status | awk '{print $2}')
        vmpeak=$(echo "$result/2048" | bc)
        echo "vm.nr_hugepages = $vmpeak" | tee -a /etc/sysctl.d/$num-custom.conf
        sysctl -p /etc/sysctl.d/$num-custom.conf
        systemctl restart postgresql@15-main
    else
        # Settings for HUGE PAGES
        touch /etc/sysctl.d/$num-custom.conf
        ppid=$(head -1 /var/lib/postgresql/15/main/postmaster.pid)
        result=$(grep ^VmPeak /proc/$ppid/status | awk '{print $2}')
        vmpeak=$(echo "$result/2048" | bc)
        echo "vm.nr_hugepages = $vmpeak" | tee -a /etc/sysctl.d/$num-custom.conf
        sysctl -p /etc/sysctl.d/$num-custom.conf
        sed -i "s|\peer|trust|g" /etc/postgresql/15/main/pg_hba.conf
        systemctl restart postgresql@15-main
    fi
}

CreateDataBase() {

    # Crate user and DB

    sudo -u postgres -i createuser $USER #Remember about the user and his name should be the same as the system user.
    sudo -u postgres -i createdb -E UTF8 -O $USER $DB

    # Create DB extensions

    sudo -u postgres -i psql -c "CREATE EXTENSION hstore;" -d $DB
    sudo -u postgres -i psql -c "CREATE EXTENSION postgis;" -d $DB
    sudo -u postgres -i psql -c "ALTER TABLE geometry_columns OWNER TO $USER;" -d $DB
    sudo -u postgres -i psql -c "ALTER TABLE spatial_ref_sys OWNER TO $USER;" -d $DB

}

InstallMapnik() {

    # MAPNIK Installation

    cd /home/$USER/
    python3 -c "import mapnik"
    curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
    apt-get install --yes nodejs
    git clone https://github.com/gravitystorm/openstreetmap-carto
    npm install -g carto

    # Download map file

    cd openstreetmap-carto/
    wget -P /home/osm/openstreetmap-carto/ https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf
    chown osm:osm -R /home/osm
    cd /home/osm/
    setfacl -R -m u:postgres:rwx /home/$USER/
}

ImportMap() {

    # Import map into DB

    mem=$(free -m | grep Mem | awk '{print $2}')
    proc=60
    cache_size=$(echo "($mem*$proc)/100" | bc)
    cd /home/$USER/openstreetmap-carto/
    sudo -u postgres osm2pgsql -d $DB --create --slim -G --hstore --tag-transform-script openstreetmap-carto.lua -C $cache_size --number-processes $(nproc) --style openstreetmap-carto.style luxembourg-latest.osm.pbf

    # After import change privelegies

    sudo -u postgres -i psql -c "ALTER DATABASE gis OWNER TO $USER;" -d $DB
    sudo -u postgres -i psql -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $USER;" -d $DB
    sudo -u postgres -i psql -c "grant all on planet_osm_polygon to $USER;" -d $DB
    sudo -u postgres -i psql -c "grant all on planet_osm_line to $USER;" -d $DB
    sudo -u postgres -i psql -c "grant all on planet_osm_point to $USER;" -d $DB
    sudo -u postgres -i psql -c "grant all on planet_osm_roads to $USER;" -d $DB
    sudo -u postgres -i psql -c "grant all on geometry_columns to $USER;" -d $DB
    sudo -u postgres -i psql -c "grant all on spatial_ref_sys to $USER;" -d $DB
    sudo -u postgres psql -d $DB -f indexes.sql
    sudo -u postgres scripts/get-fonts.sh
    sudo -u postgres scripts/get-external-data.py
    sudo -u postgres carto project.mml >mapnik.xml
    sudo -u postgres -i psql -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $USER;" -d $DB
}

InstallRenderMod() {

    ### #RENDERD & MOD_TILE ###

    cd /home/$USER/
    git clone -b switch2osm https://github.com/SomeoneElseOSM/mod_tile.git
    cd mod_tile
    ./autogen.sh
    ./configure
    make
    make install
    make install-mod_tile
    ldconfig

    # Create config file

    touch /etc/apache2/conf-available/mod_tile.conf
    cat <<EOF >/etc/apache2/conf-available/mod_tile.conf
LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so
EOF
    # Mod_tile run module

    sudo a2enconf mod_tile

    # Create renders directories

    mkdir --parents /var/run/renderd /var/lib/mod_tile/
    sudo chown $USER:$USER /var/run/renderd/ -R
    sudo chown $USER:$USER /var/lib/mod_tile/ -R

    # Create renderd config

    cat <<EOF >/etc/renderd.conf
[renderd]
stats_file=/var/run/renderd/renderd.stats
socketname=/var/run/renderd/renderd.sock
num_threads=$(nproc)
tile_dir=/var/lib/mod_tile

[mapnik]
plugins_dir=/usr/lib/mapnik/3.0/input/
font_dir=/usr/share/fonts/truetype
font_dir_recurse=true

[default]
URI=/$USER/
TILEDIR=/var/lib/mod_tile
XML=/home/$USER/openstreetmap-carto/mapnik.xml
HOST=localhost
TILESIZE=256
MAXZOOM=18
 
EOF

    # Create renderd service

    sed -i "s|\RUNASUSER=renderaccount|RUNASUSER=$USER|g" /home/$USER/mod_tile/debian/renderd.init
    sed -i "s|\/usr/local/etc/renderd.conf|/etc/renderd.conf|g" /home/$USER/mod_tile/debian/renderd.init
    cp /home/$USER/mod_tile/debian/renderd.init /etc/init.d/renderd
    chmod 755 /etc/init.d/renderd
    cp /home/$USER/mod_tile/debian/renderd.service /lib/systemd/system/
    /etc/init.d/renderd start
    systemctl enable renderd
    systemctl restart renderd

    # Apache2 settings

    cat <<EOF >/etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    LoadTileConfigFile /etc/renderd.conf
    ModTileRenderdSocketName /var/run/renderd/renderd.sock
    # Timeout before giving up for a tile to be rendered
    ModTileRequestTimeout 0
    # Timeout before giving up for a tile to be rendered that is otherwise missing
    ModTileMissingRequestTimeout 30
    DocumentRoot /var/www/html
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>

# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOF

    # Apache2 reaload & restart

    systemctl reload apache2
    systemctl reload apache2
    systemctl restart apache2

    # LEAFLET

    cd /var/www/html/
    wget https://leafletjs-cdn.s3.amazonaws.com/content/leaflet/v1.9.4/leaflet.zip
    unzip leaflet.zip

    cat <<EOF >index.html
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

L.tileLayer('http://$IP/$USER/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
}).addTo(map);

var hash = L.hash(map)
//]]>
</script>
</body>
</html>
EOF

    # Restart services and The End!!!!

    systemctl restart apache2
    systemctl restart renderd
    sleep 10

    echo " CONGRATS ALL INSTALLATIONS FINISHED!!!! "
    echo " Please check install to link:  http://$IP "
}

InstallPackages
CreateUser
ConfigurePostgres
CreateDataBase
InstallMapnik
ImportMap
InstallRenderMod
