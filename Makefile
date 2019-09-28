.PHONY: local lint build

local: build
	luarocks --lua-version=5.1 make --local payments-dev-1.rockspec

build: 
	moonc payments lint_config.moon
 
lint:
	moonc -l payments

