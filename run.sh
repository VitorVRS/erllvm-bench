#!/usr/bin/env bash

## Erlc flags to be used in each case:
HIPE_FLAGS="+native +'{hipe,[{regalloc,coalescing},o2]}'"
ERLLVM_FLAGS="+native +'{hipe,[o2,to_llvm]}'"
ERJANG_FLAGS=""

## All arguments are made globals:
ACTION=      # The run function to be executed (run_all, run_class)
OTP=         # The OTP to be used for erlc and erl
COMP=        # The name of the compiler (beam, hipe, erllvm)
CLASS=       # The class of benchmarks to be executed
BENCH=       # The name of the benchmark to be executed
ITERATIONS=2 # Number of executions of benchmarks to collect statistics
DEBUG=0      # Debug mode (0=Off, 1=On)

run_all ()
{
    echo "Running all benchmark classes..."

    ## Look for all available Classes to run
    for c in `find ebin/ -maxdepth 1 -mindepth 1 -type d`; do
        CLASS=`basename $c`
        run_class
    done
}

run_class ()
{
    echo "   [Class] $CLASS"

    ## Get failing
    if [ -r failing ]; then
        skipped=`cat failing`
    else
        skipped=
    fi

    ## Get boilerplate
    BOILERPLATE=src/$CLASS/boilerplate
    if [ -r  $BOILERPLATE ]; then
        skipped="$skipped `cat $BOILERPLATE`"
    fi

    for f in `ls ebin/$CLASS/*.beam`; do
        BENCH=`basename $f .beam`
        ## Skip file if in failing or boileprlate
        SKIP="no"
        for s in $skipped; do
            if [ "$BENCH" = "$s" ]; then
                SKIP="yes"
                break
            fi
        done
        if [ "$SKIP" = "yes" ]; then
            continue
        fi
        ## Else run benchmark
        run_benchmark
    done
}

run_benchmark ()
{
    echo "   --- $BENCH"

    EBIN_DIRS=`find ebin/ -maxdepth 1 -mindepth 1 -type d`

    if [ "$COMP" = "erjang" ]; then
        $OTP_ROOT/erjang/ej -pa ebin/ $EBIN_DIRS -noshell -s run_benchmark run \
        $BENCH $COMP $ITERATIONS erjang -s erlang halt
    else
        $OTP/bin/erl -pa ebin/ $EBIN_DIRS -noshell -s run_benchmark run \
        $BENCH $COMP $ITERATIONS other -s erlang halt
    fi

}


plot_diagram ()
{
    INPUT=$1
    HASH=`basename $INPUT .res`
    TMP_DIR=/dev/shm/erllvm-bench-diagrams
    SCRIPTS_DIR=gnuplot_scripts
    DIAGRAMS_DIR=diagrams
    TMP_PERF=$TMP_DIR/speedup.perf
    echo "Plotting results..."

    mkdir -p $TMP_DIR
    ## Copy speedup.perf template and append only speedups:
    cp $SCRIPTS_DIR/speedup.perf $TMP_PERF
    cat results/$INPUT | awk '{print $1 "\t " $2 "\t " $3}' >> $TMP_PERF

    ## Create diagram in diagram:
    $SCRIPTS_DIR/bargraph.pl $TMP_PERF > $DIAGRAMS_DIR/$HASH.eps 2> /dev/null
    rm -rf $TMP_DIR
}

spinner () {
    PROC=$1;COUNT=0
    echo -n "Please wait... "
    while [ -d /proc/$PROC ];do
        while [ "$COUNT" -lt 10 ];do
            echo -n '  ' ; sleep 0.1
            ((COUNT++))
        done
        until [ "$COUNT" -eq 0 ];do
            echo -n ' ' ; sleep 0.1
            ((COUNT -= 1))
        done
    done
    echo "done!"
}

usage ()
{
    cat << EOF
Usage: $0 options OTP_ROOT

This script runs the benchmarks using the provided OTP directory (first
non-option argument) as root and creates the corresponding diagrams.

In the OTP directory provided there should be 3 subdirectories
including complete OTP installations:
  * otp_beam: This OTP is used to run BEAM stuff and all modules are
              in BEAM.
  * otp_hipe: This OTP is used to run HiPE stuff and is has been
              compiled with --enable-native-libs.
  * otp_erllvm: This OTP is used to run ErLLVM stuff and is has been
                compiled with --enable-native-libs and [to_llvm].

OPTIONS:
  -h    Show this message
  -a    Run all available benchmarks (default)
  -c    Benchmark class to run
  -n    Number of iterations (default=$ITERATIONS)

Examples:
  1) $0 -c shootout -n 3 ~/git/otp
  2) $0 -a ~/git/otp
  3) $0 -a -n 5 ~/git/otp
EOF
}

main ()
{
    while getopts "hadn:c:" OPTION; do
        case $OPTION in
            h|\?)
                usage
                exit 0
                ;;
            a)
                ACTION=run_all
                ;;
            c) ## Run *only* specified benchmark class:
                ACTION=run_class
                CLASS=$OPTARG
                ;;
            n)
                ITERATIONS=$OPTARG
                ;;
            d)
                DEBUG=1
                ;;
        esac
    done
    ## $1 is now the first non-option argument, $2 the second, etc
    shift $(($OPTIND - 1))
    OTP_ROOT=$1

    ## If ACTION is not set something went wrong (probably the script was
    ## called with no args):
    if [ -z $ACTION ]; then
        usage
        exit 1
    fi

    if [ $DEBUG -eq 1 ]; then
        cat << EOF
-- Debug info:
  Iter         = $ITERATIONS
  Run          = $ACTION
  Class        = $CLASS
  OTP          = $OTP_ROOT
  HiPE_FLAGS   = $HIPE_FLAGS
  ErLLVM_FLAGS = $ERLLVM_FLAGS
  Erjang_Flags = $ERJANG_FLAGS
EOF
    fi

    echo "Executing $ITERATIONS iterations/benchmark."
    for COMP in "beam" "hipe" "erllvm" ;  do
        ## Proper compile
        make clean > /dev/null
        echo -n "  Re-compiling with $COMP. "
        ## Use the appropriate ERLC flags
        ERL_CFLAGS=
        if [ "$COMP" = "hipe" ]; then
            ERL_CFLAGS=$HIPE_FLAGS
        fi
        if [ "$COMP" = "erllvm" ]; then
            ERL_CFLAGS=$ERLLVM_FLAGS
        fi
        if [ "$COMP" = "erjang" ]; then
            ERL_CFLAGS=$ERJANG_FLAGS
        fi
        make ERLC=$OTP_ROOT/otp_$COMP/bin/erlc ERL_COMPILE_FLAGS="$ERL_CFLAGS" \
            > /dev/null 2>&1 &
        spinner $(pidof make)

        ## Proper run
        echo "  Running $COMP..."
        OTP=$OTP_ROOT/otp_$COMP
        $ACTION
    done

    python plot_diagrams.py
}

main $@
