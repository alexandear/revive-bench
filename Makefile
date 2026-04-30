SHELL := /usr/bin/env bash

REVIVE_MODULE ?= github.com/mgechev/revive
BASE_REF ?= v1.15.0
CANDIDATE_REF ?= HEAD

BIN_DIR := $(CURDIR)/bin
BASE_BIN := $(BIN_DIR)/revive-base
CANDIDATE_BIN := $(BIN_DIR)/revive-candidate
FAST_TARGETS_FILE := $(CURDIR)/targets/repos-fast.txt
ALL_TARGETS_FILE := $(CURDIR)/targets/repos-all.txt
ISSUES_RESULTS_DIR := $(CURDIR)/results/issues
RULE_ISSUES_RESULTS_DIR := $(CURDIR)/results/rule-issues
RULE_ISSUES_CONFIG := $(CURDIR)/configs/rule-issues.toml
REVIVE_ISSUES_CONFIG := $(CURDIR)/configs/revive-issues.toml

define INSTALL_REVIVE_REF
	@set -e; \
	mkdir -p "$(BIN_DIR)"; \
	module_raw="$(REVIVE_MODULE)"; \
	module="$$module_raw"; \
	repo_url=""; \
	if [[ "$$module" == http://* || "$$module" == https://* ]]; then \
		repo_url="$$module"; \
		module="$${module#https://}"; \
		module="$${module#http://}"; \
		module="$${module%.git}"; \
	else \
		repo_url="https://$$module"; \
	fi; \
	if GOBIN="$(BIN_DIR)" go install "$$module@$(1)" >/dev/null 2>&1; then \
		mv "$(BIN_DIR)/revive" "$(2)"; \
		exit 0; \
	fi; \
	echo "go install $$module@$(1) failed, trying checkout fallback via $$repo_url" >&2; \
	TMP_REVIVE_DIR=$$(mktemp -d); \
	trap 'rm -rf "$$TMP_REVIVE_DIR"' EXIT; \
	git clone --quiet --depth 1 "$$repo_url" "$$TMP_REVIVE_DIR"; \
	git -C "$$TMP_REVIVE_DIR" fetch --depth 1 origin "$(1)" >/dev/null 2>&1; \
	git -C "$$TMP_REVIVE_DIR" checkout --detach FETCH_HEAD >/dev/null 2>&1; \
	cd "$$TMP_REVIVE_DIR" && GOBIN="$(BIN_DIR)" go install .; \
	mv "$(BIN_DIR)/revive" "$(2)"
endef

.PHONY: help setup-targets setup-targets-fast setup-targets-all install-hyperfine install-base install-candidate bench bench-compare bench-fast bench-compare-fast bench-all bench-compare-all issues issues-fast issues-all issues-compare issues-compare-fast issues-compare-all rule-issues clean

help:
	@echo "Targets:"
	@echo "  make setup-targets      Clone/update fast benchmark repositories"
	@echo "  make setup-targets-fast Clone/update fast benchmark repositories"
	@echo "  make setup-targets-all  Clone/update all benchmark repositories"
	@echo "  make install-hyperfine  Install hyperfine (macOS with brew)"
	@echo "  make install-base       Build baseline revive binary"
	@echo "  make install-candidate  Build candidate revive binary"
	@echo "  make bench              Run fast single-binary benchmark (candidate only)"
	@echo "  make bench-compare      Run fast comparison benchmark"
	@echo "  make bench-fast         Run fast single-binary benchmark (candidate only)"
	@echo "  make bench-compare-fast Run fast comparison benchmark"
	@echo "  make bench-all          Run all single-binary benchmark (candidate only)"
	@echo "  make bench-compare-all  Run all comparison benchmark"
	@echo "  make issues             Count revive issues in fast repos (candidate only)"
	@echo "  make issues-fast        Count revive issues in fast repos (candidate only)"
	@echo "  make issues-all         Count revive issues in all repos (candidate only)"
	@echo "  make issues-compare     Compare baseline vs candidate issue counts (fast)"
	@echo "  make issues-compare-fast Compare baseline vs candidate issue counts (fast)"
	@echo "  make issues-compare-all Compare baseline vs candidate issue counts (all)"
	@echo "  make rule-issues        Compare per-rule issue counts across repeated runs on one repo (candidate only)"
	@echo "  make clean              Remove local binaries and results"

setup-targets:
	TARGETS_FILE="$(FAST_TARGETS_FILE)" ./scripts/setup-targets.sh

setup-targets-fast:
	TARGETS_FILE="$(FAST_TARGETS_FILE)" ./scripts/setup-targets.sh

setup-targets-all:
	TARGETS_FILE="$(ALL_TARGETS_FILE)" ./scripts/setup-targets.sh

install-hyperfine:
	@if command -v brew >/dev/null 2>&1; then \
		brew list hyperfine >/dev/null 2>&1 || brew install hyperfine; \
	else \
		echo "Install hyperfine manually: https://github.com/sharkdp/hyperfine"; \
		exit 1; \
	fi

install-base:
	$(call INSTALL_REVIVE_REF,$(BASE_REF),$(BASE_BIN))

install-candidate:
	$(if $(filter HEAD,$(CANDIDATE_REF)), \
		mkdir -p "$(BIN_DIR)"; \
		go build -o "$(CANDIDATE_BIN)" github.com/mgechev/revive, \
		$(call INSTALL_REVIVE_REF,$(CANDIDATE_REF),$(CANDIDATE_BIN)))

bench:
	./scripts/bench.sh --targets-file "$(FAST_TARGETS_FILE)" --candidate-bin "$(CANDIDATE_BIN)"

bench-compare:
	./scripts/bench.sh --targets-file "$(FAST_TARGETS_FILE)" --base-bin "$(BASE_BIN)" --candidate-bin "$(CANDIDATE_BIN)"

bench-fast:
	./scripts/bench.sh --targets-file "$(FAST_TARGETS_FILE)" --candidate-bin "$(CANDIDATE_BIN)"

bench-compare-fast:
	./scripts/bench.sh --targets-file "$(FAST_TARGETS_FILE)" --base-bin "$(BASE_BIN)" --candidate-bin "$(CANDIDATE_BIN)"

bench-all:
	./scripts/bench.sh --targets-file "$(ALL_TARGETS_FILE)" --candidate-bin "$(CANDIDATE_BIN)"

bench-compare-all:
	./scripts/bench.sh --targets-file "$(ALL_TARGETS_FILE)" --base-bin "$(BASE_BIN)" --candidate-bin "$(CANDIDATE_BIN)"

issues:
	./scripts/count-issues.sh --targets-file "$(FAST_TARGETS_FILE)" --revive-bin "$(CANDIDATE_BIN)" --details-dir "$(ISSUES_RESULTS_DIR)/fast/candidate"

issues-fast:
	./scripts/count-issues.sh --targets-file "$(FAST_TARGETS_FILE)" --revive-bin "$(CANDIDATE_BIN)" --details-dir "$(ISSUES_RESULTS_DIR)/fast/candidate"

issues-all:
	./scripts/count-issues.sh --targets-file "$(ALL_TARGETS_FILE)" --revive-bin "$(CANDIDATE_BIN)" --details-dir "$(ISSUES_RESULTS_DIR)/all/candidate"

issues-compare:
	@BASE_VER="$$("$(BASE_BIN)" -version 2>/dev/null | head -n1 || true)"; \
	if [[ -z "$$BASE_VER" ]]; then BASE_VER="$(BASE_BIN)"; fi; \
	echo "=== Baseline ($$BASE_VER) ==="
	@./scripts/count-issues.sh --targets-file "$(FAST_TARGETS_FILE)" --revive-bin "$(BASE_BIN)" --config "$(REVIVE_ISSUES_CONFIG)" --details-dir "$(ISSUES_RESULTS_DIR)/fast/baseline"
	@echo
	@CANDIDATE_VER="$$("$(CANDIDATE_BIN)" -version 2>/dev/null | head -n1 || true)"; \
	if [[ -z "$$CANDIDATE_VER" ]]; then CANDIDATE_VER="$(CANDIDATE_BIN)"; fi; \
	echo "=== Candidate ($$CANDIDATE_VER) ==="
	@./scripts/count-issues.sh --targets-file "$(FAST_TARGETS_FILE)" --revive-bin "$(CANDIDATE_BIN)" --config "$(REVIVE_ISSUES_CONFIG)" --details-dir "$(ISSUES_RESULTS_DIR)/fast/candidate"

issues-compare-fast:
	@BASE_VER="$$("$(BASE_BIN)" -version 2>/dev/null | head -n1 || true)"; \
	if [[ -z "$$BASE_VER" ]]; then BASE_VER="$(BASE_BIN)"; fi; \
	echo "=== Baseline ($$BASE_VER) ==="
	@./scripts/count-issues.sh --targets-file "$(FAST_TARGETS_FILE)" --revive-bin "$(BASE_BIN)" --config "$(REVIVE_ISSUES_CONFIG)" --details-dir "$(ISSUES_RESULTS_DIR)/fast/baseline"
	@echo
	@CANDIDATE_VER="$$("$(CANDIDATE_BIN)" -version 2>/dev/null | head -n1 || true)"; \
	if [[ -z "$$CANDIDATE_VER" ]]; then CANDIDATE_VER="$(CANDIDATE_BIN)"; fi; \
	echo "=== Candidate ($$CANDIDATE_VER) ==="
	@./scripts/count-issues.sh --targets-file "$(FAST_TARGETS_FILE)" --revive-bin "$(CANDIDATE_BIN)" --config "$(REVIVE_ISSUES_CONFIG)" --details-dir "$(ISSUES_RESULTS_DIR)/fast/candidate"

issues-compare-all:
	@BASE_VER="$$("$(BASE_BIN)" -version 2>/dev/null | head -n1 || true)"; \
	if [[ -z "$$BASE_VER" ]]; then BASE_VER="$(BASE_BIN)"; fi; \
	echo "=== Baseline ($$BASE_VER) ==="
	@./scripts/count-issues.sh --targets-file "$(ALL_TARGETS_FILE)" --revive-bin "$(BASE_BIN)" --config "$(REVIVE_ISSUES_CONFIG)" --details-dir "$(ISSUES_RESULTS_DIR)/all/baseline"
	@echo
	@CANDIDATE_VER="$$("$(CANDIDATE_BIN)" -version 2>/dev/null | head -n1 || true)"; \
	if [[ -z "$$CANDIDATE_VER" ]]; then CANDIDATE_VER="$(CANDIDATE_BIN)"; fi; \
	echo "=== Candidate ($$CANDIDATE_VER) ==="
	@./scripts/count-issues.sh --targets-file "$(ALL_TARGETS_FILE)" --revive-bin "$(CANDIDATE_BIN)" --config "$(REVIVE_ISSUES_CONFIG)" --details-dir "$(ISSUES_RESULTS_DIR)/all/candidate"

rule-issues:
	@if [[ -z "$(RULE_REPO)" ]]; then \
		echo "RULE_REPO is required, e.g. make rule-issues RULE_REPO=go-github RULE_RUNS=5"; \
		exit 1; \
	fi
	@./scripts/compare-rule-issues.sh \
		--revive-bin "$(CANDIDATE_BIN)" \
		--repo "$(RULE_REPO)" \
		--config "$(RULE_ISSUES_CONFIG)" \
		--runs "$(if $(RULE_RUNS),$(RULE_RUNS),3)" \
		--details-dir "$(RULE_ISSUES_RESULTS_DIR)"

clean:
	rm -rf "$(BIN_DIR)" "$(CURDIR)/results"
