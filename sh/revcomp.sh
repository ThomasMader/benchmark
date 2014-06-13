#!/bin/sh

#echo 'run spectralnorm in D:'
#time ./spectralnorm 5500

echo 'run revcomp in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts revcomp 0 < revcomp-input25000000.txt

