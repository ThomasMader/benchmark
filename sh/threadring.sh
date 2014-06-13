#!/bin/sh

#echo 'run spectralnorm in D:'
#time ./spectralnorm 5500

echo 'run threadring in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts threadring 50000000 

