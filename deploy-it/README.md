# deploy-it

A standalone terminal manager for static React + Vite websites on Vercel. No Python packages are required. It uses Python 3, Node.js, your project's package manager, and the Vercel CLI.

## Commands

```sh
deploy-it                    # detect this project, or open the project menu
deploy-it projects           # saved folders and remote Vercel projects
deploy-it accounts           # named logins/tokens and account/team selection
deploy-it --dry-run          # local validation; remote access checks when configured
deploy-it --dry-run --build  # also compile locally; no upload
deploy-it --production       # explicitly select the stable production URL
deploy-it --preview
deploy-it --path ~/my-site --account personal
deploy-it --output public-build --build-command 'npm run build'
```

Menus support arrow keys, Enter and q. Numbered menus are used for piped input. EOF never confirms an action.

## Accounts

Each named account has its own Vercel global configuration under `accounts/<label>/`. Browser sign-in is recommended. Alternatively enter a token at the hidden prompt. Tokens are stored with mode 0600; account directories use 0700. The normal Vercel login configuration is not overwritten. Never commit `accounts/` or `config.json`.

Pick a team scope for each account; the same login can have separate named profiles for different teams. Projects remember their account. Credentials supplied to the Vercel CLI use its supported token flag; the tool never prints or records the token, but local process arguments can be visible to other processes running as your user.

## Deployment

1. Validate the local React + Vite folder, build command and output.
2. Confirm deployment, select an account and an accessible Vercel project (or create one).
3. Choose Main website (production, first/default) or Test version (a new preview URL). Selection starts building and publishing directly.
4. Build locally. The tool uploads **only the static build output**, using temporary staging and the selected project's IDs. It does not upload source code, node_modules or the project's local environment files.
5. Show the main website URL (or test URL), copy it, and offer Open website in browser, Deploy another project, Manage existing projects or Exit. The production build URL is dimmed.

Production updates all production domains for that project. Picking a share URL does not reassign a domain. Unique version URLs are immutable; stable production URLs follow production updates. Custom domains are optional.

`dist` is the default output. Override it if your Vite configuration uses a different directory. Existing `vercel.json` redirects, headers and rewrites are retained, with build settings overridden for static output. A default SPA rewrite is supplied when none exists. Projects with server functions or legacy Vercel builds are rejected rather than silently deployed incorrectly.

Local Vite builds use your normal local environment. This tool does not pull remote environment variables automatically. Dependencies should already be installed; missing dependencies are reported by the build. A failed build never uploads.

## Dry run

`--dry-run` does not create projects, link directories, upload, change production, delete, pause, log or save configuration. It may make authenticated GET requests to validate account/project access. Account setup must be done outside dry run. Without configured credentials, it reports remote validation as unavailable. `--build` is an explicit opt-in to local build-output changes.

## Management

Fetch projects with pagination, find accessible projects by plain deployment/domain URL, list their domains and deployments, pause/resume, delete selected versions or projects, and request production rollback. API operations use the current CLI session (`vercel api`, currently beta) or a configured access token.

Cleanup only considers previews older than 30 days outside the newest five deployments. Production, aliased and non-terminal deployments are excluded, and targets are rechecked immediately before deletion. The exact selection is shown and requires a typed confirmation. Remote concurrent changes remain possible; use manual deletion if someone is simultaneously promoting deployments.

History is capped at 200 events. Deployment lists are fetched remotely rather than cached. Temporary upload files are removed automatically. Local source folders are never deleted.

Vercel Hobby is for personal, non-commercial projects. Platform permissions and plan restrictions still apply; the tool cannot bypass them. On Hobby, rollback is limited to the previous production deployment.

## Installation / development

A pinned Vercel CLI is installed under `runtime/`; a global CLI on PATH takes priority. To update the bundled version explicitly:

```sh
npm install --prefix runtime --save-exact vercel@latest
```

Run offline tests with `python3 -m unittest discover -s tests -v`.


## Fetch and run without cloning

The launcher needs main.py and deploy_it/. Fetch the repository archive, then copy only this tool into a persistent local folder. Replace YOUR_USERNAME after publication:

    (
      set -eu
      fetch_dir="$(mktemp -d)"
      trap 'rm -rf "$fetch_dir"' EXIT
      curl -fL https://github.com/YOUR_USERNAME/developer-tools/archive/refs/heads/main.tar.gz -o "$fetch_dir/source.tar.gz"
      tar -xzf "$fetch_dir/source.tar.gz" -C "$fetch_dir"
      mkdir -p "$HOME/.local/share/developer-tools/deploy-it/deploy_it"
      cp "$fetch_dir/developer-tools-main/deploy-it/deploy-it" "$fetch_dir/developer-tools-main/deploy-it/main.py" "$HOME/.local/share/developer-tools/deploy-it/"
      cp -R "$fetch_dir/developer-tools-main/deploy-it/deploy_it/." "$HOME/.local/share/developer-tools/deploy-it/deploy_it/"
      npm install --prefix "$HOME/.local/share/developer-tools/deploy-it/runtime" --save-exact vercel@62.4.0
    )
    bash "$HOME/.local/share/developer-tools/deploy-it/deploy-it"

Run from your React + Vite folder. Later runs need only the last command. Node.js/npm is required; no third-party Python packages are needed. Settings persist locally. To install the command on PATH:

    chmod +x "$HOME/.local/share/developer-tools/deploy-it/deploy-it"
    mkdir -p "$HOME/.local/bin"
    ln -s "$HOME/.local/share/developer-tools/deploy-it/deploy-it" "$HOME/.local/bin/deploy-it"

See the main README for PATH setup.

## Troubleshooting

Missing CLI: install Vercel as above. Account failures: run deploy-it accounts and correct the token or scope. Build failures: check project dependencies and the displayed build log. Dry-run remote validation requires a configured account. Main website publishing updates all production domains attached to the chosen project. Build logs contain project output; avoid printing secrets in build scripts.
