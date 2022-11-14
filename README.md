# Serverkonfiguration

*Version a1, 14.11.2022*

[toc]

## Installation

Es wird **openSUSE MicroOS** mit der Systemrolle **MicroOS Container Host** installiert.

### Partitionierung

| Partition | Filesystem | Größe |
| --------- | ---------- | ----- |
| /         | btrfs      | 50GB  |
| /var      | btrfs      | 50GB  |
| /home     | btrfs      | max.  |

### Zeitzone

Zeitzone auf **Germany**, aber Hardware Clock auf **UTC** setzen.

### Network

Hostname setzen.

### Booting

In **Bootloader Options** Timeout auf 3s setzen.

### Security

Firewall aktivieren, SSH Service aktivieren und SSH port öffnen.

## Konfiguration

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

Cockpit Addons sind auf **libvirtd** und **tuned** angewiesen, welche über systemd aktiviert werden müssen: 

```bash
systemctl enable --now libvirtd.socket
systemctl enable --now tuned.service
```

### Zusatzpakete installieren

Folgende Pakete sollten für einfachere Administration nachinstalliert werden:

- nano
- emacs
- tmux
- wget

### rebootmgr: Zeitfenster zum Neustart

openSUSE stellt ein Programm namens **rebootmgr** bereit, in dem man einstellen, kann wann das System automatisiert neustarten darf, um z.B. Updates anzuwenden. In der Standardkonfiguration liegt dieses Zeitfenster bei **03:30:00 für 1h30min**. Dies kann man ändern mit dem Befehl `rebootmgrctl`.

Damit sich der PC strikt an das Zeitfenster hält (was für Server durchaus wichtig ist), muss die "Strategie" von rebootmgr auf **maint-window** gestellt werden:

```bash
sudo rebootmgrctl set-strategy maint-window
```

Für gewöhnlich arbeite ich mit einem Maintenance Window von **03:00:00 Uhr für 1 Stunde**. Bei dem Bettieb High Avaibility Applications muss in dieser Zeit ein Backupserver laufen.

```bash
sudo rebootmgrctl set-window 03:00:00 1h
```

### Home Snapshots

> Folgende Schritte sind auf Grund eines SELinux Konfigurationsfehlers (der hoffentlich bald gepatcht wird) nötig:
>
> ```bash
> semanage fcontext -a -t snapperd_data_t '/home/\.snapshots(/.*)?'
> mkdir /home/.snapshots/
> restorecon -R -v /home/.snapshots/
> ```

Snapshots für die Home-Partition aktivieren:

```bash
snapper -c home create-config /home
```

Die Anzahl der Snapshots, die gemacht werden sollen, um Daten zu sichern, kann man unter `/etc/snapper/configs/` in den Konfigurationsdateien ändern.

### Usermanagement

Es müssen die User **public** und **server** angelegt werden.

Das ist am einfachsten über Cockpit möglich. Alternativ mit `useradd -mU USERNAME` und `passwd USERNAME`. Wichtig ist, dass der User seine **eigene gleichnamige Primärgruppe** und das Homeverzeichnis die Berechtigung **700** hat.

Zuguterletzt muss **User Lingering** aktiviert werden, damit User Prozesse, in diesem Fall also die Server Prozesse, sofort bei Start des Computers hochgefahren werden und nicht erst, wenn sich der User anmeldet:

```bash
loginctl enable-linger server public
```

### SSH

SSH ist standardmäßig so konfiguriert, dass man sich per Password anmelden kann. Das sollte man für einen sicheren Server ändern. Folgende Befehle müssen ausgeführt werden:

```bash
sudo transactional-update shell
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /usr/etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /usr/etc/ssh/sshd_config
exit
```

Anschließend das System neu starten.

Um sich nun über SSH einzuloggen, muss man über Cockpit den Public Key seines Rechners unter *Accounts > server* eintragen.

## Userrolle: server (Applications)

### Installation

Zuerst muss man den User-Service von podman aktivieren:

```bash
systemctl --user enable --now podman.socket
```

Und dann das Script `podman-systemd-apply` von Github in den `~/bin/` Ordner herunterladen und mit `chmod u+x ~/bin/podman-systemd-apply` ausführbar machen:

```bash
wget -O ~/bin/podman-systemd-apply https://raw.githubusercontent.com/levi-jcbs/MicroOS-Serverkonfiguration/main/scripts/podman-systemd-apply
```

### Bennenung von Apps

Alle Applications werden mit einer führenden Null durchnummeriert und tragen den diese ID von der Bezeichnung mit Unterstrichen getrennt im Namen. Zum Beispiel **04_mein_erste_testapp**. Die Namen werden auf Verzeichnisse und Pods angewandt.

### Verzeichnisstruktur

| Verzeichnis    | Beschreibung                                                 |
| -------------- | ------------------------------------------------------------ |
| ~/apps/        | Hier liegen die Applicationdaten in nach **xx_name** benannten Unterordnern. |
| ~/systemd/     | Hier liegen die Unitdateien von allen Applications (pods) und dazugehörigen containern in nach **xx_name** benannten Unterordnern. |
| /var/log/apps/ | Hier liegen Logdateien von Applications in nach **xx_name** benannten Unterordnern. |
| ~/imports/     | Hier legen Administratoren ihre Imagedateien ab, um sie zu importieren. |

