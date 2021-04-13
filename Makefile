debug:
	ldc2 -g micro.d

release:
	ldc2 --release -O3 -mcpu=native micro.d

release-lto:
	ldc2 --release -O3 -mcpu=native --flto=full micro.d

profile:
	ldc2 --output-s --release -O3 -mcpu=native --fdmd-trace-functions micro.d

asm:
	ldc2 --output-s --release -O3 -mcpu=native micro.d


.PHONY: release release-lto profile asm
