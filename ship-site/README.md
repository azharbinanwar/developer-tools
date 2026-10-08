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

## Commands

```
ship-site              your Vercel projects; pick one, it builds and publishes
ship-site --prod       straight to the main website, no question asked
ship-site --preview    a fresh test URL, the main website untouched
ship-site --dry-run    check everything and show what would happen; changes nothing (also -n)
ship-site ~/site       treat that folder as the current project
ship-site accounts     add or remove Vercel accounts
ship-site -v           version
```

## What happens

### 1. Projects

```
▸ Projects
   you are in ~/Desktop/mine/rig-register-web
 ❯ rig-register-web       Mohsin Dev   rig-register-web.vercel.app   ● this folder
   rig-register-web-v2    Mohsin Dev   rig-register-web-v2.vercel.app
   studiodesk             Mohsin Dev   studiodesk-chi.vercel.app
   + new project
   accounts
   refresh
   quit
```

Every project across your saved accounts, refreshed from Vercel behind a spinner. Inside a project folder, the Vercel project it publishes to is preselected. Expired Vercel sign-ins are renewed on their own.

**+ new project** creates one on Vercel by the name you type, asking which account only if you have more than one. **accounts** adds one (Vercel browser sign-in or a pasted token, then its team scope) or removes one. With no account yet, it starts by adding one.

### 2. Folder

Inside a project, that folder is built. Outside one, the folder the project was last built from is used, or it asks once and remembers.

### 3. Where

**main website** (production) or **test version** (a fresh preview URL). `--prod` and `--preview` skip the question.

### 4. Version (main website only)

```
▸ Version  1.0.0
 ❯ publish as 1.0.0
   bump                next is 1.0.1, or type your own
```

Enter publishes as is. **bump** asks `New version [1.0.1] ›`: Enter takes it, or type any version like `1.1.0`. It updates `package.json` with `npm version <new> --no-git-tag-version`, so nothing is committed or tagged. If this version is already live, the header says **live already** and **bump** is preselected. Test versions never ask.

### 5. Build and publish

The exact commands are shown, then run: `npm run build` (or pnpm, yarn or bun from the lockfile), then `vercel deploy` from a temporary copy of `dist/` outside your git repo. No source, `node_modules`, `.env` or git commit info leaves your Mac, so Vercel's commit-author check never blocks it. The copy is deleted afterwards. If the build or deploy fails, Vercel's error is shown and it stops.

### 6. Done

The link is printed and copied. For the main website it is the project's domain.

## Dry run

`ship-site --dry-run` (or `-n`) walks the whole flow, checks everything, and changes nothing.

| Step | In a dry run |
| --- | --- |
| project list, refresh | ✅ runs (read-only) |
| add or remove an account | ✅ runs |
| new Vercel project | ⏭ says it would create it |
| version | ⏭ shows the new version, does not touch `package.json` |
| build script in `package.json` | ✅ checked |
| package manager installed | ✅ checked |
| Vercel login and project access | ✅ checked (read-only) |
| build | ⏭ shows the command |
| deploy | ⏭ shows the exact command |
| "last published" record | ⏭ not saved |

It ends with **dry run passed** or a list of ✗ problems to fix.

## Needs

macOS, python3 (built in), node and the Vercel CLI. Missing node or the CLI? It asks before installing either.

## Where things live

| What | Where |
| --- | --- |
| Accounts, scopes, project list, which project each folder uses, last published version | `~/.config/ship-site/config.json` (mode 0600) |
| Each account's sign-in | `~/.config/ship-site/accounts/<name>/` (mode 0700) |
| Your normal `vercel login` | untouched |

A `vercel.json` in your project root is uploaded with `dist/`. Without one, a single-page-app rewrite is added so deep links work. The only file it changes in your project is `package.json`'s version, and only when you pick **bump**.

## Left out on purpose

Listing, deleting, pausing or rolling back deployments. The Vercel dashboard and `vercel ls`, `vercel rm`, `vercel rollback` already do that well.