### Portvergabe

Apps dürfen die Ports **80xx** für HTTP und **22xx** für SSH nutzen. **xx** steht dabei für die ID der Application.

Diese Ports müssen natürlich in der Firewall  erlaubt werden. Das geht über Cockpit *Network > Firewall > Edit rules and zones*. Alternativ über die Kommandozeile:

```bash
firewall-cmd --add-port=8001-8099/tcp --permanent
firewall-cmd --add-port=2201-2299/tcp --permanent
firewall-cmd --reload
```

### Application einrichten

Jede Application hat in Podman einen Pod. Ein Pod ist eine Gruppe von Containern (Komponenten der Application). Alle Container in dem Pod der Application teilen das selbe Netzwerk, localhost und Portfreigaben.

Um eine Application einzurichten, muss man also

- Einen Pod erstellen (Auf Namen achten)
- Container Image(s) importieren oder pullen
- Zu Pod zugehörige(n) Containe erstellen

#### Pod erstellen

Beim Erstellen eines Pods sollten die öffentlichen Ports angegeben werden, da dies sowieso auf alle Container angewandt wird. Grundlegende Podkonfiguration:

```bash
podman pod create --replace --userns= --publish 80xx:80 xx_name
```

#### Container erstellen

Beim Erstellen von Containern werden dann Container-spezifisch **Storage Mounts**, **Env-Variablen** etc. angegeben. Grundlegende Containerkonfiguration:

```bash
podman run --replace --detach --pod [new:]xx_name --volume ~/apps/xx_name/:/app/:Z --name xx_image image
```

Wenn die Application nur aus einem Container besteht, kann auf die Erstellung von Pods verzichtet werden, und beim erstellen des Containers mit `--pod new:xx_name` der Pod direkt miterstellt werden.

Vor dem Namen des Containers sollte die ID stehen, damit es bei gleichen Komponenten in mehreren Applications keine Namensduplikate gibt. Beispielsweise werden oft viele mariadb Container genutzt, für alle Möglichen Applications. Es können nicht alle **mariadb** heißen, deswegen nennt man sie einfach **xx_mariadb**. 

#### Production

Für gewöhnlich werden Applications in Production nicht auf dem Server manuell (über oben genannte Befehle) erstellt, sondern von Admins auf einem Testcomputer.

Um die Applications dann vom Testcomputer auf den Production Server zu migrieren, werden dann die **systemd Unit Dateien der App** kopiert. Wie diese erstellt werden, wird im folgenden Abschnitt erklärt:

### Applications verwalten

Um das automatisierte Starten und einfache administrieren zu gewährleisten, werden alle Applications in Systemd Units gesteckt. Diese liegen in eigenen Ordner (für jede Application) in `~/systemd/`. Jede Application hat eine Unit-Datei für den Pod und eine oder mehrere für dazugehörige Container. All diese können von einem laufendem Pod einfach mit `podman generate systemd --files --new --name --restart-policy=no xx_name` generiert werden (Aufpassen, dass der Befehl im zu dem Pod gehörigen Ordner ausgeführt wird!).

Um seine Systemd-Konfiguration anzuwenden, führt man einfach `podman-systemd-apply` aus. Dieses Script stoppt alle Pods, kopiert die neue Konfiguration zu Systemd und wendet sie an und startet alles wieder. Es geht Blitzschnell.

### Application Extensions

Einige wenige Applications benötigen Services, die außerhalb von Containern laufen und beispielsweise Befehle in Containern ausführen oder als Timer Container in bestimmten Abständen starten. Diese Unit Dateien nenne ich Extensions, weil sie an sich kein Container und kein Pod sind, aber bei `podman-systemd-apply` trotzdem so behandelt werden. Sie müssen mit **extension-** beginnen. Beispielsweise **extension-01_nextcloud_cron.timer**.

Damit Extensions beim Start des der Application (des Pods) mitstarten, müssen sie in der Unitdatei des Pods unter **Requires=** und **Before=** eingetragen werden.

## Userrolle: public (Reverse Proxy / Gateway Server)

Kommt.

## Userrolle: root (Datensicherheit)

Kommt.

# Beispiele

## systemd

Die Systemd Beispiele für Applications müssen auf Namen und weitere Optionen angepasst werden. Dazu die Dateien aus dem Beispielordner der entsprechenden App in den finalen **~/systemd/XX_APP/** Ordner kopieren und **apply.sh** ausführen.

Beachte, dass der Name der Application natürlich keine Leerzeichen enthalten darf. Auch Großbuchstaben sind unpraktisch.

### Nextcloud

Für Nextcloud werden folgende Images benötigt: **nextcloud**, **mariadb**. Im **apps**-Verzeichnis werden folgende App-Unterordner benötigt: **app**, **data**, **mariadb**.

