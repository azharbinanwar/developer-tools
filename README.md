# Developer Tools

Two existing terminal tools, preserved unchanged:

| Command | Purpose |
| --- | --- |
| [make-a-build](make-a-build/README.md) | Flutter APK builds, appho.st uploads and optional email |
| [deploy-it](deploy-it/README.md) | React + Vite builds and Vercel publishing |

No GitHub Actions, extra app or new tool. macOS is the current reference platform.

## Local installation

Requires Bash and Python 3, plus the requirements in each tool guide. Replace YOUR_USERNAME once the repository is published.

    git clone https://github.com/YOUR_USERNAME/developer-tools.git "$HOME/developer-tools"
    mkdir -p "$HOME/.local/bin"
    ln -s "$HOME/developer-tools/make-a-build/make-a-build" "$HOME/.local/bin/make-a-build"
    ln -s "$HOME/developer-tools/deploy-it/deploy-it" "$HOME/.local/bin/deploy-it"

Install only the desired tool by creating only its symlink. Existing commands are not overwritten: if one exists, keep it or deliberately remove its symlink before linking the new installation.

For deploy-it, install Node.js/npm and the Vercel CLI:

    npm install --prefix "$HOME/developer-tools/deploy-it/runtime" --save-exact vercel@62.4.0

Add this to ~/.zshrc or your shell startup file, then start a new terminal:

    export PATH="$HOME/.local/bin:$PATH"

## Direct execution from GitHub

See each tool guide for fetch-and-run commands without cloning. GitHub hosts the code; execution happens locally. Downloading files is still necessary. Persistent local folders retain settings between runs.

Download first, then launch normally so menus can read your terminal. Piping source into Bash can interfere with interactive input; deploy-it also requires its supporting Python files. Review code before execution. For reproducibility, replace main with a reviewed commit or tag.

## Personal data

No user credentials, configuration, history or logs are included. Users enter their own values through the existing menus.

The unchanged scripts save data next to their installed files:

- make-a-build: config.json and logs/; may adopt an existing ~/.apphost.
- deploy-it: config.json, accounts/, history.jsonl and logs/.

These paths and runtime dependencies are ignored by Git. Keep the installation private and never force-add ignored files. Credentials are plaintext locally, not encrypted. deploy-it protects token files with mode 0600 and account directories with 0700. Do not expose config files or logs publicly.

Your existing installed commands and account files remain in their original folders. This repository does not migrate settings automatically. Copy personal settings only into your own private installation if you choose to migrate later.

## Update and uninstall

For a clone:

    git -C "$HOME/developer-tools" pull --ff-only

For direct downloads, repeat the fetch step. Settings are retained. Review changes before running updated code.

Remove only the symlinks you created to uninstall:

    rm "$HOME/.local/bin/make-a-build" "$HOME/.local/bin/deploy-it"

Keep the installation folder to retain settings. Delete it separately only if you want to erase local credentials and logs too.

## Validation and contributions

    bash -n make-a-build/make-a-build
    bash -n deploy-it/deploy-it
    cd deploy-it
    python3 -m unittest discover -s tests -v

Keep contributions focused on these tools; exclude all personal and generated files.

## Publication

GitHub owner and URL are not selected yet; commands intentionally contain placeholders. Choose a license before inviting external reuse. No license has been assumed. Publication is a separate step.
