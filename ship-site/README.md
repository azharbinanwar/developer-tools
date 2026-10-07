# ship-site

Build a Vite site on your Mac, publish only the `dist/` folder to Vercel, copy the link.

## Run it

Inside your Vite project:

```sh
ship-site
```

Or without installing:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/ship-site/ship-site)
```

Install options, and the `developer-tools` hub, are in the [main README](../README.md#2-install-it).

## What happens

1. **Projects first.** It opens on every project across your saved Vercel accounts, refreshed from Vercel behind a spinner:
   ```
   ▸ Projects
      you are in ~/Desktop/mine/rig-register-web
    ❯ rig-register-web     Mohsin Dev   rig-register-web.vercel.app   ● this folder
      rig-register-web-v2  Mohsin Dev   rig-register-web-v2.vercel.app
      studiodesk           Mohsin Dev   studiodesk-chi.vercel.app
      + new project
      accounts
      refresh
      quit
   ```
   Inside a project folder, the Vercel project it publishes to is already selected. Press Enter.
2. **Folder.** Inside a project, that folder is built. Outside one, the folder the project was last built from is used, or it asks once and remembers.
3. **Where**: main website (production) or a test version (a fresh preview URL). Skip the question with `--prod` or `--preview`.
4. **Build**: the exact command is shown, then run. `npm run build`, or pnpm, yarn or bun if their lockfile is present.
5. **Publish**: the exact `vercel deploy` command is shown, then run from a temporary copy of `dist/` outside your git repo. No source, `node_modules`, `.env` or commit info leaves your Mac. The copy is deleted afterwards.
6. **Done**: the link is printed and copied. For the main website that is the project's domain.

**+ new project** creates one on Vercel by the name you type, asking which account only if you have more than one. **accounts** is where you add one (Vercel browser sign-in or a pasted token), pick its team scope, or remove it. First run with no account goes straight to adding one.

## Commands

```
ship-site             your Vercel projects; pick one, it builds and publishes
ship-site --prod      straight to the main website, no question asked
ship-site --preview   a fresh preview URL
ship-site ~/site      a project folder other than the current one
ship-site accounts    add or remove Vercel accounts
ship-site --version
```

## Needs

macOS, python3 (built in), node and the Vercel CLI. Missing node or the CLI? It asks before installing either.

## Where things live

| What | Where |
| --- | --- |
| Accounts, scopes, which project each folder uses | `~/.config/ship-site/config.json` (mode 0600) |
| Each account's sign-in | `~/.config/ship-site/accounts/<name>/` (mode 0700): the CLI session for browser logins, a `token` file for pasted tokens |
| Your normal `vercel login` | untouched, ship-site never uses it |

A `vercel.json` in your project root is uploaded along with `dist/`. Without one, a single-page-app rewrite is added so deep links work.

## Left out on purpose

Listing, deleting, pausing or rolling back deployments. The Vercel dashboard and `vercel ls`, `vercel rm`, `vercel rollback` already do that well.
