#!/usr/bin/env bash

OTP_LIST="beam beamasm24 beamasm25 hipe erllvm"

## Erlc flags to be used in each case:
HIPE_FLAGS="+native +'{hipe,[{regalloc,coalescing},o2]}'"
ERLLVM_FLAGS="+native +'{hipe,[o2,to_llvm]}'"

## All arguments are made globals:
ACTION=      # The run function to be executed (run_all, run_class)
METRIC="runtime"
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
    for c in `find src/ -maxdepth 1 -mindepth 1 -type d`; do
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
    if [ -r $BOILERPLATE ]; then
        skipped="$skipped `cat $BOILERPLATE`"
    fi

    local _BENCH_WILDCARD="ebin/$CLASS/*.beam"

    if [ "$METRIC" = "compile" ]; then
        _BENCH_WILDCARD="src/$CLASS/*.erl"   
    fi

    if [ "$METRIC" = "size" ]; then
        _BENCH_WILDCARD="src/$CLASS/*.erl"   
    fi

    for f in `ls $_BENCH_WILDCARD`; do
        BENCH=`basename $f .beam`
        BENCH=`basename $BENCH .erl`
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

run_startup_benchmark()
{
    local _CMD=""
    touch results/startup_$COMP.res
    _CMD="perf stat --metric-only --log-fd 1 $OTP/bin/erl -pa ebin/ $@ -noshell -s $BENCH module_info -s erlang halt +S 1"
    local _RESULTS=""
    local _TMP=""
    for a in $(seq 1 $ITERATIONS); do
        _TMP=$($_CMD | grep 'seconds time elapsed' | cut -d ' ' -f 8 | sed -e "s/,/\./g")
        _RESULTS="$_RESULTS $_TMP"
    done
    local _DATA=""
    _DATA=$(echo $_RESULTS | tr -s " " "\n" | sort | awk 'NF > 0')

    local _MEDIAN=""
    _MEDIAN=$(echo $_DATA | tr -s " " "\n" | awk ' { a[i++]=$1; } END { x=int((i+1)/2); if (x < (i+1)/2) print (a[x-1]+a[x])/2; else print a[x-1]; }')

    local _STDDEV=""
    _STDDEV=$(echo $_DATA | tr -s " " "\n" | awk '{for(i=1;i<=NF;i++) {sum[i] += $i; sumsq[i] += ($i)^2}} END {for (i=1;i<=NF;i++) {printf "%f\n", sqrt((sumsq[i]-sum[i]^2/NR)/NR)}}')
    echo "$BENCH    $_MEDIAN" >> results/startup_$COMP.res
    echo "$BENCH    $_STDDEV" >> results/startup_$COMP-err.res
}

run_benchmark ()
{
    local _CMD=""
    echo "   --- $BENCH"

    EBIN_DIRS=`find ebin/ -maxdepth 1 -mindepth 1 -type d`


    if [ "$METRIC" = "startup" ]; then
        run_startup_benchmark $EBIN_DIRS
    else
        _CMD="$OTP/bin/erl -pa ebin/ $EBIN_DIRS -noshell -s run_benchmark run $METRIC $CLASS $BENCH $COMP $ITERATIONS -s erlang halt +S 1"
        echo $_CMD
        $_CMD
    fi
}

