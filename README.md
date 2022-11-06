# Serverkonfiguration

*Version a1, 06.11.2022*

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

### Booting

In **Bootloader Options** Timeout auf 3s setzen.

### Security

Firewall aktivieren, SSH Service aktivieren und SSH port öffnen.

### Network

Hostname setzen.

## Konfiguration

### System aktualisieren

System mit `transactional-update dup` aktualisieren. Danach rebooten.

### Home Snapshots

Snapshots für die Home-Partition aktivieren:

```bash
snapper -c home create-config /home
```

Die Anzahl der Snapshots, die gemacht werden sollen, um Daten zu sichern, kann man unter `/etc/snapper/configs/` in den Konfigurationsdateien ändern.

### Cockpit installieren

Cockpit und optional folgende Addons installieren (`transactional-update pkg in PAKET`):

- cockpit-kdump
- cockpit-machines
- cockpit-networkmanager
- cockpit-pcp
- cockpit-podman
- cockpit-storaged
- cockpit-tukit

Danach Rebooten.

Cockpit mit `systemctl enable --now cockpit.socket` aktivieren und zur Firewall hinzufügen:

```bash
firewall-cmd --add-service=cockpit --permanent
firewall-cmd --reload
```

Das VM Addon von Cockpit ist auf **libvirtd** angewiesen, welches über systemd aktiviert werden muss: `systemctl enable --now libvirtd.socket`

### Zusatzpakete installieren

Folgende Pakete sollten für einfachere Administration nachinstalliert werden:

- nano
- emacs
- tuned
- tuned-profiles-atomic

### Usermanagement

Es müssen die User **public** und **server** angelegt werden.

Das ist am einfachsten über Cockpit möglich. Alternativ mit `useradd -mU USERNAME` und `passwd USERNAME`. Wichtig ist, dass der User seine **eigene gleichnamige Primärgruppe** und das Homeverzeichnis die Berechtigung **700** hat.

> **Folgender Teil ist nur auf Grund einer Fehlkonfiguration von MicroOS notwendig, die bald gepatcht wird.**
>
> Als nächster Schritt muss das sudo-Verhalten verändert werden, damit man in Cockpit den administrativen Zugang aktivieren kann. Dauerhaft sollte man in Cockpit nicht als root angemeldet sein, weil die Podman Container als User **server** laufen, und man diese in der root-Oberfläche nicht angezeigt bekommt.
>
> Dafür unkommentiert man folgende Zeilen in der sudoers Datei über `visudo`:
>
> ```
> # Defaults targetpw
> # ALL ALL=(ALL:ALL) ALL
> ```

Zuguterletzt muss **User Lingering** aktiviert werden, damit User Prozesse, in diesem Fall also die Server Prozesse, sofort bei Start des Computers hochgefahren werden und nicht erst, wenn sich der User anmeldet:

```bash
loginctl enable-linger server
loginctl enable-linger public
```

### SSH

SSH ist standardmäßig so konfiguriert, dass man sich per Password anmelden kann. Das sollte man für einen sicheren Server ändern. Folgende Befehle müssen ausgeführt werden:

```bash
sudo transactional-update shell
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /usr/etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /usr/etc/ssh/sshd_config
exit
```

Anschließend das System neu starten.

Um sich nun über SSH einzuloggen, muss man über Cockpit den Public Key seines Rechners unter *Accounts > server* eintragen.

## Userrolle: server (Applications)

Zuerst muss man den User-Service von podman aktivieren:

```bash
systemctl --user enable --now podman.socket
```

### Bennenung von Apps

Alle Applications werden mit einer führenden Null durchnummeriert und tragen den diese ID von der Bezeichnung mit Unterstrichen getrennt im Namen. Zum Beispiel **04_mein_erste_testapp**.

### Verzeichnisstruktur

| Verzeichnis    | Beschreibung                                                 |
| -------------- | ------------------------------------------------------------ |
| ~/apps/        | Hier liegen die Applicationdaten in nach **xx_name** benannten Unterordnern. |
| ~/systemd/     | Hier liegen die Unitdateien von allen Applications (pods) und dazugehörigen containern in nach **xx_name** benannten Unterordnern. |
| /var/log/apps/ | Hier liegen Logdateien von Applications in nach **xx_name** benannten Unterordnern. |
| ~/imports/     | Hier legen Administratoren ihre Imagedateien ab, um sie zu importieren. |

### Portvergabe

Apps dürfen die Ports **80xx** für HTTP und **22xx** für SSH nutzen. **xx** steht dabei für die ID der Application.

### Application einrichten

Jede Application hat in Podman einen Pod. Ein Pod ist eine Gruppe von Containern (Komponenten der Application). Alle Container in dem Pod der Application teilen das selbe Netzwerk, localhost und Portfreigaben.

## Userrolle: public (Reverse Proxy / Gateway Server)

Kommt.
