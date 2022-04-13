DIRS = orbit-int shootout small

.PHONY: all clean compile

all:
	for d in $(DIRS); do (cd $$d && make ERLC=$(ERLC) ERL_COMPILE_FLAGS="$(ERL_COMPILE_FLAGS)" EBIN_DIR=../$(EBIN_DIR) $@); \
	done

clean:
	for d in $(DIRS); do (cd $$d && make EBIN_DIR=../$(EBIN_DIR) $@); done

compile:
	$(RM) ../results/compile.res; \
	for f in $(shell find . -name "*.erl"); do \
		(perf stat --metric-only -o stat.txt $(ERLC) $(ERL_COMPILE_FLAGS) -o$(EBIN_DIR) $$f); \
		(basename -z $$f .erl | sed -e "s/\x0/\t/" >> ../results/compile.res); \
		(cat stat.txt | grep "seconds time elapsed" | cut -d " " -f 8 | sed -e "s/,/./g" >> ../results/compile.res); \
	done

