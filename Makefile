.PHONY: all fmt lint spec build docs examples clean

AMEBA = ./lib/ameba/bin/ameba

all: fmt lint spec build

$(AMEBA): $(AMEBA).cr
	crystal build -o $@ $(AMEBA).cr

fmt:
	crystal tool format

lint: $(AMEBA)
	$(AMEBA)

spec:
	crystal spec -v

build:
	crystal build --no-codegen src/prof.cr

docs:
	crystal docs

examples:
	cd examples/benchmark && shards install && crystal run src/benchmark.cr

clean:
	rm -rf docs
	rm -rf bin
