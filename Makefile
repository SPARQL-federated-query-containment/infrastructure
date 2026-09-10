# Single-node orchestration for the federated query-containment benchmark.
# Copy inventory.yml.example to inventory.yml and fill in your jFed address.

INVENTORY ?= inventory.yml
WARMUP    ?= 3
REPS      ?= 20
ENGINE    ?= both
SUITE     ?= all

# Connection settings for the single [wall] host, read straight from the inventory
# -- the same source Ansible uses -- so the bastion jump, key, and user are defined
# once (in inventory.yml) and these targets need no ~/.ssh/config entry of their own.
inv = $(shell ansible-inventory -i $(INVENTORY) --list 2>/dev/null | \
	python3 -c 'import sys,json;d=json.load(sys.stdin);h=d["wall"]["hosts"][0];print(d["_meta"]["hostvars"][h].get("$(1)",""))' 2>/dev/null)

HOST     := $(call inv,ansible_host)
SSH_KEY  := $(call inv,ansible_ssh_private_key_file)
SSH_USER := $(call inv,ansible_user)
SSH_ARGS := $(call inv,ansible_ssh_common_args)
SSH      := ssh -i $(SSH_KEY) -l $(SSH_USER) $(SSH_ARGS)
SCP      := scp -i $(SSH_KEY) $(SSH_ARGS)

.PHONY: ping check provision smoke run run-status progress results stop ssh

ping:        # Reachability of the node (bastion + agent + PEM)
	ansible wall -i $(INVENTORY) -m ping

check:       # Syntax-check the playbook
	ansible-playbook -i $(INVENTORY) --syntax-check playbook.yaml

provision:   # System + Docker + Bun, clone benchmark-runner, bun install, build the SpeCS image
	ansible-playbook -i $(INVENTORY) playbook.yaml

smoke:       # Synchronous 1-repetition sanity check (both engines, all suites)
	$(SSH) $(HOST) 'cd benchmark-runner && ~/.bun/bin/bun run smoke'

run: provision  # Provision (idempotent -- pulls latest benchmark-runner + reinstalls), then launch the benchmark on the node, detached (survives laptop disconnect)
	$(SSH) $(HOST) 'cd benchmark-runner && screen -dmS bench bash -lc "~/.bun/bin/bun src/run.ts -w $(WARMUP) -r $(REPS) --engine $(ENGINE) --suite $(SUITE) > ~/bench.log 2>&1"'
	@echo "benchmark started on $(HOST) (screen: bench, -w $(WARMUP) -r $(REPS)). Watch: make run-status"

run-status:  # Follow the benchmark log (blocks; Ctrl-C is safe, the run keeps going)
	$(SSH) $(HOST) 'tail -n 40 -f ~/bench.log'

progress:    # Non-following snapshot of the benchmark log
	$(SSH) $(HOST) 'tail -n 40 ~/bench.log 2>/dev/null || echo "(none yet)"'

results:     # Pull the JSON reports from the node into ./results/
	mkdir -p ./results
	$(SCP) -r "$(SSH_USER)@$(HOST):~/benchmark-runner/results/*" ./results/

stop:        # Stop the benchmark screen on the node
	$(SSH) $(HOST) 'screen -S bench -X quit 2>/dev/null || true'
	@echo "benchmark stopped on $(HOST)"

ssh:         # Open a shell on the node
	$(SSH) $(HOST)
