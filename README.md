# infrastructure

Ansible that stands up a **single jFed Virtual Wall node** and runs the
[`benchmark-runner`](https://github.com/SPARQL-federated-query-containment/benchmark-runner)
federated SPARQL query-containment benchmark on it: the staged bag-set containment
procedure (`bfc`) against the SpeCS set-containment oracle (`specs`), over the
committed pair suites — four scenario families (`operators`, `star`, `branching`,
`ucfq`) plus a `-scale` twin of each. Outcomes and timings are written as JSON.

One node does everything — clone, build the SpeCS Docker image, run. There is no
federation, no data generation (the pairs ship with the repo), and no data transfer.

## 1. Prerequisites

- A jFed experiment swapped in with **one node** on **Ubuntu 20.04**, and its
  **PEM key** at `~/.ssh/ilabt.pem` (`chmod 600`).
- Ansible on your laptop.
- Your **GitHub SSH key in the local agent** (agent-forwarded so the node can clone
  the repo + submodules):
  ```bash
  ssh-add ~/.ssh/id_ed25519 && ssh-add -l
  ```

Docker and Bun are installed automatically; you don't set them up.

## 2. SSH config

jFed uses your login key for SSH (dumped to a throwaway file under `~/.jFed/tmp/`).
Copy it once:

```bash
cp "$(ls -t ~/.jFed/tmp/sshKeyUsr*.pem | head -1)" ~/.ssh/ilabt.pem && chmod 600 ~/.ssh/ilabt.pem
```

Add to `~/.ssh/config`. The wildcard matches any Virtual Wall node, so you never
edit it on a swap-in. `ssh-rsa` is re-enabled because some node images only offer
SHA-1 host keys:

```sshconfig
Host wall-bastion
    HostName bastion.ilabt.imec.be
    User fffbrtamuge
    IdentityFile ~/.ssh/ilabt.pem

Host *.wall2.ilabt.iminds.be
    User brtamuge
    IdentityFile ~/.ssh/ilabt.pem
    ProxyJump wall-bastion
    ForwardAgent yes
    ServerAliveInterval 120
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
```

## 3. Configure

```bash
cp inventory.yml.example inventory.yml
```

Edit the one `ansible_host` to your node's wall address. `inventory.yml` is
git-ignored. Repo, version, and Bun/SpeCS knobs live in `group_vars/all.yml`.

## 4. Run

Run the steps one at a time — each returns. `provision` needs the control session
to stay connected (~10–15 min the first time, a few minutes on re-runs — it is
idempotent); `make run` re-runs `provision` before it launches, so it needs the
connection until the benchmark starts, then detaches into `screen` **on the node**
and survives the control session dropping.

```bash
ssh-add ~/.ssh/id_ed25519     # GitHub key in the agent (the node clones the repo)

make ping            # 💻 connected, ~seconds  — node reachable
make provision       # 💻 connected, ~10-15 min — system + Docker + Bun, clone
                     #   benchmark-runner (+submodules), bun install, build the SpeCS image.
                     #   Re-running this always picks up whatever solver commit is currently
                     #   pinned on benchmark-runner's main -- bump the solver submodule there
                     #   and re-provision to put the latest solver on the wall.
make smoke           # 💻 connected, minutes    — optional: 1-repetition sanity check,
                     #   prints correct / incorrect / unknown / error counts
make run             # 💻 connected, ~minutes   — re-runs provision (idempotent: pulls
                     #   latest benchmark-runner + reinstalls), then launches -w 3 -r 20
                     #   (both engines, all suites), 20 min per-pair timeout, 8192MB z3
                     #   memory cap (sized for this node's 12GB), DETACHED. ✅ You can
                     #   disconnect once it starts.

make progress        # 💻 ~seconds  — non-blocking snapshot of ~/bench.log; repeat until done
make run-status      # 💻 (blocks)  — live-follow the benchmark log (Ctrl-C to stop)
make results         # 💻 minutes   — scp the JSON reports to ./results/
make stop            # stop the benchmark screen
```

Override the run shape on the command line, e.g. `make run REPS=10 SUITE=correctness`,
`make run ENGINE=bfc`, or `make run MEMORY=4096 TIMEOUT=600000` if you swap in a
smaller node.

### When can the control session drop?

The control session (your Ansible/SSH connection) only has to stay alive for
`provision` — bounded, tens of minutes. `make run` starts the benchmark inside
`screen` on the node and returns immediately; the connection can drop right after,
and you reconnect only to `make progress` / `make results`. `make run-status` blocks
to stream the log but holds no work — `Ctrl-C` and disconnect whenever; the run
keeps going on the node.

## Output

`make results` pulls `results/<timestamp>/{bfc,specs}.{correctness,scale}.json` from
the node into `./results/`. Each file carries its `meta` (environment, repetitions),
a `summary` (mean/median ms, outcome counts, `bySize` for the scale suite), and a
`results` map keyed by pair id. See the `benchmark-runner` README for the schema.
