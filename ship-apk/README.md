# ship-apk

Build a Flutter APK, upload it to appho.st, mail the download link to your testers. One command, then walk away.

## Run it

Inside your Flutter project:

```sh
ship-apk
```

Or without installing:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/ship-apk/ship-apk)
```

Install options, and the `developer-tools` hub, are in the [main README](../README.md#2-install-it).

## Commands

```
ship-apk              your apps; pick one, it builds, uploads and mails the link
ship-apk --dry-run    check everything and show what would happen; changes nothing (also -n)
ship-apk --verbose    stream the full build log instead of one line
ship-apk config       mailbox and mail template
ship-apk -v           version
```

## What happens

### 1. Apps

```
▸ Apps
 ❯ Thoub                   E4FW48PjtX   1 person     ● this folder
   Reg Register            Nh8IpVYIVA   no mail      ~/Desktop/mine/rig_register
   + add app
   edit an app
   mailbox
   quit
```

Inside an app's folder, that app is preselected. Inside a Flutter folder nobody saved yet, **+ add this app** is preselected with the folder filled in. Adding asks for the app name, the appho.st app id, `user_id` and API key, all from the app's page on appho.st › Private API › download config.

### 2. Version

```
▸ Version  1.0.0+4
 ❯ ship as 1.0.0+4
   bump                next build is 1.0.0+5, or type your own
```

Enter ships as is. **bump** asks `New version [1.0.0+5] ›`: Enter takes the next build, or type any version like `1.1.0+6`. A bad version asks again. Only the `version:` line in `pubspec.yaml` changes, and a fresh build is forced.

If this exact version was shipped last time, the header says **shipped last time** and **bump** is preselected. You still choose.

### 3. Build

A fresh `flutter build apk --release`, or the last build. Projects with `.fvmrc` or `.fvm/` build with `fvm flutter`.

### 4. Email

Settled before anything runs, and it names exactly what is missing:

| State | You see |
| --- | --- |
| no mailbox yet | **set up mailbox** or skip |
| mailbox ready, nobody to send to | **set up this app's email** or skip |
| both ready | **send the link to 1 person + 1 CC**, skip, or change To, CC, BCC or subject |

**set up mailbox** asks one thing at a time: address, password, SMTP host and port (prefilled for Gmail, Outlook, iCloud, Yahoo and Zoho), the name people see, then offers a test mail. Gmail needs an [app password](https://myaccount.google.com/apppasswords).

**set up this app's email** asks To, then CC, then BCC (blank skips), then the subject.

### 5. Notes

When mail is going out, the commit titles since the last send are shown, then:

- **use these**
- **write my own**: opens your editor (or TextEdit) prefilled with them. Save, then press Enter in the terminal. Markdown is fine; lines starting with `#` are dropped, and bullets pasted from TextEdit are tidied into `-` lists.
- **no notes**

### 6. Build, upload, mail

These run with no more questions. The link is copied and shown as a QR code if `qrencode` is installed. If the upload drops (network), you get **retry the upload** with the same APK, no rebuild.

### 7. Done

**open the APK folder** (first when no mail went out), **open the link**, **back to apps**, or **quit**.

## Dry run

`ship-apk --dry-run` (or `-n`) walks the whole flow, checks everything, and changes nothing.

| Step | In a dry run |
| --- | --- |
| apps, menus, add or edit an app | ✅ runs |
| version | ⏭ shows the new version, does not write `pubspec.yaml` |
| notes | ✅ runs |
| flutter or fvm installed | ✅ checked |
| appho.st app id and keys set | ✅ checked |
| mailbox login | ✅ checked (logs in and out, sends nothing) |
| build | ⏭ shows the command |
| upload | ⏭ shows the target app and version |
| mail | ⏭ shows the mail exactly as it would go out |
| "last shipped" record, logs | ⏭ not saved |

It ends with **dry run passed** or a list of ✗ problems to fix.

## Editing later

- **edit an app**: To, CC, BCC, subject, app name, app id, folder, appho.st credentials, remove.
- **mailbox**: the sending account, a test mail, and the mail template.

Passwords show one `*` per character; Enter keeps a saved one.

The mail template is plain text in `config.json` (mailbox › edit the mail template) with `{name}` `{app}` `{version}` `{link}` `{notes}` `{sender}`.

## Needs

macOS, python3 and curl (built in), plus `flutter` or `fvm`. `qrencode` is optional.

## Where things live

| What | Where |
| --- | --- |
| Apps, credentials, mailbox, template, last shipped version | `~/.config/ship-apk/config.json` (mode 0600) |
| Build and send logs | `~/.config/ship-apk/logs/` |

The only file it ever changes in your project is the `version:` line of `pubspec.yaml`, and only when you pick **bump**. The free appho.st tier rejects APKs over 100 MB; you are warned before the upload.
