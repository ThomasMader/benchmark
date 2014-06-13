#!/bin/sh

#echo 'run spectralnorm in D:'
#time ./spectralnorm 5500

echo 'run binarytrees in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts binarytrees 20 

