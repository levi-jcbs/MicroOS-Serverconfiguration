# Serverkonfiguration

*Version b1, 25.03.2023*

[toc]

## Cluster Beschreibung

### Ziel

Das Ziel ist ein ein production fertiges zweieinhalb node Cluster, welches Requests von Extern an mehrere Applications weiterleitet.

Der ersten beiden Server sollten leistungsstark sein, auf diesen laufen die Applications. Der dritte Server dient lediglich dazu den High-Availability Status auch für das etcd Cluster zu erreichen, wozu man mindestens drei Nodes benötigt. Dieser kann auf einem leistungsschwachen PC, wie einem Raspberry Pi gehostet werden.

### Struktur

#### Server

```
                                    +----k3s-cluster-----+
               +----------+   »»»   |  Primary Server    |
Client   »»»   |  Router  |         |                    |
               +----------+  (»»»)  |  Secondary Server  |
                                    |                    |
                                    |  etcd Server       |
                                    +--------------------+
```

#### Inside Cluster

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

## Node Installation

Es wird **openSUSE MicroOS** mit der Systemrolle **MicroOS Container Host** installiert. Für den **etcd Node** kann die **Standard-Systemrolle** ausgewählt werden.

### Partitionierung

| Partition | Filesystem | Größe     |
| --------- | ---------- | --------- |
| /         | btrfs      | min. 50GB |
| /var      | btrfs      | min. 50GB |
| /home     | btrfs      | max.      |

### Zeitzone

Zeitzone auf **Germany**, aber Hardware Clock auf **UTC** setzen.

### Network

Hostname setzen: Z.b. **firmaxyz-prod-primary** oder **firmaxyz-k8s-0**. Node muss erkennbar sein.

### Booting

In **Bootloader Options** Timeout auf 3s setzen.

### Security

Firewall aktivieren, SSH Service aktivieren und SSH port öffnen.

## Node Konfiguration

### (Ggf.) Installationsrepo löschen

Mit `zypper lr -u` Repos auflisten und alle USB/CD/DVD Repos mit `zypper rr` entfernen. Dieses bleibt nach der Installation manchmal übrig und es kann nicht mehr drauf zugegriffen werden, wenn das Installationsmedium entfernt wird.

### System aktualisieren

System mit `transactional-update dup` aktualisieren. Danach rebooten.

### Cockpit installieren

Cockpit und optional folgende Addons installieren (`transactional-update pkg in PAKET`):

- cockpit-kdump
- cockpit-machines
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

### Zusatzpakete installieren

Folgende Pakete sollten für einfachere Administration nachinstalliert werden:

- emacs
- tmux
- wget

### Home Snapshots

> Folgende Schritte sind auf Grund eines SELinux Konfigurationsfehlers (der hoffentlich bald gepatcht wird) nötig:
>
> ```bash
> semanage fcontext -a -t snapperd_data_t '/home/\.snapshots(/.*)?'
> snapper -c home create-config /home
> restorecon -R -v /home/.snapshots/
> ```

Snapshots für die Home-Partition aktivieren:

```bash
snapper -c home create-config /home
```

Die Anzahl der Snapshots, die gemacht werden sollen, um Daten zu sichern, kann man unter `/etc/snapper/configs/` in den Konfigurationsdateien ändern.

### Usermanagement

Es muss der User **server** angelegt werden.

Das ist am einfachsten über Cockpit möglich. Alternativ mit `useradd -mU USERNAME` und `passwd USERNAME`. Wichtig ist, dass der User seine **eigene gleichnamige Primärgruppe** und das Homeverzeichnis die Berechtigung **700** hat.

Zuguterletzt muss **User Lingering** aktiviert werden, damit User Prozesse sofort bei Start des Computers hochgefahren werden und nicht erst, wenn sich der User anmeldet:

```bash
loginctl enable-linger server
```

### SSH

SSH ist standardmäßig so konfiguriert, dass man sich per Password anmelden kann. Das sollte man für einen sicheren Server ändern. Folgende Befehle müssen ausgeführt werden:

```bash
sudo transactional-update shell
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /usr/etc/ssh/sshd_config
sed -i 's/#KbdInteractiveAuthentication yes/KbdInteractiveAuthentication no/' /usr/etc/ssh/sshd_config
exit
```

Anschließend das System neu starten.

Um sich nun über SSH einzuloggen, muss man über Cockpit den Public Key seines Rechners unter *Accounts > server* eintragen.

## Kubernetes (k3s)

### Installation

