debug:
	ldc2 -g zero.d

release:
	ldc2 --release -O3 -mcpu=native zero.d

release-lto:
	ldc2 --release -O3 -mcpu=native --flto=full zero.d

profile:
	ldc2 --output-s --release -O3 -mcpu=native --fdmd-trace-functions zero.d

asm:
	ldc2 --output-s --release -O3 -mcpu=native zero.d


.PHONY: release release-lto profile asm
