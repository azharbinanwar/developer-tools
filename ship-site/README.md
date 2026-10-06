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

Install options, and the `developer-tools` hub that runs every tool from one menu, are in the [main README](../README.md#2-install-it).

## What happens

1. **Checks**: node and the Vercel CLI. If either is missing it asks before installing it. Not signed in to Vercel? It runs `vercel login` and waits.
2. **Where**: main website (production) or a test version (a fresh preview URL). Skip the question with `--prod` or `--preview`.
3. **Build**: `npm run build`, or pnpm, yarn or bun if their lockfile is present.
4. **Publish**: only `dist/` is uploaded. Source, `node_modules` and `.env` files never leave your Mac.
5. **Done**: the link is printed and copied to your clipboard.

First run for a project links or creates a Vercel project named after `package.json`. Later runs remember it.

## Commands

```
ship-site             build this project and publish dist/ to Vercel
ship-site --prod      straight to the main website, no question asked
ship-site --preview   a fresh preview URL
ship-site ~/site      a project folder other than the current one
ship-site --version
```

## Needs

macOS and node. The Vercel CLI (`npm i -g vercel`) is offered on first run if missing.

Several Vercel accounts or teams? Run `vercel switch` first. The CLI's own login is what gets used.

## Where things live

| What | Where |
| --- | --- |
| Which Vercel project each folder belongs to | `~/.config/ship-site/<project>.json` |
| Vercel login | the Vercel CLI's own config, untouched |

A `vercel.json` in your project root is uploaded along with `dist/`. Without one, a single-page-app rewrite is added so deep links work.

## Left out on purpose

Listing, deleting, pausing or rolling back deployments. The Vercel dashboard and `vercel ls`, `vercel rm`, `vercel rollback` already do that well.
