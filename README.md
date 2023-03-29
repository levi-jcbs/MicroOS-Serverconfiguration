# Serverkonfiguration

*Version b1, 25.03.2023*

[toc]

## Cluster Beschreibung

### Ziel

Das Ziel ist ein ein production fertiges zweieinhalb node Cluster, welches Requests von Extern an mehrere Applications weiterleitet.

Der ersten beiden Server sollten leistungsstark sein, auf diesen laufen die Applications. Der dritte Server dient lediglich dazu den High-Availability Status auch für das etcd Cluster zu erreichen, wozu man mindestens drei Nodes benötigt. Dieser kann auf einem leistungsschwachen PC, wie einem Raspberry Pi gehostet werden.

### Struktur

#### Cluster Network

```
                                    +----k3s-cluster-----+
               +----------+   »»»   |  Primary Server    |
Client   »»»   |  Router  |         |                    |
               +----------+  (»»»)  |  Secondary Server  |
                                    |                    |
                                    |  etcd Server       |
                                    +--------------------+
```

#### Kubernetes

```
      +---------------------------------------Primary/Secondary-Node----------------------------------------+
      |                                +--------------------------App-Namespace--------------------------+  |
»»»   |  Ingress Reverse Proxy   »»»   |  External Webserver Service   »»»   Deployment    »»»   Pod(s)  |  |
      |                                |                                                          |      |  |
      |                                |                «««         ConfigMap & Secrets         «««      |  |
      |                                |                |                                                |  |
      |                                |  Internal Database Service    »»»   StatefulSet   »»»   Pod(s)	 |  |
      |                                +-----------------------------------------------------------------+  |
      |                                                                ...                                  |
      +-----------------------------------------------------------------------------------------------------+
                                                       ...
```

#### Storage

- Eine schnelle interne M.2 Festplatte **für das System** (min. 1 TB)
- Ein RAID **für die Application Daten** (min. 2TB)

## Node Installation

Es wird **openSUSE MicroOS** mit der Systemrolle **MicroOS Container Host** installiert. Für den **etcd Node** kann die **Standard-Systemrolle** ausgewählt werden.

### Partitionierung

| Festplatte         | Partition | Filesystem | Größe     |
| ------------------ | --------- | ---------- | --------- |
| **System M.2 SSD** | /         | btrfs      | 50GB      |
| **System M.2 SSD** | /var      | btrfs      | max.      |
|                    |           |            |           |
| **Data RAID**      | /data     | btrfs      | min. 2 TB |

### Zeitzone

Zeitzone auf **Germany**, aber Hardware Clock auf **UTC** setzen.

### Network

Hostname setzen: Z.b. **firmaxyz-prod-primary** oder **firmaxyz-k8s-0**. Node muss erkennbar sein.

### Booting

In **Bootloader Options** Timeout auf 3s setzen.

### Security

Firewall aktivieren, SSH Service aktivieren und SSH port öffnen.

## Node Konfiguration

### System aktualisieren

Mit `zypper lr -u` Repos auflisten und alle USB/CD/DVD Repos mit `zypper rr` entfernen. Dieses bleibt nach der Installation manchmal übrig und es kann nicht mehr drauf zugegriffen werden, wenn das Installationsmedium entfernt wird.

System mit `transactional-update dup` aktualisieren. Danach rebooten.

### Cockpit installieren

Cockpit und optional folgende Addons installieren (`transactional-update pkg in PAKET`):

- cockpit-kdump
- cockpit-networkmanager
- cockpit-pcp
- cockpit-podman
- cockpit-storaged
- cockpit-tukit
- tuned
- tuned-profiles-atomic

Danach Rebooten.

Cockpit mit `systemctl enable --now cockpit.socket` aktivieren und zur Firewall hinzufügen:

```bash
firewall-cmd --add-service=cockpit --permanent
firewall-cmd --reload
```

Cockpit Addons sind auf **tuned** angewiesen, welches über systemd aktiviert werden muss: 

```bash
systemctl enable --now tuned.service
```
### SSH konfigurieren

SSH ist standardmäßig so konfiguriert, dass man sich per Password anmelden kann. Das sollte man für einen sicheren Server ändern. Folgende Befehle müssen ausgeführt werden:

```bash
sudo transactional-update shell
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /usr/etc/ssh/sshd_config
sed -i 's/#KbdInteractiveAuthentication yes/KbdInteractiveAuthentication no/' /usr/etc/ssh/sshd_config
exit
```

Anschließend das System neu starten.

Um sich nun über SSH einzuloggen, muss man über Cockpit den Public Key seines Rechners unter *Accounts > server* eintragen.

### Zusatzpakete installieren

Folgende Pakete sollten für einfachere Administration nachinstalliert werden:

- emacs
- tmux
- wget

### Data Partition

