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

1. **First run in a project**: it offers to remember the folder and asks for the app name, the appho.st app id, `user_id` and API key. All three come from the app's page on appho.st › Private API › download config.
2. **Every run**: pick build fresh or reuse the last APK, choose whether to send the email, then everything else runs unattended.
3. **Done**: the link is copied to your clipboard, printed as a QR code if `qrencode` is installed, and mailed if you asked.

Run it outside any project and it lists your saved apps to pick from.

## Commands

```
ship-apk             build, upload, and optionally mail the link
ship-apk --dry-run   same, but print the mail instead of sending it
ship-apk --verbose   stream the full build log instead of one line
ship-apk config      mail account and config file
ship-apk --version
```

## Email

Each app has a **To** list and an optional hidden **BCC** list, edited from the app screen. The mail account (SMTP host, port, address, password, from name) is shared by all apps and set up under `ship-apk config`, which also has a "send a test to myself".

The subject and body are plain text in `config.json` with these placeholders: `{name}` `{app}` `{version}` `{link}` `{notes}` `{sender}`. `{notes}` is the git log since the last send, so the mail says what changed.

## Needs

macOS, python3 and curl (built in), plus `flutter` or `fvm`. Projects pinned with fvm use it automatically. `qrencode` is optional.

## Where things live

| What | Where |
| --- | --- |
| Projects, credentials, SMTP, template | `~/.config/ship-apk/config.json` (mode 0600) |
| Build and send logs | `~/.config/ship-apk/logs/` |

Nothing is written into your project. The free appho.st tier rejects APKs over 100 MB; you are warned before the upload.
