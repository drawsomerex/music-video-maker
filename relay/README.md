# Bug-report relay (one-time setup, about 10 minutes, free)

The app's **Help ▸ Report a Problem…** sends a report to this tiny Cloudflare Worker, which files it as an **Issue** in the GitHub repo.
People who report do **not** need a GitHub account. The GitHub token lives only inside Cloudflare — never in the app or this repo.

## Set it up
1. Make a free account at <https://dash.cloudflare.com> and open **Workers & Pages ▸ Create ▸ Worker**. Name it e.g. `mvm-reports`. Deploy, then **Edit code** and paste in `relay/worker.js`. Deploy again.
2. On GitHub: **Settings ▸ Developer settings ▸ Personal access tokens ▸ Fine-grained tokens ▸ Generate**. Repository access: *Only select repositories → music-video-maker*. Permissions: **Issues: Read and write** (nothing else). Copy the token.
3. In the Worker: **Settings ▸ Variables and Secrets**: add secret `GITHUB_TOKEN` = the token, and variable `REPO` = `drawsomerex/music-video-maker`.
4. *(Optional, stops spam)* **Workers ▸ KV ▸ Create namespace** `limits`, then in the Worker's **Settings ▸ Bindings** add a KV binding named `LIMITS`.
5. Copy the Worker's address (like `https://mvm-reports.<you>.workers.dev`) and put it in `scripts/release.conf` as `REPORT_URL=…` (it is not a secret). Release a new version.
6. On GitHub, create the label `user-report` (and optionally `in-progress`).

## Using it
- New reports appear at <https://github.com/drawsomerex/music-video-maker/issues> (and in the free GitHub phone app).
- Write a comment (it is shown to the person who reported), then **Close** the issue = **completed**. Add the label `in-progress` to show "Being worked on".
- The app checks the status of the reports its user sent (public GitHub data, no login) and shows *Received / Being worked on / Done* and your comment.

Reports contain only what the person typed plus the app version, macOS version and the type of Mac — never their lyrics, files, or keys.
