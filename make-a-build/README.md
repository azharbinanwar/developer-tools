# make-a-build

The existing Flutter build/upload/email script, copied unchanged.

## Requirements

Bash, Python 3, curl, Flutter (or FVM for configured FVM projects), and a working Android build environment. macOS clipboard/editor commands are used; other platforms are not verified. qrencode is optional. Supply your own appho.st credentials. SMTP is needed only for email delivery.

## Commands and flow

    make-a-build
    make-a-build config
    make-a-build --verbose
    make-a-build --dry-run

Inside a Flutter project, the script detects it and offers to remember it. Elsewhere, select a saved project. Choose an app/account, build a fresh APK or use an existing APK, upload it, and optionally email the link. Configuration menus manage apps, accounts, recipients and SMTP settings. Logs live in logs/ next to the script.

Important: --dry-run still builds/uploads; it prints the email instead of sending it. It is not a no-upload mode.

## Fetch and run without cloning

Replace YOUR_USERNAME after publication. Run from your Flutter project:

    mkdir -p "$HOME/.local/share/developer-tools/make-a-build"
    curl -fL https://raw.githubusercontent.com/YOUR_USERNAME/developer-tools/main/make-a-build/make-a-build -o "$HOME/.local/share/developer-tools/make-a-build/make-a-build.download"
    bash -n "$HOME/.local/share/developer-tools/make-a-build/make-a-build.download" && mv "$HOME/.local/share/developer-tools/make-a-build/make-a-build.download" "$HOME/.local/share/developer-tools/make-a-build/make-a-build"
    bash "$HOME/.local/share/developer-tools/make-a-build/make-a-build"

Later runs need only the last command. Fetch again to update. To install the command on PATH:

    chmod +x "$HOME/.local/share/developer-tools/make-a-build/make-a-build"
    mkdir -p "$HOME/.local/bin"
    ln -s "$HOME/.local/share/developer-tools/make-a-build/make-a-build" "$HOME/.local/bin/make-a-build"

See the main README for PATH setup and existing-command handling.

## Settings and troubleshooting

config.json contains your own project, appho.st and SMTP settings. The script may adopt ~/.apphost. These are not distributed in this repository. Keep them private.

For build failures, read the log and check the Android build independently. For upload failures, check the selected app/account credentials and service response. For email failures, check SMTP host, port and credentials. Correct settings through make-a-build config.
