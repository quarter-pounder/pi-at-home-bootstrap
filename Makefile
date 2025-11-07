.PHONY: %

DEFAULT_GOAL := help

%:
	@$(MAKE) -f common/Makefile $@