Auf der Data Partition (`/data`) werden alle **Application Daten** (Persistent Volumes) und **Application Konfigurationen** (yamls) gespeichert. Die PersitentVolumes im Storage Ordner werden zwischen Nodes syncronisiert, um überall verfügbar zu sein. Die App Config wird zur Vereinfachung der Administration ebenfalls zwischen Nodes syncronisiert.

#### Struktur

- **/data/**
  - **kubernetes/**
    - **resource-config/**
      - **namespaces/**
        - my-app/
          - webserver.yaml
            - *Deployment*
            - Service
            - PVC
          - database.yaml
            - *StatefulSet*
            - *Service*
            - PVC-0
            - PVC-1
    - **storage/**
      - persistent-volume-xyz/

#### Permissions

Die Permissions der Data-Partition sollten auf **750** gesetzt werden.

#### Snapshots

Snapshots für die Data-Partition aktivieren (`policycoreutils-python-utils` installieren, falls nicht vorhanden):

```bash
semanage fcontext -a -t snapperd_data_t '/data/\.snapshots(/.*)?'
snapper -c data create-config /data
restorecon -R -v /data/.snapshots/
```

Die Anzahl der Snapshots, die gemacht werden sollen, um Daten zu sichern, kann man unter `/etc/snapper/configs/` in den Konfigurationsdateien ändern.

#### Syncronisation via Syncthing

Enable Podman Socket:

```bash
systemctl enable --now podman.socket
```

Get Syncthing Image:

```bash
podman pull quay.io/oci-containers/syncthing:latest
```

Add Firewalld Rule:

```bash
firewall-cmd --permanent --add-service=syncthing
firewall-cmd --permanent --add-port=8384/tcp
firewall-cmd --reload
```

Create Syncthing Config Directory:

```bash
mkdir -p /opt/syncthing/
```

Run Syncthing:

```bash
podman run \
	--detach \
	--name=syncthing \
	--hostname=$( hostname ) \
	--userns=host \
	--network=host \
	--env PUID=0 \
	--env GID=0 \
	--env STGUIADDRESS=0.0.0.0:8384 \
	--volume /opt/syncthing:/var/syncthing:Z \
	--volume /data/kubernetes:/data0:Z \
	quay.io/oci-containers/syncthing:latest
```

Create Systemd Service and enable it:

```bash
cd /tmp
podman generate systemd --files --new --name syncthing
podman stop syncthing && podman rm syncthing
mv container-syncthing.service /etc/systemd/system/syncthing.service
systemctl daemon-reload
systemctl enable --now syncthing
```

## Kubernetes

### Installation

#### Preparation

1. Configure Firewall
	```bash
	# Primary & Secondary Server
	firewall-cmd --permanent --add-port=80/tcp
	firewall-cmd --permanent --add-port=443/tcp
	firewall-cmd --permanent --add-port=2376/tcp
	firewall-cmd --permanent --add-port=2379/tcp
	firewall-cmd --permanent --add-port=2380/tcp
	firewall-cmd --permanent --add-port=6443/tcp
	firewall-cmd --permanent --add-port=8472/udp
	firewall-cmd --permanent --add-port=9099/tcp
	firewall-cmd --permanent --add-port=10250/tcp
	firewall-cmd --permanent --add-port=10254/tcp
	firewall-cmd --permanent --add-port=30000-32767/tcp
	firewall-cmd --permanent --add-port=30000-32767/udp
	firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16 # pods network
	firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16 # services network
	firewall-cmd --reload
	
	# etcd Server
	firewall-cmd --permanent --add-port=2376/tcp
	firewall-cmd --permanent --add-port=2379/tcp
	firewall-cmd --permanent --add-port=2380/tcp
	firewall-cmd --permanent --add-port=8472/udp
	firewall-cmd --permanent --add-port=9099/tcp
	firewall-cmd --permanent --add-port=10250/tcp
	firewall-cmd --reload
	```

#### Install k3s

##### Primary Server

1. Install k3s

   ```bash
   curl -sfL https://get.k3s.io | sh -s - server --disable=traefik --cluster-init
   ```

2. Get k3s Secret Token

   ```bash
   cat /var/lib/rancher/k3s/server/node-token
   ```

##### Secondary Server

Install k3s and join cluster using **k3s Token** and **hostname** of primary server

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=<K3S-TOKEN> sh -s - server --disable=traefik --server https://<PRIMARY-SERVER-HOSTNAME>:6443
```

##### etcd Server

Install k3s etcd component to complete etcd cluster. You need the **k3s Token** and **hostname** of primary/secondary server again

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=<K3S-TOKEN> sh -s - server --disable-apiserver --disable-controller-manager --disable-scheduler --disable=traefik --server https://<PRIMARY/SECONDARY-SERVER-HOSTNAME>:6443
```

#### Helm Package Manager

### Local Provisioner

#### Entrypoint Ingress (Caddy)

### Deploy Example

#### Webserver

##### Deployment

##### Persistent Volume

##### Service

#### Database

##### StatefulSet

##### Persistent Volumes

##### Service

#### Ingress Configuration