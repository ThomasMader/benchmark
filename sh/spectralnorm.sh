#!/bin/sh

echo 'run spectralnorm in D:'
time ./spectralnorm 5500

echo 'run spectralnorm in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts spectralnorm 5500
