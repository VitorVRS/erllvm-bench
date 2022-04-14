ERLC = erlc
ERL_COMPILE_FLAGS = +debug_info
EBIN_DIR   = ebin
ERL_FILES  = $(wildcard *.erl)
BEAM_FILES = $(subst .erl,.beam,$(ERL_FILES))
METRIC = runtime

## Create needed folders (if not exist):
$(shell [ -d "diagrams/" ] || mkdir diagrams/)
$(shell [ -d "results/" ] || mkdir results/)
$(shell [ -d "$(EBIN_DIR)/" ] || mkdir $(EBIN_DIR)/)

## Check that certain programs are available
GNUPLOT := $(shell which gnuplot)
ifeq ($(GNUPLOT),)
$(error gnuplot is required but it is not found! Aborting.)
endif

FIG2PS  := $(shell which fig2ps)
ifeq ($(FIG2PS),)
$(error fig2ps is required but it is not found! Aborting.)
endif


.PHONY: all check clean distclean compile

all: $(BEAM_FILES) fasta
	if [ "$(METRIC)" = "runtime" ]; then \
		(cd src && make EBIN_DIR=../$(EBIN_DIR) ERLC=$(ERLC) ERL_COMPILE_FLAGS="$(ERL_COMPILE_FLAGS)" $@); \
	fi

%.beam: %.erl
	$(ERLC) $(ERL_COMPILE_FLAGS) -o $(EBIN_DIR) $<

fasta:
	gcc fasta.c -o fasta

clean:
	$(RM) ebin/$(BEAM_FILES) io_file fasta revcomp-input.txt regexdna-input.txt knucleotide-input.txt
	@(cd src && $(MAKE) EBIN_DIR=../$(EBIN_DIR) $@)

distclean: clean
	$(RM) -rI diagrams/ results/ ebin/


compile:
	@(cd src && make EBIN_DIR=../$(EBIN_DIR) ERLC=$(ERLC) ERL_COMPILE_FLAGS="$(ERL_COMPILE_FLAGS)" compile)
