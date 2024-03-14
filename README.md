# How to install OSM TILE Server on Ubuntu 20.04

Its description how to manually install, setup and configure all the necessary software to operate your own tile server. These step-by-step instructions were written for Ubuntu Linux 20.04 LTS (Focal Fossa).

## Hardware Requirements

It’s recommended to use a server with a clean fresh OS.

The required RAM and disk space depend on which country’s map you are going to use. For example,

- The Luxembourge map requires at least 8G RAM and 30GB disk space.

- The UK map requires at least 12G RAM and 100GB disk space.

- The whole planet map requires at least 32G RAM and 1TB SSD (Solid State Drive). It’s not viable to use a spinning hard disk for the whole planet map.

You will need more disk space if you are going to pre-render tiles to speed up map loading in the web browser, which is highly recommended. Check this [tile disk usage page](https://wiki.openstreetmap.org/wiki/Tile_disk_usage) to see how much disk space are required for pre-rendering tiles. For example, if you are going to pre-render tiles from zoom level 0 to zoom level 15 for the planet map, an extra 460 GB disk space is required.

Another thing to note is that importing large map data, like the whole planet, to PostgreSQL database takes a long time. Consider adding more RAM and especially using SSD instead of spinning hard disk to speed up the import process.

## Services description

It consists of 5 main components: mod_tile, renderd, mapnik, osm2pgsql and a postgresql/postgis database.

- Mod_tile is an apache module that serves cached tiles and decides which tiles need re-rendering - either because they are not yet cached or because they are outdated.
- Renderd provides a priority queueing system for different sorts of requests to manage and smooth out the load from rendering requests.
- Mapnik is the software library that does the actual rendering and is used by renderd.
- Osm2pgsql is used to import OSM data into a PostgreSQL/PostGIS database for rendering into maps and many other uses.
- PostGIS is an extension to the PostgreSQL object-relational database system which allows GIS (Geographic Information Systems) objects to be stored in the database.

_The diagram shows an approximate operating principle of server components_

![schema](https://github.com/dbelkovsky/bash_scipts/blob/main/Osm_server.png)

## Quick start

To get started quickly, just download the [script](https://github.com/dbelkovsky/bash_scipts/blob/main/data/mapnik_deploy.sh) to a server with the Ubuntu 20.04 operating system installed. Switch to superuser and run it.

```
sudo -i

chmod u+x mapnik_deploy.sh

./mapnik_deploy.sh
```

_First you need to make changes to the script: indicate which osm.pbf file you need to download (everything that is specified by default - String # 187 Luxembourg). The script will ask the rest of the preliminary setup questions on its own._

**In a weak server configuration(2CPU, 8RAM, 30GbHDD) + map of Luxembourg, the server is ready for operation after 15 minutes it starts running the deployment [script](https://github.com/dbelkovsky/bash_scipts/blob/main/data/mapnik_deploy.sh).**

## Manual installation

### Create system user

This guide assumes that you run everything from a non-root user via “sudo”. The non-root username used by default below is “osm” - you can create that locally if you want, or edit scripts to refer to a different username if you want. If you do create the “osm” user you’ll need to add it to the group of users that can sudo to root. From your normal non-root user account:

```
sudo -i

adduser --system --group osm

usermod -aG sudo osm

exit
```

### Update system and install packages

To update the system and Install essential tools:

```
sudo apt-get update

sudo apt-get -y upgrade

apt install -y wget software-properties-common dirmngr ca-certificates apt-transport-https lsb-release curl
```

Add repos and install all packages:

```
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/postgresql-pgdg.list

add-apt-repository -y ppa:osmadmins/ppa

apt update

apt install --no-install-recommends -y screen locate git tar unzip bzip2 net-tools postgis-doc postgis postgresql-15 postgresql-client-15 postgresql-client-common postgresql-15-postgis-3 postgresql-15-postgis-3-dbgsym postgresql-15-postgis-3-scripts osm2pgsql gdal-bin mapnik-utils python3-pip python3-yaml python3-pretty-yaml python3-psycopg2 python3-mapnik apache2 libmapnik-dev apache2-dev autoconf libtool libxml2-dev libbz2-dev libgeos-dev libgeos++-dev libproj-dev build-essential libcairo2-dev libcurl4-gnutls-dev libglib2.0-dev libiniparser-dev libmemcached-dev librados-dev fonts-dejavu fonts-noto-cjk fonts-noto-cjk-extra fonts-noto-hinted fonts-noto-unhinted ttf-unifont acl
```

### Postgers/postGIS configurations

During a large installation of packages, we installed and launched the Postgres server and the geospatial extension PostGIS.

_PostgreSQL database server will automatically start and listens on 127.0.0.1:5432. The postgres user will be created on the OS during the installation process. It’s the super user for PostgreSQL database server. By default, this user has no password and there’s no need to set one because you can use sudo to switch to the postgres user and log into PostgreSQL server._

#### Optimize PostgreSQL Server Performance

The import process can take some time. To speed up this process, we can tune some PostgreSQL server settings to improve performance. Edit PostgreSQL main configuration file.

```
sudo vi /etc/postgresql/15/main/postgresql.conf
```

First, we should change the value of `hared_buffer`. The default setting is:

```
shared_buffers = 128MB
```

This is too small. The rule of thumb is to set it to 25% of your total RAM (excluding swap space). For example, my VPS has 60G RAM, so I set it to:

```
shared_buffers = 15GB
```

Find the following line:

```
#work_mem = 4MB
#maintenance_work_mem = 64MB
```

Again, the value is too small. I use the following settings:

```
work_mem = 1GB
maintenance_work_mem = 8GB
```

Then find the following line:

```
#effective_cache_size = 4GB
```

If you have lots of RAM like I do, you can set a higher value for the effective_cache_size like 20G:

```
effective_cache_size = 20GB
```

Save and close the file.

By default, PostgreSQL would try to use huge pages in RAM. However, Linux by default does not allocate huge pages. Check the process ID of PostgreSQL.

```
sudo head -1 /var/lib/postgresql/15/main/postmaster.pid

Sample output:

7031
```

Then check the VmPeak value of this process ID:

```
grep ^VmPeak /proc/7031/status

Sample output:

VmPeak: 16282784 kB
```

This is the peak memory size that will be used by PostgreSQL. Now check the size of huge page in Linux:

```
cat /proc/meminfo | grep -i huge

AnonHugePages:         0 kB
ShmemHugePages:        0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:               0 kB
```

**We can calculate how many huge pages we need. Divide the VmPeak value by the size of huge page: 16282784 kB / 2048 kB = 7950. Then we need to edit the sysctl files to change Linux kernel parameters. Instead of editing the /etc/sysctl.conf file, we create a custom config file, so your custom configurations won’t be overwritten when upgrading software packages:**

```
sudo touch /etc/sysctl.d/60-custom.conf
```

Then run the following command to allocate 7950 huge pages:

```
echo "vm.nr_hugepages = 7950" | sudo tee -a /etc/sysctl.d/60-custom.conf
```

Save and close the file. Apply the changes:

```
sudo sysctl -p /etc/sysctl.d/60-custom.conf
```

If you check the meminfo again:

```
cat /proc/meminfo | grep -i huge

AnonHugePages:         0 kB
ShmemHugePages:        0 kB
HugePages_Total:    7950
HugePages_Free:     7950
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
```

Restart PostgreSQL to save all changes and use huge pages.

```
sudo systemctl restart postgresql
```

### Create postgres user and batabase

Then create user "osm" a database named "gis" and at the same time make "osm" as the owner of the database. Please don’t change the database name. Other tools like Renderd and Mapnik assume there’s a database named "gis".

```
su postgres -l

createuser osm

createdb -E UTF8 -O osm gis
```

Create database extentions:

```
psql -c "CREATE EXTENSION hstore;" -d gis

psql -c "CREATE EXTENSION postgis;" -d gis

psql -c "ALTER TABLE geometry_columns OWNER TO osm;" -d gis

psql -c "ALTER TABLE spatial_ref_sys OWNER TO osm;" -d gis
```

Exit from the postgres user:

```
exit
```

### Istallation Mapnik & OpenStreetMap Carto

#### Mapnik installation

We need to install the Mapnik library. Mapnik is used to render the OpenStreetMap data into the tiles managed by the Apache web server through renderd and mod_tile.

```
python3 -c "import mapnik"
```

#### OpenStreetMap Carto installation

The home of “OpenStreetMap Carto” on the web is https://github.com/gravitystorm/openstreetmap-carto/ and it has it’s own installation instructions at https://github.com/gravitystorm/openstreetmap-carto/blob/master/INSTALL.md although we’ll cover everything that needs to be done here.

Here we’re assuming that we’re storing the stylesheet details in a directory below “/osm/” below the home directory of the “osm” user (or whichever other one you are using)

```
cd /home/osm/
curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -
apt-get install --yes nodejs
git clone https://github.com/gravitystorm/openstreetmap-carto
npm install -g carto
```

### Last preparations to import map into DB

We need to download map in working directory(for exmple is Luxembourg map):

```
cd /home/osm/openstreetmap-carto/
wget -P /home/osm/openstreetmap-carto/ https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf
```

After downloading change ownet to work directory:

```
chown osm:osm -R /home/osm/
```

And grant privelegues to `postgres` user to all files in work folder:

```
setfacl -R -m u:postgres:rwx /home/osm/
```

### Import the Map Data to PostgreSQL

To import map data, we need to use osm2pgsql which converts OpenStreetMap data to postGIS-enabled PostgreSQL databases.

Switch to the postgres user and change work directory:

```
cd /home/osm/openstreetmap-carto/
sudo -u postgres
```

Run the following command to load map stylesheet and map data into the gis database. Replace luxembourg-latest.osm.pbf with your own map data file.

```
osm2pgsql -d gis --create --slim -G --hstore --tag-transform-script openstreetmap-carto.lua -C 5600 --number-processes 2 --style openstreetmap-carto.style luxembourg-latest.osm.pbf
```

where

- `-d gis`: select database.
- `--create`: is default function
- `--slim`: run in slim mode rather than normal mode. This option is needed if you want to update the map data using OSM change files (OSC) in the future.
- `-G, --multi-geometry`: generate multi-geometry features in postgresql tables.
- `--hstore`: add tags without column to an additional hstore (key/value) column to PostgreSQL tables
- `--tag-transform-script`: its supports Lua scripts to rewrite tags before they enter the database.
- `-C, --cache=NUM`: flag specifies the cache size in MegaBytes. It should be around 70% of the free RAM on your machine. Bigger cache size results in faster import speed. For example, my server has 8GB free RAM, so I can specify -C 5600. Be aware that PostgreSQL will need RAM for shared_buffers. Use this formula to calculate how big the cache size should be: (Total RAM - PostgreSQL shared_buffers) \* 70%
- `--number-processes`: number of CPU cores on your server. I have 2.
- `--style`: specify the location of style file
- Finally, you need to specify the location of map data file.

And you will be able to continue your work. Once the import is complete, grant all privileges of the gis database to the osm user.

```
psql -c "ALTER DATABASE gis OWNER TO osm;" -d gis
psql -c "grant all on planet_osm_polygon to osm;" -d gis
psql -c "grant all on planet_osm_line to osm;" -d gis
psql -c "grant all on planet_osm_point to osm;" -d gis
psql -c "grant all on planet_osm_roads to osm;" -d gis
psql -c "grant all on geometry_columns to osm;" -d gis
psql -c "grant all on spatial_ref_sys to osm;" -d gis
```

**Creating indexes**

_Since version v5.3.0, some extra indexes now need to be [applied manually](https://github.com/gravitystorm/openstreetmap-carto/blob/master/CHANGELOG.md#v530---2021-01-28)._

```
psql -d gis -f indexes.sql
```

**Downloading Shapefile and adding Fonts**

Although most of the data used to create the map is directly from the OpenStreetMap data file that you downloaded above, some shapefiles for things like low-zoom country boundaries are still needed. Also In version v5.6.0 and above of Carto, fonts need to be installed manually:

```
scripts/get-fonts.sh && cripts/get-external-data.py
```

_This is not a quick process and may take quite some time, depending on the size of the map loaded into the database._

Then we convert the carto project into something that **Mapnik** can understand:

```
carto project.mml >mapnik.xml
```

Control assignment of privileges in the database:

```
psql -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO osm;" -d gis
```

Exit from the postgres user.

```
exit
```

**_Congrats! The database is now ready to use!_**

## Install Mod_tile and Renderd

### Mod_tile installation

**Making packages**

_Now, we’ll install mod_tile and renderd. “mod_tile” is an Apache module that handles requests for tiles; “renderd” is a daemon that actually renders tiles when “mod_tile” requests them. We’ll use the “switch2osm” branch of https://github.com/SomeoneElseOSM/mod_tile, which is itself forked from https://github.com/openstreetmap/mod_tile, but modified so that it supports Ubuntu 20.04, and with a couple of other changes to work on a standard Ubuntu server rather than one of OSM’s rendering servers._

Go to work directory:

```
cd /home/osm/
```

Clone the repo:

```
git clone -b switch2osm https://github.com/SomeoneElseOSM/mod_tile.git
```

Change build directory:

```
cd mod_tile
```

Run building commands:

```
./autogen.sh
./configure
make
sudo make install
sudo make install-mod_tile
sudo ldconfig
```

**After building and installing the packages, you need to continue configuring the services.**

Create mod_tile configuration file for apache2

```
vi /etc/apache2/conf-available/mod_tile.conf
```

and past into file following strings

```
LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so
```

Save changes and enable Apache2 module mod_tile

```
sudo a2enconf mod_tile
```

**Creating renderd and tile directories**

Create directories:

```
mkdir --parents /var/run/renderd /var/lib/mod_tile/
```

- _`/var/run/renderd` this is directory where starting rendering daemon_
- _`/var/lib/mod_tile/` this is the directory for saving generated tiles_

Grant full rights to the directories to `osm` user:

```
sudo chown osm:osm /var/run/renderd/ -R
sudo chown osm:osm /var/lib/mod_tile/ -R
```

**Creating renderd service**

First, create a config file:

```
sudo touch /etc/renderd.conf
```

_You also can download example configuration file from [my](https://github.com/dbelkovsky/bash_scipts/blob/main/data/renderd.conf) repository or configuration file wiht extended configuration from [this](https://github.com/SomeoneElseOSM/mod_tile/blob/master/etc/renderd/renderd.conf.examples) repository_

Edit renderd config file.

```
sudo vi /etc/renderd.conf
```

In the `[renderd]` section, change the number of threads according to the number of CPU cores on your server. And also change `tile_dir` to you custom tile rendering directory:

```
num_threads=2
tile_dir=/var/lib/mod_tile
```

Add a `default` layer.

```
[default]
URI=/osm/
XML=/home/osm/openstreetmap-carto/mapnik.xml
HOST=tile.your-domain.com
TILEDIR=/var/lib/mod_tile
TILESIZE=256
MAXZOOM=18
```

By default, renderd allows a max zoom level of 18. If you need zoom level 19, add the following line in the `[default]` section.

```
MAXZOOM=19
```

After all the above manipulations, you can start the renderd service manually. To do this you need to run the command:

```
renderd -f -c /etc/renderd.conf
```

where

- `-f, --foreground`: run renderd in the foreground for debugging purposes.
- `-c, --config`: set the location of the config file used to configure the various parameters of renderd, like the mapnik style sheet. The default is /etc/renderd.conf

Afer start you can see next output in CLI:

```
renderd[5163]: Parsing section renderd
renderd[5163]: Parsing render section 0
renderd[5163]: Parsing section mapnik
renderd[5163]: Parsing section default
renderd[5163]: config renderd: unix socketname=/var/run/renderd/renderd.sock
renderd[5163]: config renderd: num_threads=4
renderd[5163]: config renderd: num_slaves=0
renderd[5163]: config renderd: tile_dir=/var/lib/mod_tile
renderd[5163]: config renderd: stats_file=/var/run/renderd/renderd.stats
renderd[5163]: config mapnik:  plugins_dir=/usr/local/lib/mapnik/input
renderd[5163]: config mapnik:  font_dir=/usr/share/fonts/truetype/ttf-dejavu
renderd[5163]: config mapnik:  font_dir_recurse=1
renderd[5163]: config renderd(0): Active
renderd[5163]: config renderd(0): unix socketname=/var/run/renderd/renderd.sock
renderd[5163]: config renderd(0): num_threads=4
renderd[5163]: config renderd(0): tile_dir=/var/lib/mod_tile
renderd[5163]: config renderd(0): stats_file=/var/run/renderd/renderd.stats
renderd[5163]: config map 0:   name(default) file(/usr/local/share/maps/style/OSMBright/OSMBright.xml) uri(/osm_tiles/) htcp() host(localhost)
renderd[5163]: Initialising unix server socket on /var/run/renderd/renderd.sock
renderd[5163]: Created server socket 4
renderd[5163]: Renderd is using mapnik version 2.2.0
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSansCondensed.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSerifCondensed-BoldItalic.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSansMono-Oblique.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSerif-Italic.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSans-Bold.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSansCondensed-Bold.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSerifCondensed.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSerif.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSans-BoldOblique.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSerif-BoldItalic.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSerif-Bold.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSerifCondensed-Bold.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSansCondensed-Oblique.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSansMono-Bold.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSansMono.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSansCondensed-BoldOblique.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSans-ExtraLight.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSerifCondensed-Italic.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSans-Oblique.ttf
renderd[5163]: DEBUG: Loading font: /usr/share/fonts/truetype/ttf-dejavu/DejaVuSansMono-BoldOblique.ttf
Running in foreground mode...
debug: init_storage_backend: initialising file storage backend at: /var/lib/mod_tile
renderd[5163]: Loading parameterization function for
debug: init_storage_backend: initialising file storage backend at: /var/lib/mod_tile
renderd[5163]: Loading parameterization function for
debug: init_storage_backend: initialising file storage backend at: /var/lib/mod_tile
renderd[5163]: Loading parameterization function for
debug: init_storage_backend: initialising file storage backend at: /var/lib/mod_tile
renderd[5163]: Loading parameterization function for
renderd[5163]: Starting stats thread
renderd[5163]: Using web mercator projection settings
renderd[5163]: Using web mercator projection settingsrenderd[5163]: Using web mercator projection settings
```

**Now create a renderd systemd service**

After building from sources and mod_tile and rendering, the necessary files for configuring the systemd service will appear in the `home/osm/mod_tile/debian` directory.

Edit `/home/osm/mod_tile/debian/renderd.init` file so that “RUNASUSER” is set to the non-root account that you have used before, such as “osm” and change path to “renderd.conf“, then copy it to the system directory.

```
sed -i "s|\RUNASUSER=renderaccount|RUNASUSER=osm|g" /home/osm/mod_tile/debian/renderd.init
sed -i "s|\/usr/local/etc/renderd.conf|/etc/renderd.conf|g" /home/osm/mod_tile/debian/renderd.init
cp /home/osm/mod_tile/debian/renderd.init /etc/init.d/renderd
chmod 755 /etc/init.d/renderd
```

Copy the renderd.service to systemd derectory

```
cp /home/osm/mod_tile/debian/renderd.service /lib/systemd/system/
```

Start service renderd

```
/etc/init.d/renderd start
```

Enable renderd to autostart

```
systemctl enable renderd
```

Restart renderd to check it!

```
systemctl restart renderd
```

## Apache settings

Edit `/etc/apache2/sites-available/000-default.conf` and insert the following lines between lines `ServerAdmin` and `DocumentRoot`

```
LoadTileConfigFile /etc/renderd.conf
ModTileRenderdSocketName /var/run/renderd/renderd.sock
# Timeout before giving up for a tile to be rendered
ModTileRequestTimeout 0
# Timeout before giving up for a tile to be rendered that is otherwise missing
ModTileMissingRequestTimeout 30
```

_You also can download [000-default.conf](https://github.com/dbelkovsky/bash_scipts/blob/main/data/000-default.conf) file ftom it tepository_

After applying changes twise reload configuration and restart apache2 service

```
sudo systemctl reload apache2
sudo systemctl reload apache2
sudo systemctl restart apache2
```

### Laeflet

A tiled web map is also known as a slippy map in OpenStreetMap terminology. There are two free and open-source JavaScript map libraries you can use for your tile server: OpenLayer and `Leaflet`. The advantage of `Leaflet` is that it is simple to use and your map will be mobile-friendly. And in this guide I will use `Leaflet`.

Download and decompress Leaflet archive to apache directory

```
cd /var/www/html/
wget https://leafletjs-cdn.s3.amazonaws.com/content/leaflet/v1.9.4/leaflet.zip
unzip leaflet.zip
```

Edit index.html file

```
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

L.tileLayer('http://YOUR_SERVER_IP\/osm/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
}).addTo(map);

var hash = L.hash(map)
//]]>
</script>
</body>
</html>
```
