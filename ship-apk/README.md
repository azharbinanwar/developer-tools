# ship-apk

Build a Flutter APK, upload it to appho.st, mail the download link to your testers. One command, walk away.

## Run it

Inside your Flutter project:

```sh
ship-apk
```

Or without installing:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/ship-apk/ship-apk)
```

Install options, and the `developer-tools` hub that runs every tool from one menu, are in the [main README](../README.md#2-install-it).

## What happens

1. **Apps first.** It opens on your saved apps. Inside an app's folder that app is preselected. Inside a Flutter folder nobody saved yet, "+ add this app" is preselected with the folder filled in; adding asks for the app name, the appho.st app id, `user_id` and API key (all from the app's page on appho.st › Private API › download config).
   ```
   ▸ Apps
    ❯ Reg Register          Nh8IpVYIVA   2 people     ● this folder
      Studio Desk           Ab3kQ9xLmP   no mail      ~/Desktop/mine/studiodesk
      + add app
      edit an app
      mailbox
      quit
   ```
2. **Build**: a fresh `flutter build apk --release` (or `fvm flutter` when the project pins it), or the last build.
3. **Email**, settled before anything runs, naming exactly what is missing:
   - no mailbox yet → **set up mailbox**: address, password, SMTP host and port prefilled for Gmail, Outlook, iCloud, Yahoo and Zoho, sender name, then an optional test mail
   - mailbox ready, nobody to send to → **set up this app's email**: To, CC, BCC and subject, one question at a time
   - both ready → **send the link to N people**, skip, or change To, CC, BCC or subject
4. **Build, upload, mail** run unattended. The link is copied and shown as a QR code if `qrencode` is installed.
5. **Done**: open the APK folder (first when no mail went out), open the link, back to apps, or quit.

## Commands

```
ship-apk             your apps; pick one, it builds, uploads and mails the link
ship-apk --dry-run   same, but print the mail instead of sending it (it still builds and uploads)
ship-apk --verbose   stream the full build log instead of one line
ship-apk config      mailbox and template
ship-apk -v          version
```

## Email

The **mailbox** is the account mail is sent from, shared by every app. Each app has its own **To**, **CC**, **BCC** and **subject** under **edit an app**. Passwords show one `*` per character, and Enter keeps a saved one.

The subject and body are plain text in `config.json` (mailbox › edit the mail template) with these placeholders: `{name}` `{app}` `{version}` `{link}` `{notes}` `{sender}`. `{notes}` is the git log since the last send, so the mail says what changed.

## Needs

macOS, python3 and curl (built in), plus `flutter` or `fvm`. Projects pinned with fvm use it automatically. `qrencode` is optional.

## Where things live

| What | Where |
| --- | --- |
| Projects, credentials, SMTP, template | `~/.config/ship-apk/config.json` (mode 0600) |
| Build and send logs | `~/.config/ship-apk/logs/` |

Nothing is written into your project. The free appho.st tier rejects APKs over 100 MB; you are warned before the upload.
