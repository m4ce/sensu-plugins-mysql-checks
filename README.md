# Sensu plugin for monitoring MySQL

A sensu plugin to monitor MySQL, including slave replication.

The plugin generates multiple OK/WARN/CRIT/UNKNOWN events via the sensu client socket (https://sensuapp.org/docs/latest/clients#client-socket-input).

What is currently supported:

* Active connections check
* Max used connections check
* Slave IO/SQL threads running checks
* Slave replication lag check
* Uptime check
* Operational check (up/down)

## Usage

The plugin accepts the following command line options:

```
    -c, --config <PATH>              Optional configuration file (default: ./mysql.json)
        --crit-conn <PERCENTAGE>     Critical if PERCENTAGE exceeds the current number of open connections in relation to max connections (default: 90)
        --crit-slave-lag <SECONDS>   Critical if SECONDS exceeds the current slave replication lag (default: 120)
        --dryrun                     Do not send events to sensu client socket
        --handlers <HANDLER>         Comma separated list of handlers
    -H, --host <HOST>                MySQL host (default: localhost)
        --password <PASSWORD>        MySQL password
    -p, --port <PORT>                MySQL port (default: 3306)
        --uptime <UPTIME>            Uptime in seconds
    -u, --user <USER>                MySQL user
        --warn-conn <PERCENTAGE>     Warn if PERCENTAGE exceeds the current number of open connections in relation to max connections (default: 80)
        --warn-slave-lag <SECONDS>   Warn if SECONDS exceeds the current slave replication lag (default: 60)
```

For security reasons, it's recommended you placed the MySQL credentials in the JSON configuration file as follows:

```
{
  "username": "sensu",
  "password": "secret"
}
```

## Author
Matteo Cerutti - <matteo.cerutti@hotmail.co.uk>