collect_results ()
{
    echo "Collecting results..."

    local _FILES=""
    local _FILES_ERR=""

    for COMP in $OTP_LIST; do
        _FILES="${_FILES} results/${METRIC}_${COMP}.res"
    done

    for COMP in $OTP_LIST; do
        _FILES_ERR="${_FILES_ERR} results/${METRIC}_${COMP}-err.res"
    done

    echo "### Benchmark BEAM/BEAMASM24  BEAM/BEAMASM25  BEAM/HIPE   BEAM/ERLLVM BEAM    BEAMASM24   BEAMASM25   HIPE    ERLLVM (secs)" \
        > results/$METRIC.res
    pr -J -m -t $_FILES \
        | gawk '{print $1 "\t" $2/$4 "\t" $2/$6 "\t" $2/$8 "\t" $2/$10 "\t\t" $2 "\t" $4 "\t" $6 "\t" $8 "\t" $10}' \
        >> results/$METRIC.res
    ## Print average performance results of current execution:
    awk '{btl += $2; htl += $3} END {print "Runtime BTL:", btl/(NR-1), \
        "Runtime HTL:", htl/(NR-1)}' results/$METRIC.res

    echo "### Standard deviation BEAM BEAMASM24 BEAMASM25   HIPE    ERLLVM (millisecs)" \
        > results/$METRIC-err.res
    pr -J -m -t $_FILES_ERR \
        | gawk '{print $1 "\t" $2 "\t" $4 "\t" $6 "\t" $8 "\t" $10}' \
        >> results/$METRIC-err.res
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
    cat results/$INPUT | awk '{print $1 "\t " $2 "\t " $3 "\t " $4 "\t " $5}' >> $TMP_PERF

    cat $TMP_PERF

    ## Create diagram in diagram:
    echo "$SCRIPTS_DIR/bargraph.pl $TMP_PERF > $DIAGRAMS_DIR/$HASH.eps"
    $SCRIPTS_DIR/bargraph.pl $TMP_PERF > $DIAGRAMS_DIR/$HASH.eps
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
  -m    Metric to be collected (default=runtime)
        Available options are:
        * runtime
        * compile (compilation time)
        * size (code size loaded into memory)

Examples:
  1) $0 -c shootout -n 3 ~/git/otp
  2) $0 -a ~/git/otp
  3) $0 -a -n 5 ~/git/otp
EOF
}

main ()
{
    while getopts "hadm:n:c:" OPTION; do
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
            m)
                METRIC=$OPTARG
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
EOF
    fi

    echo "Executing $ITERATIONS iterations/benchmark."
    for COMP in $OTP_LIST; do

        ## Proper compile
        make clean > /dev/null
        ## Remove intermediate files from un-completed former run
        if [ -r results/$METRIC_$COMP.res ]; then
          rm results/$METRIC_$COMP.res
          touch results/$METRIC_$COMP.res
        fi

        echo -n "  Re-compiling with $COMP. "
        ## Use the appropriate ERLC flags
        ERL_CFLAGS=
        if [ "$COMP" = "hipe" ]; then
            ERL_CFLAGS=$HIPE_FLAGS
        fi
        if [ "$COMP" = "erllvm" ]; then
            ERL_CFLAGS=$ERLLVM_FLAGS
        fi
        make ERLC=$OTP_ROOT/otp_$COMP/bin/erlc ERL_COMPILE_FLAGS="$ERL_CFLAGS" METRIC=$METRIC \
            > /dev/null 2>&1 &
        spinner $(pidof make)

        ## Proper run
        echo "  Running $COMP..."
        OTP=$OTP_ROOT/otp_$COMP
        $ACTION
    done

    ## Collect results in results/runtime.res:
    collect_results

    ## Plot results:
    plot_diagram $METRIC.res

    ## Backup all result files & diagrams to unique .res files:
    NEW_SUFFIX=`date +"%y.%m.%d-%H:%M:%S"`

    # move main results
    mv results/$METRIC.res results/$METRIC-$NEW_SUFFIX.res
    mv results/$METRIC-err.res results/$METRIC-err-$NEW_SUFFIX.res

    # move individual results
    for c in $OTP_LIST; do
        mv results/$METRIC\_$c.res results/$METRIC\_$c-$NEW_SUFFIX.res
        mv results/$METRIC\_$c-err.res results/$METRIC\_$c-err-$NEW_SUFFIX.res
    done;
    mv diagrams/$METRIC.eps diagrams/$METRIC-$NEW_SUFFIX.eps
}

main $@
