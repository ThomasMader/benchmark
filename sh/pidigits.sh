#!/bin/sh

#echo 'run spectralnorm in D:'
#time ./spectralnorm 5500

echo 'run pidigits in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts pidigits 10000

