#!/bin/sh

#echo 'run spectralnorm in D:'
#time ./spectralnorm 5500

echo 'run chameneosredux in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts chameneosredux 6000000

