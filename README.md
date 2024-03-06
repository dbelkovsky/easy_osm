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

apt install -y wget software-properties-common dirmngr ca-certificates

apt-transport-https lsb-release curl
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
```

Sample output:

```
7031
```

Then check the VmPeak value of this process ID:

```
grep ^VmPeak /proc/7031/status
```

Sample output:

```
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
